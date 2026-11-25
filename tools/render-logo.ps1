# Renders the CurseForge project icon variants from tools/render/logo.html to branding\Logo-<variant>.png
# (512 x 512, transparent corners).
#   powershell -ExecutionPolicy Bypass -File C:\Yatzy\tools\render-logo.ps1                 # every variant
#   powershell -ExecutionPolicy Bypass -File C:\Yatzy\tools\render-logo.ps1 -Only felt      # just one
param([string[]]$Only)

$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$page = 'C:\Yatzy\tools\render\logo.html'
$out = 'C:\Yatzy\branding'
$tmp = Join-Path $env:TEMP 'yatzy-render'
New-Item -ItemType Directory -Force $out, $tmp | Out-Null

$variants = @('leather', 'felt', 'both', 'one')
if ($Only) { $variants = @($variants | Where-Object { $Only -contains $_ }) }

$url = 'file:///' + ($page -replace '\\', '/')
$profileDir = Join-Path $tmp ("profile-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($v in $variants) {
    $png = Join-Path $out "Logo-$v.png"
    if (Test-Path $png) { Remove-Item $png }
    $args = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
              '--default-background-color=00000000', '--force-device-scale-factor=2',
              '--window-size=256,256', '--virtual-time-budget=4000', "--user-data-dir=$profileDir",
              "--screenshot=$png", "$url#$v")
    Start-Process $edge -ArgumentList $args -Wait -WindowStyle Hidden
    if (Test-Path $png) { "Logo-$v.png" } else { Write-Warning "no screenshot for $v" }
}
