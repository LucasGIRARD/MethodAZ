[CmdletBinding()]
param(
    [ValidatePattern("^[A-Za-z0-9._-]+$")]
    [string]$Ref = "main",

    [ValidatePattern("^[A-Za-z0-9._-]+$")]
    [string]$Version,

    [switch]$Latest,

    [switch]$SelectVersion,

    [string]$Destination = ".\methodaz-vps",

    [ValidatePattern("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")]
    [string]$Repository = "LucasGIRARD/MethodAZ",

    [string]$ArchivePath
)

$ErrorActionPreference = "Stop"

Get-Command tar -ErrorAction Stop | Out-Null

$modeCount = 0
if ($Version) { $modeCount++ }
if ($Latest) { $modeCount++ }
if ($SelectVersion) { $modeCount++ }
if ($modeCount -gt 1) {
    throw "Utiliser un seul mode parmi -Version, -Latest et -SelectVersion."
}

function Get-ReleaseTags {
    $uri = "https://api.github.com/repos/$Repository/releases?per_page=20"
    @(Invoke-RestMethod -Uri $uri -UseBasicParsing | ForEach-Object { $_.tag_name })
}

function Get-LatestReleaseTag {
    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    (Invoke-RestMethod -Uri $uri -UseBasicParsing).tag_name
}

if ($Latest) {
    $Version = Get-LatestReleaseTag
    if (-not $Version) {
        throw "Impossible de déterminer la dernière release."
    }
}
elseif ($SelectVersion) {
    $tags = Get-ReleaseTags
    if (-not $tags) {
        throw "Aucune release GitHub trouvée pour $Repository."
    }

    Write-Host "Versions disponibles :"
    for ($i = 0; $i -lt $tags.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $tags[$i])
    }

    $answer = Read-Host "Version à installer [1]"
    if (-not $answer) {
        $answer = "1"
    }
    if (-not ($answer -match "^\d+$") -or [int]$answer -lt 1 -or [int]$answer -gt $tags.Count) {
        throw "Sélection invalide : $answer"
    }
    $Version = $tags[[int]$answer - 1]
}

$sourceType = if ($Version) {
    "release"
}
elseif ($Ref -match "^[0-9a-fA-F]{40}$") {
    "commit"
}
else {
    "branch"
}
$sourceRef = if ($Version) { $Version } else { $Ref }

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
        $url = if ($Version) {
            "https://github.com/$Repository/archive/refs/tags/$Version.tar.gz"
        }
        elseif ($Ref -match "^[0-9a-fA-F]{40}$") {
            "https://github.com/$Repository/archive/$Ref.tar.gz"
        }
        else {
            "https://github.com/$Repository/archive/refs/heads/$Ref.tar.gz"
        }

        Write-Host "Téléchargement de $Repository ($sourceType $sourceRef)"
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
        "source_type=$sourceType"
        "ref=$sourceRef"
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
