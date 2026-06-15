[CmdletBinding()]
param(
    [ValidateSet("init", "validate", "pull", "up", "down", "restart", "ps", "logs", "clean")]
    [string]$Action = "validate",

    [ValidateSet("all", "databases", "linkwarden", "davis", "freshrss", "ttrss", "kill-newsletter", "web", "monitoring")]
    [string]$Service = "all"
)

$ErrorActionPreference = "Stop"

$InstallDir = Split-Path -Parent $PSScriptRoot
$LocalDir = Join-Path $InstallDir "local"
$WorkDir = Join-Path $LocalDir "work"
$ConfigFile = Join-Path $LocalDir "vps.env"
$ConfigExample = Join-Path $LocalDir "vps.env.example"
$SecretsFile = Join-Path $LocalDir "secrets.env"
$SecretsExample = Join-Path $LocalDir "secrets.env.example"
$DatabasesOverride = Join-Path $LocalDir "databases.override.yml"
$TtrssOverride = Join-Path $LocalDir "ttrss.override.yml"
$KillNewsletterOverride = Join-Path $LocalDir "kill-newsletter.override.yml"
$MonitoringCompose = Join-Path $LocalDir "monitoring.compose.yml"

$CoreServices = @("linkwarden", "davis", "freshrss", "ttrss", "web")
$AllServices = @($CoreServices + "kill-newsletter")
$ManagedStacks = @("databases") + $AllServices + "monitoring"

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker est introuvable."
    }

    & docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose est indisponible."
    }
}

function Initialize-Local {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        Copy-Item -LiteralPath $ConfigExample -Destination $ConfigFile
        Write-Host "Configuration locale créée : $ConfigFile"
    }
    if (-not (Test-Path -LiteralPath $SecretsFile)) {
        Copy-Item -LiteralPath $SecretsExample -Destination $SecretsFile
        Write-Host "Secrets locaux créés : $SecretsFile"
    }
    if (-not (Select-String -LiteralPath $SecretsFile -Pattern "^POSTGRES_ADMIN_PASSWORD=" -Quiet)) {
        Add-Content -LiteralPath $SecretsFile -Encoding utf8 -Value "POSTGRES_ADMIN_PASSWORD=local_postgres_admin"
    }

    if ($IsLinux -or $IsMacOS) {
        & chmod 600 $ConfigFile $SecretsFile 2>$null
    }

    foreach ($name in $ManagedStacks) {
        $source = switch ($name) {
            "databases" { Join-Path $InstallDir "databases" }
            "monitoring" { Join-Path $InstallDir "monitoring" }
            default { Join-Path $InstallDir "services\$name" }
        }
        $target = Join-Path $WorkDir $name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item -Path (Join-Path $source "*") -Destination $target -Recurse -Force
    }

    $webIndex = Join-Path $WorkDir "web\html\index.php"
    if (-not (Test-Path -LiteralPath $webIndex)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $webIndex) | Out-Null
        Set-Content -LiteralPath $webIndex -Encoding utf8 -Value "<?php echo 'Test local PHP OK';"
    }
}

function Get-LocalEnvValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Default = ""
    )

    if (Test-Path -LiteralPath $ConfigFile) {
        $pattern = "^\s*$([regex]::Escape($Name))=(.*)$"
        foreach ($line in Get-Content -LiteralPath $ConfigFile -Encoding utf8) {
            if ($line -match $pattern) {
                return $Matches[1].Trim().Trim('"').Trim("'")
            }
        }
    }

    return $Default
}

function Test-LocalEnvEnabled {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [bool]$Default = $false
    )

    $defaultValue = if ($Default) { "true" } else { "false" }
    $value = (Get-LocalEnvValue -Name $Name -Default $defaultValue).ToLowerInvariant()
    return @("1", "true", "yes", "on") -contains $value
}

