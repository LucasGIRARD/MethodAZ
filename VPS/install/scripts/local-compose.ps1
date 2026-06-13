[CmdletBinding()]
param(
    [ValidateSet("init", "validate", "pull", "up", "down", "restart", "ps", "logs", "clean")]
    [string]$Action = "validate",

    [ValidateSet("all", "databases", "linkwarden", "davis", "freshrss", "ttrss", "kill-newsletter", "web")]
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

$CoreServices = @("linkwarden", "davis", "freshrss", "ttrss", "web")
$AllServices = @($CoreServices + "kill-newsletter")
$ManagedStacks = @("databases") + $AllServices

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
        $source = if ($name -eq "databases") {
            Join-Path $InstallDir "databases"
        }
        else {
            Join-Path $InstallDir "services\$name"
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

function Get-SelectedServices {
    if ($Service -eq "all") {
        return $CoreServices
    }

    return @($Service)
}

function Invoke-Stack {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $composeFile = Join-Path $WorkDir "$Name\docker-compose.yml"
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
    $dockerArguments += $Arguments

    & docker @dockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Échec Docker Compose pour $Name."
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
        },
        @{
            Name = "monitoring"
            File = Join-Path $InstallDir "monitoring\docker-compose.yml"
            Profile = @("containers", "logs")
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
        Invoke-Stack -Name "databases" -Arguments @("pull")
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            if ($name -eq "web") {
                Invoke-Stack -Name $name -Arguments @("build", "--pull")
            }
            else {
                Invoke-Stack -Name $name -Arguments @("pull")
            }
        }
    }
    "up" {
        Invoke-Stack -Name "databases" -Arguments @("up", "-d", "--wait")
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            if ($name -eq "kill-newsletter" -and
                -not (Test-Path -LiteralPath (Join-Path $WorkDir "kill-newsletter\app\Dockerfile"))) {
                throw "Le dépôt Kill the Newsletter doit être cloné dans install/local/work/kill-newsletter/app."
            }
            Invoke-Stack -Name $name -Arguments @("up", "-d")
        }

        Write-Host "Services locaux démarrés. Utiliser l'action ps puis les URLs documentées."
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
            Invoke-Stack -Name $name -Arguments @("restart")
        }
    }
    "ps" {
        Write-Host "`n### databases"
        Invoke-Stack -Name "databases" -Arguments @("ps")
        foreach ($name in Get-SelectedServices) {
            if ($name -eq "databases") {
                continue
            }
            Write-Host "`n### $name"
            Invoke-Stack -Name $name -Arguments @("ps")
        }
    }
    "logs" {
        Write-Host "`n### databases"
        Invoke-Stack -Name "databases" -Arguments @("logs", "--tail=100")
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
