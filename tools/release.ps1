# release.ps1 - build the addon zip, and (with -Upload) publish it on CurseForge.
#
#   powershell -ExecutionPolicy Bypass -File tools\release.ps1            # only build dist\<Addon>-<version>.zip
#   powershell -ExecutionPolicy Bypass -File tools\release.ps1 -Upload    # build, then upload to CurseForge
#   ... -Upload -ReleaseType beta                                         # "release" (default), "beta" or "alpha"
#   ... -Upload -DryRun                                                   # do everything except the upload itself
#
# Everything it needs comes from the addon itself:
#   - version          : "## Version:" in the .toc
#   - game version     : "## Interface:" in the .toc (16001 -> 1.60.1 = WoW: Forever)
#   - CurseForge project: "## X-Curse-Project-ID:" in the .toc
#   - changelog        : the section for this version in CHANGELOG.md ("## 0.10.0")
# The CurseForge API token is NEVER kept in the project folder (so it can't end up in a zip):
#   environment variable CF_API_KEY, or the file %APPDATA%\AddonRelease\curseforge-token.txt
#
# The zip has one folder (the addon folder) with forward slashes in all paths, which is
# what CurseForge and every addon manager expect.

param(
    [switch]$Upload,
    [switch]$DryRun,
    [ValidateSet("release", "beta", "alpha")][string]$ReleaseType = "release",
    [string]$AddonFolder = "Yatzy",
    [string]$OutDir = ""            # where the zip goes (default: dist)
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $root $AddonFolder
$dist = if ($OutDir) { $OutDir } else { Join-Path $root "dist" }

function Fail($msg) { Write-Host ""; Write-Host "STOPPED: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- read the .toc
$tocPath = Join-Path $addonDir "$AddonFolder.toc"
if (-not (Test-Path $tocPath)) { Fail "No $AddonFolder.toc in $addonDir" }
$toc = [IO.File]::ReadAllLines($tocPath, [Text.Encoding]::UTF8)
function TocField($name) {
    foreach ($line in $toc) {
        if ($line -match ("^##\s*" + [regex]::Escape($name) + ":\s*(.+?)\s*$")) { return $Matches[1] }
    }
    return $null
}
$version = TocField "Version"
$interface = TocField "Interface"
$projectId = TocField "X-Curse-Project-ID"
if (-not $version) { Fail "No '## Version:' line in the .toc" }
if (-not $interface) { Fail "No '## Interface:' line in the .toc" }

# 16001 -> 1.60.1, 11507 -> 1.15.7
$n = [int]($interface.Split(",")[0].Trim())
$gameVersion = "{0}.{1}.{2}" -f [math]::Floor($n / 10000), ([math]::Floor($n / 100) % 100), ($n % 100)

Write-Host "Addon:        $AddonFolder"
Write-Host "Version:      $version"
Write-Host "Game version: $gameVersion (Interface $interface)"

# ---------------------------------------------------------------- every file in the .toc exists
foreach ($line in $toc) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if (-not (Test-Path (Join-Path $addonDir $t))) { Fail "The .toc lists '$t', but that file doesn't exist" }
}

# ---------------------------------------------------------------- build the zip
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "$AddonFolder-$version.zip"
if (Test-Path $zipPath) {
    # a zip for this version already exists: that version may be out already, so don't
    # silently replace it (raise "## Version:" in the .toc for a new release)
    if ($Upload -and -not $DryRun) { Fail "$zipPath already exists. Raise '## Version:' in the .toc first." }
    Remove-Item $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Files that never go into the release (editor and system leftovers)
$skip = @('Thumbs.db', 'desktop.ini', '.DS_Store')

$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
$count = 0
try {
    Get-ChildItem $addonDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        if ($skip -contains $_.Name -or $_.Name.StartsWith(".") -or $_.Name.EndsWith("~")) { return }
        $rel = $_.FullName.Substring($addonDir.Length + 1).Replace('\', '/')
        $entry = "$AddonFolder/$rel"
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry,
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $script:count++
    }
} finally {
    $zip.Dispose()
}
$size = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "Zip:          $zipPath ($count files, $size MB)" -ForegroundColor Green

if (-not $Upload) { exit 0 }

# ---------------------------------------------------------------- changelog for this version
$changelog = "Version $version"
$clPath = Join-Path $root "CHANGELOG.md"
if (Test-Path $clPath) {
    $lines = [IO.File]::ReadAllLines($clPath, [Text.Encoding]::UTF8)
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($l in $lines) {
        if ($l -match '^##\s+(\S+)') {
            if ($inside) { break }
            $inside = ($Matches[1] -eq $version)
            continue
        }
        if ($inside) { $out.Add($l) }
    }
    if ($out.Count -gt 0) { $changelog = ($out -join "`n").Trim() }
    else { Fail "CHANGELOG.md has no '## $version' section. Write what's new first." }
} else {
    Fail "No CHANGELOG.md in $root"
}

# ---------------------------------------------------------------- CurseForge
if (-not $projectId) { Fail "No '## X-Curse-Project-ID:' line in the .toc (the number on the CurseForge project page, 'About Project')" }
$token = $env:CF_API_KEY
$tokenFile = Join-Path $env:APPDATA "AddonRelease\curseforge-token.txt"
if (-not $token -and (Test-Path $tokenFile)) { $token = ([IO.File]::ReadAllText($tokenFile)).Trim() }
if (-not $token) { Fail "No CurseForge API token. Put it in $tokenFile (see RELEASING.md)" }

$api = "https://wow.curseforge.com/api"
$headers = @{ "X-Api-Token" = $token }

# Find the id of our game version (e.g. 1.60.1). If the same number exists for more than one
# flavor, take the one whose type is called Forever.
$types = Invoke-RestMethod -Uri "$api/game/version-types" -Headers $headers
$versions = Invoke-RestMethod -Uri "$api/game/versions" -Headers $headers
$matching = @($versions | Where-Object { $_.name -eq $gameVersion })
if ($matching.Count -eq 0) { Fail "CurseForge has no game version called $gameVersion" }
if ($matching.Count -gt 1) {
    $foreverTypes = @($types | Where-Object { $_.name -match 'forever' -or $_.slug -match 'forever' } | ForEach-Object { $_.id })
    $narrowed = @($matching | Where-Object { $foreverTypes -contains $_.gameVersionTypeID })
    if ($narrowed.Count -eq 1) { $matching = $narrowed }
    else {
        $list = ($matching | ForEach-Object {
            $tid = $_.gameVersionTypeID
            $tn = ($types | Where-Object { $_.id -eq $tid } | Select-Object -First 1).name
            "$($_.id) ($tn)"
        }) -join ", "
        Fail "More than one game version is called $gameVersion : $list"
    }
}
$gameVersionId = $matching[0].id
$typeName = ($types | Where-Object { $_.id -eq $matching[0].gameVersionTypeID } | Select-Object -First 1).name
Write-Host "CurseForge:   project $projectId, game version id $gameVersionId ($typeName $gameVersion), $ReleaseType"

$metadata = @{
    changelog     = $changelog
    changelogType = "markdown"
    displayName   = "$AddonFolder $version"
    gameVersions  = @($gameVersionId)
    releaseType   = $ReleaseType
} | ConvertTo-Json -Compress

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run: everything is ready, nothing was uploaded. Changelog that would be sent:" -ForegroundColor Yellow
    Write-Host $changelog
    exit 0
}

# Multipart upload (Windows PowerShell 5.1 has no -Form, so HttpClient does it)
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add("X-Api-Token", $token)
$form = New-Object System.Net.Http.MultipartFormDataContent
$meta = New-Object System.Net.Http.StringContent($metadata, [Text.Encoding]::UTF8, "application/json")
$form.Add($meta, "metadata")
$bytes = [IO.File]::ReadAllBytes($zipPath)
$file = New-Object System.Net.Http.ByteArrayContent(, $bytes)
$file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/zip")
$form.Add($file, "file", [IO.Path]::GetFileName($zipPath))
$resp = $client.PostAsync("$api/projects/$projectId/upload-file", $form).Result
$body = $resp.Content.ReadAsStringAsync().Result
$client.Dispose()
if (-not $resp.IsSuccessStatusCode) { Fail "CurseForge said $([int]$resp.StatusCode): $body" }
Write-Host ""
Write-Host "Uploaded! CurseForge file id: $body" -ForegroundColor Green
Write-Host "CurseForge checks new files before they go public; that usually takes a few minutes to an hour."