function Initialize-KillNewsletterSource {
    $repository = Get-LocalEnvValue `
        -Name "KILL_NEWSLETTER_REPOSITORY" `
        -Default "https://github.com/leafac/kill-the-newsletter.git"
    $reference = Get-LocalEnvValue `
        -Name "KILL_NEWSLETTER_REF" `
        -Default "a7bb41c2f483db33f4516c1c56f3db3d43fc959a"
    $target = Join-Path $WorkDir "kill-newsletter\app"

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git est requis pour récupérer Kill the Newsletter."
    }

    if (-not (Test-Path -LiteralPath (Join-Path $target ".git"))) {
        if (Test-Path -LiteralPath $target) {
            $entries = @(Get-ChildItem -LiteralPath $target -Force)
            if ($entries.Count -gt 0) {
                throw "Le répertoire $target existe mais n'est pas un dépôt Git."
            }
        }

        & git clone --filter=blob:none $repository $target
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de cloner Kill the Newsletter."
        }
    }

    $current = (& git -C $target rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Le dépôt Kill the Newsletter est invalide."
    }

    if ($current -ne $reference) {
        $changes = @(& git -C $target status --porcelain)
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de vérifier le dépôt Kill the Newsletter."
        }
        if ($changes.Count -gt 0) {
            throw "Le dépôt Kill the Newsletter contient des modifications locales ; impossible de sélectionner $reference."
        }

        & git -C $target remote set-url origin $repository
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de configurer le dépôt Kill the Newsletter."
        }
        & git -C $target fetch --depth 1 origin $reference
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de récupérer la révision Kill the Newsletter $reference."
        }
        & git -C $target checkout --detach FETCH_HEAD
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de sélectionner la révision Kill the Newsletter $reference."
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $target "package.json"))) {
        throw "Le dépôt Kill the Newsletter ne contient pas package.json."
    }
}

function Get-SelectedServices {
    if ($Service -eq "all") {
        return $CoreServices
    }

    return @($Service)
}

function Test-NeedsDatabases {
    return $Service -eq "all" -or
        $Service -eq "databases" -or
        $CoreServices -contains $Service
}

function Invoke-Stack {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $composeFile = if ($Name -eq "monitoring") {
        $MonitoringCompose
    }
    else {
        Join-Path $WorkDir "$Name\docker-compose.yml"
    }
    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "Projet local absent : $Name. Exécuter d'abord l'action init."
    }

    $dockerArguments = @(
        "compose",
        "--project-name", "vps-local-$Name",
        "--env-file", $ConfigFile,
        "--env-file", $SecretsFile,
        "-f", $composeFile
    )
    if ($Name -eq "databases") {
        $dockerArguments += @("-f", $DatabasesOverride)
    }
    elseif ($Name -eq "ttrss") {
        $dockerArguments += @("-f", $TtrssOverride)
    }
    elseif ($Name -eq "kill-newsletter") {
        $dockerArguments += @("-f", $KillNewsletterOverride)
    }
    elseif ($Name -eq "monitoring") {
        $dockerArguments += @("--profile", "containers", "--profile", "logs")
    }
    $dockerArguments += $Arguments

    & docker @dockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Échec Docker Compose pour $Name."
    }
}

function Start-LocalMonitoring {
    Invoke-Stack -Name "monitoring" -Arguments @(
        "up", "-d", "--remove-orphans", "grafana", "prometheus", "node-exporter"
    )

    if (Test-LocalEnvEnabled -Name "ENABLE_CONTAINER_METRICS" -Default $true) {
        Invoke-Stack -Name "monitoring" -Arguments @("up", "-d", "cadvisor")
    }
    else {
        Invoke-Stack -Name "monitoring" -Arguments @("rm", "--stop", "--force", "cadvisor")
    }

    if (Test-LocalEnvEnabled -Name "ENABLE_LOGS" -Default $true) {
        Invoke-Stack -Name "monitoring" -Arguments @("up", "-d", "loki", "alloy")
    }
    else {
        Invoke-Stack -Name "monitoring" -Arguments @(
            "rm", "--stop", "--force", "alloy", "alloy-init", "loki", "loki-init"
        )
    }
}

function Pull-LocalMonitoring {
    Invoke-Stack -Name "monitoring" -Arguments @(
        "pull", "prometheus-init", "grafana", "prometheus", "node-exporter"
    )

    if (Test-LocalEnvEnabled -Name "ENABLE_CONTAINER_METRICS" -Default $true) {
        Invoke-Stack -Name "monitoring" -Arguments @("pull", "cadvisor")
    }

    if (Test-LocalEnvEnabled -Name "ENABLE_LOGS" -Default $true) {
        Invoke-Stack -Name "monitoring" -Arguments @("pull", "loki-init", "loki", "alloy-init", "alloy")
    }
}

