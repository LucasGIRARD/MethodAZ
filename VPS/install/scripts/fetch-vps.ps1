[CmdletBinding()]
param(
    [ValidatePattern("^[A-Za-z0-9._-]+$")]
    [string]$Ref = "main",

    [string]$Destination = ".\methodaz-vps",

    [ValidatePattern("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")]
    [string]$Repository = "LucasGIRARD/MethodAZ",

    [string]$ArchivePath
)

$ErrorActionPreference = "Stop"

Get-Command tar -ErrorAction Stop | Out-Null

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) {
    throw "La destination existe déjà : $destinationPath"
}

$destinationParent = Split-Path -Parent $destinationPath
New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null

$temporary = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("methodaz-vps-" + [System.Guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $temporary | Out-Null

try {
    $archive = Join-Path $temporary "methodaz.tar.gz"
    if ($ArchivePath) {
        Copy-Item -LiteralPath $ArchivePath -Destination $archive
    }
    else {
        $url = if ($Ref -match "^[0-9a-fA-F]{40}$") {
            "https://github.com/$Repository/archive/$Ref.tar.gz"
        }
        else {
            "https://github.com/$Repository/archive/refs/heads/$Ref.tar.gz"
        }

        Write-Host "Téléchargement de $Repository à la référence $Ref"
        try {
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri $url `
                -OutFile $archive
        }
        catch {
            throw "Téléchargement impossible. Vérifier que le dépôt est public et que la référence existe. $($_.Exception.Message)"
        }
    }

    [array]$entries = & tar -tzf $archive
    if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
        throw "Archive GitHub invalide."
    }

    $readmeEntry = $entries |
        Where-Object { $_ -match "/VPS/README[.]md$" } |
        Select-Object -First 1
    if (-not $readmeEntry) {
        throw "Le dossier VPS est absent de l'archive."
    }
    $prefix = $readmeEntry.Substring(
        0,
        $readmeEntry.Length - "/VPS/README.md".Length
    )

    $bundle = Join-Path $temporary "bundle"
    New-Item -ItemType Directory -Path $bundle | Out-Null

    & tar -xzf $archive `
        --directory $bundle `
        --strip-components=2 `
        "$prefix/VPS"
    if ($LASTEXITCODE -ne 0) {
        throw "Extraction du dossier VPS impossible."
    }

    $sourceVersion = @(
        "repository=$Repository"
        "ref=$Ref"
        "downloaded_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        ""
    ) -join "`n"

    $sourcePath = Join-Path $bundle "install\source-version.txt"
    [System.IO.File]::WriteAllText(
        $sourcePath,
        $sourceVersion,
        [System.Text.UTF8Encoding]::new($false)
    )

    Move-Item -LiteralPath $bundle -Destination $destinationPath
    Write-Host "Bundle VPS téléchargé dans : $destinationPath"
    Write-Host "Source enregistrée dans : $destinationPath\install\source-version.txt"
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}
