# Renders the prototype's UI pieces with headless Microsoft Edge (exact same CSS as the
# browser prototype) and converts the screenshots to WoW .tga files with transparency.
#   powershell -ExecutionPolicy Bypass -File C:\Yatzy\tools\render-assets.ps1
# Each piece is drawn in the top-left corner of a power-of-two canvas (WoW needs
# power-of-two textures); the addon crops it with SetTexCoord.
# -Only CheckerRed,PointRed   renders just those output files.
param([string[]]$Only)

Add-Type -AssemblyName System.Drawing

$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$page = 'C:\Yatzy\tools\render\assets.html'
$out = 'C:\Yatzy\Yatzy\Media\Textures\UI'
$tmp = Join-Path $env:TEMP 'yatzy-render'
New-Item -ItemType Directory -Force $out, $tmp | Out-Null

# name in the page, canvas width/height (CSS px), scale, output file
$assets = @(
    @('die1', 64, 64, 2, 'Die1'), @('die2', 64, 64, 2, 'Die2'), @('die3', 64, 64, 2, 'Die3'),
    @('die4', 64, 64, 2, 'Die4'), @('die5', 64, 64, 2, 'Die5'),
    @('pip', 16, 16, 2, 'Pip'),
    @('glow', 128, 128, 1, 'DieGlow'),
    @('softglow', 256, 64, 2, 'SoftGlow'),
    @('btn-primary-170x44', 256, 64, 2, 'BtnPrimary170x44'),
    @('btn-primary-200x32', 256, 32, 2, 'BtnPrimary200x32'),
    @('btn-primary-130x26', 256, 32, 2, 'BtnPrimary130x26'),
    @('btn-primary-70x22', 128, 32, 2, 'BtnPrimary70x22'),
    @('btn-primary-220x44', 256, 64, 2, 'BtnPrimary220x44'),
    @('btn-primary-210x56', 256, 64, 2, 'BtnPrimary210x56'),     # Roll button (next to the tray)
    @('btn-secondary-180x26', 256, 32, 2, 'BtnSecondary180x26'),
    @('btn-secondary-28x22', 32, 32, 2, 'BtnSecondary28x22'),
    @('home', 16, 16, 2, 'Home'),
    @('btn-secondary-200x32', 256, 32, 2, 'BtnSecondary200x32'),
    @('btn-secondary-100x26', 128, 32, 2, 'BtnSecondary100x26'),
    @('btn-secondary-92x22', 128, 32, 2, 'BtnSecondary92x22'),
    @('btn-secondary-112x22', 128, 32, 2, 'BtnSecondary112x22'),
    @('btn-secondary-70x22', 128, 32, 2, 'BtnSecondary70x22'),
    @('btn-secondary-22x22', 32, 32, 2, 'BtnSecondary22x22'),
    @('bandH', 256, 8, 2, 'FrameH'),
    @('bandV', 8, 256, 2, 'FrameV'),
    @('corner', 32, 32, 2, 'FrameCorner'),
    @('cornerround', 8, 8, 2, 'FrameCornerRound'),
    @('tray', 512, 128, 1, 'Tray'),
    @('plaque', 256, 32, 2, 'Plaque'),
    @('tab', 32, 128, 2, 'FoldTab'),
    @('strike', 64, 8, 2, 'Strike'),
    @('trash', 16, 16, 2, 'Trash'),
    @('undo', 16, 16, 2, 'Undo'),
    @('check', 32, 32, 2, 'Check'),
    @('gear', 16, 16, 2, 'Gear'),                                # title bar: settings and sound
    @('speaker-off', 16, 16, 2, 'SpeakerOff'),
    @('speaker-1', 16, 16, 2, 'Speaker1'),
    @('speaker-2', 16, 16, 2, 'Speaker2'),
    @('speaker-3', 16, 16, 2, 'Speaker3'),
    @('rays', 256, 256, 1, 'Rays'),
    @('icon-yatzy', 64, 64, 2, 'IconYatzy'),                   # game icons (start screen, game list)
    @('icon-checker', 64, 64, 2, 'IconBackgammon'),
    @('icon-minimap', 64, 64, 2, 'MinimapIcon'),                 # the minimap button: two dice
    @('btn-secondary-236x52', 256, 64, 2, 'BtnSecondary236x52'),  # game choice cards on the start screen
    @('checker-red', 64, 64, 2, 'CheckerRed'),                   # backgammon checkers and points
    @('checker-ivory', 64, 64, 2, 'CheckerIvory'),
    @('point-red', 32, 128, 2, 'PointRed'),
    @('point-ivory', 32, 128, 2, 'PointIvory'),
    @('portrait-ring', 64, 64, 2, 'PortraitRing'),               # round frame for player pictures
    @('portrait-back', 64, 64, 2, 'PortraitBack')
)
if ($Only) { $assets = @(foreach ($a in $assets) { if ($Only -contains $a[4]) { , $a } }) }   # (the comma keeps a single match from being unrolled)

function Convert-PngToTga([string]$png, [string]$tga) {
    $src = [System.Drawing.Bitmap]::FromFile($png)
    $bmp = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose(); $src.Dispose()
    $w = $bmp.Width; $h = $bmp.Height
    $data = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $raw = New-Object byte[] ($data.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
    $stride = $data.Stride
    $bmp.UnlockBits($data); $bmp.Dispose()
    $header = New-Object byte[] 18
    $header[2] = 2
    $header[12] = $w -band 0xFF; $header[13] = ($w -shr 8) -band 0xFF
    $header[14] = $h -band 0xFF; $header[15] = ($h -shr 8) -band 0xFF
    $header[16] = 32; $header[17] = 8
    $fs = [System.IO.File]::Create($tga)
    $fs.Write($header, 0, 18)
    for ($y = $h - 1; $y -ge 0; $y--) { $fs.Write($raw, $y * $stride, $w * 4) }   # BGRA rows, bottom-up
    $fs.Close()
}

$url = 'file:///' + ($page -replace '\\', '/')
# A fresh browser profile each run: a profile left locked by an earlier run makes Edge quit (exit 21)
$profileDir = Join-Path $tmp ("profile-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($a in $assets) {
    $name, $w, $h, $scale, $file = $a
    $png = Join-Path $tmp "$file.png"
    if (Test-Path $png) { Remove-Item $png }
    $args = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
              '--default-background-color=00000000', "--force-device-scale-factor=$scale",
              "--window-size=$w,$h", '--virtual-time-budget=4000', "--user-data-dir=$profileDir",
              "--screenshot=$png", "$url#$name")
    Start-Process $edge -ArgumentList $args -Wait -WindowStyle Hidden
    if (-not (Test-Path $png)) { Write-Warning "no screenshot for $name"; continue }
    $tga = Join-Path $out "$file.tga"
    Convert-PngToTga $png $tga
    "{0,-22} {1}x{2}  {3,5:N0} KB" -f "$file.tga", ($w * $scale), ($h * $scale), ((Get-Item $tga).Length / 1KB)
}
"PNG previews are in $tmp"