function Test-AllCompose {
    foreach ($name in $ManagedStacks) {
        Invoke-Stack -Name $name -Arguments @("config", "--quiet")
    }

    $extraStacks = @(
        @{
            Name = "gateway"
            File = Join-Path $InstallDir "gateway\docker-compose.yml"
            Profile = "manual"
        }
    )

    foreach ($stack in $extraStacks) {
        $arguments = @(
            "compose",
            "--project-name", "vps-local-$($stack.Name)",
            "--env-file", $ConfigFile,
            "--env-file", $SecretsFile,
            "-f", $stack.File
        )
        foreach ($profile in @($stack.Profile)) {
            $arguments += @("--profile", $profile)
        }
        $arguments += @("config", "--quiet")

        & docker @arguments

        if ($LASTEXITCODE -ne 0) {
            throw "Configuration Compose invalide : $($stack.Name)."
        }
    }
}

Initialize-Local
if ($Action -ne "init") {
    Assert-Docker
}

switch ($Action) {
    "init" {
        Write-Host "Environnement local préparé dans $WorkDir"
        Write-Host "Configuration : $ConfigFile"
        Write-Host "Secrets : $SecretsFile"
    }
    "validate" {
        Test-AllCompose
        Write-Host "Tous les projets Compose sont valides."
    }
    "pull" {
        if (Test-NeedsDatabases) {
            Invoke-Stack -Name "databases" -Arguments @("pull")
        }
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            if ($name -eq "kill-newsletter") {
                Initialize-KillNewsletterSource
                Invoke-Stack -Name $name -Arguments @("build", "--pull")
            }
            elseif ($name -eq "monitoring") {
                Pull-LocalMonitoring
            }
            elseif ($name -eq "web") {
                Invoke-Stack -Name $name -Arguments @("build", "--pull")
            }
            else {
                Invoke-Stack -Name $name -Arguments @("pull")
            }
        }
    }
    "up" {
        if (Test-NeedsDatabases) {
            Invoke-Stack -Name "databases" -Arguments @("up", "-d", "--wait")
        }
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            if ($name -eq "monitoring") {
                Start-LocalMonitoring
                continue
            }
            if ($name -eq "kill-newsletter") {
                Initialize-KillNewsletterSource
                Invoke-Stack -Name $name -Arguments @("up", "-d", "--build")
                continue
            }
            Invoke-Stack -Name $name -Arguments @("up", "-d")
        }

        Write-Host "Services locaux démarrés. Utiliser l'action ps puis les URLs documentées."
        if ($Service -eq "monitoring") {
            Write-Host "Grafana : http://localhost:3000"
            Write-Host "Prometheus : http://localhost:9090"
        }
    }
    "down" {
        [array]$selected = Get-SelectedServices
        [array]::Reverse($selected)
        foreach ($name in $selected) {
            if ($name -eq "databases") {
                continue
            }
            Invoke-Stack -Name $name -Arguments @("down", "--remove-orphans")
        }
        if ($Service -eq "all" -or $Service -eq "databases") {
            Invoke-Stack -Name "databases" -Arguments @("down", "--remove-orphans")
        }
    }
    "restart" {
        if ($Service -eq "all" -or $Service -eq "databases") {
            Invoke-Stack -Name "databases" -Arguments @("restart")
        }
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            if ($name -eq "monitoring") {
                Start-LocalMonitoring
                continue
            }
            Invoke-Stack -Name $name -Arguments @("restart")
        }
    }
    "ps" {
        if (Test-NeedsDatabases) {
            Write-Host "`n### databases"
            Invoke-Stack -Name "databases" -Arguments @("ps")
        }
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            Write-Host "`n### $name"
            Invoke-Stack -Name $name -Arguments @("ps")
        }
    }
    "logs" {
        if (Test-NeedsDatabases) {
            Write-Host "`n### databases"
            Invoke-Stack -Name "databases" -Arguments @("logs", "--tail=100")
        }
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            Write-Host "`n### $name"
            Invoke-Stack -Name $name -Arguments @("logs", "--tail=100")
        }
    }
    "clean" {
        $confirmation = Read-Host "Supprimer tous les conteneurs et les données locales de test ? Taper OUI"
        if ($confirmation -ne "OUI") {
            throw "Nettoyage annulé."
        }

        foreach ($name in $ManagedStacks) {
            Invoke-Stack -Name $name -Arguments @("down", "--volumes", "--remove-orphans")
        }

        $resolvedLocal = (Resolve-Path -LiteralPath $LocalDir).Path
        $resolvedWork = (Resolve-Path -LiteralPath $WorkDir).Path
        if (-not $resolvedWork.StartsWith($resolvedLocal, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Répertoire de travail hors de install/local."
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
        Write-Host "Données locales supprimées."
    }
}
