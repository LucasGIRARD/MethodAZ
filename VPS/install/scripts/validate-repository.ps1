[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = (
    Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
).Path
$Errors = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $Root -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    foreach ($parseError in $parseErrors) {
        $Errors.Add("$($_.FullName): $($parseError.Message)")
    }
}

$markdownFiles = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.md |
    Where-Object { $_.FullName -notmatch '[/\\]docs[/\\]archive[/\\]legacy[/\\]' }

foreach ($file in $markdownFiles) {
    $fenceCount = (
        Select-String -LiteralPath $file.FullName -Pattern '^```' -Encoding utf8
    ).Count
    if ($fenceCount % 2 -ne 0) {
        $Errors.Add("$($file.FullName): nombre impair de blocs de code")
    }

    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding utf8) {
        foreach ($match in [regex]::Matches($line, '\[[^\]]+\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value.Trim('<', '>')
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or
                $target.StartsWith('#')) {
                continue
            }

            $pathPart = ($target -split '#', 2)[0]
            if ([string]::IsNullOrWhiteSpace($pathPart)) {
                continue
            }

            $resolved = Join-Path $file.DirectoryName $pathPart
            if (-not (Test-Path -LiteralPath $resolved)) {
                $Errors.Add("$($file.FullName): lien manquant $target")
            }
        }
    }
}

$config = Join-Path $Root "install/config/vps.env.example"
$imageKeys = @(
    "LINKWARDEN_VERSION",
    "DAVIS_VERSION",
    "FRESHRSS_VERSION",
    "TTRSS_IMAGE",
    "POSTGRES_VERSION",
    "PHP_BASE_IMAGE",
    "WEB_IMAGE_TAG",
    "NGINX_ALPINE_VERSION",
    "GRAFANA_VERSION",
    "PROMETHEUS_VERSION",
    "NODE_EXPORTER_VERSION",
    "CADVISOR_VERSION",
    "LOKI_VERSION",
    "ALLOY_VERSION",
    "ALPINE_VERSION",
    "NGINX_VERSION",
    "CERTBOT_VERSION"
)
$values = @{}
foreach ($line in Get-Content -LiteralPath $config -Encoding utf8) {
    if ($line -match '^([A-Z0-9_]+)=(.+)$') {
        $values[$Matches[1]] = $Matches[2]
    }
}

foreach ($key in $imageKeys) {
    if (-not $values.ContainsKey($key)) {
        $Errors.Add("$config : référence d'image absente $key")
        continue
    }
    $value = $values[$key]
    if ($value -match '(^|:)(latest|main|master|edge|stable)$') {
        $Errors.Add("$config : référence d'image mutable $key=$value")
    }
}

$gitRoot = (& git -C $Root rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0) {
    $tracked = & git -C $gitRoot ls-files
    foreach ($forbidden in @(
        "VPS/install/config/vps.env",
        "VPS/install/config/secrets.env",
        "VPS/install/config/restic.env",
        "VPS/install/local/vps.env",
        "VPS/install/local/secrets.env"
    )) {
        $relativePath = $forbidden.Replace(
            '/',
            [System.IO.Path]::DirectorySeparatorChar
        )
        $forbiddenPath = Join-Path $gitRoot $relativePath
        if ($tracked -contains $forbidden -and
            (Test-Path -LiteralPath $forbiddenPath)) {
            $Errors.Add("$forbidden ne doit pas être suivi par Git")
        }
    }
}

if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Validation du dépôt terminée : PowerShell, Markdown, images et secrets locaux."
