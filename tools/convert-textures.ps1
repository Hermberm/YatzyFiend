# Converts the prototype's JPG textures into WoW-ready .tga files.
# WoW can't read JPG/PNG; it reads uncompressed TGA (and BLP). Sizes must be powers of two.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File C:\Yatzy\tools\convert-textures.ps1
# Re-run it later when new art (e.g. your AI-generated images) is added to the list below.

Add-Type -AssemblyName System.Drawing

$src = 'C:\Yatzy\prototype\textures'
$dst = 'C:\Yatzy\Yatzy\Media\Textures'
New-Item -ItemType Directory -Force $dst | Out-Null

# source file -> addon file name, size (power of two)
$jobs = @(
    # 512 px: larger, smoother texture detail on screen (256 px looked grainy when tiled)
    @{ In = 'wood_table_worn_diff_1k.jpg';   Out = 'TableWood.tga'; Size = 512 },
    @{ In = 'brown_leather_albedo_1k.jpg';   Out = 'Leather.tga';   Size = 512 },
    # (felt and dice wood are now part of the rendered pieces in render-assets.ps1)
    @{ In = 'metal_plate_02_diff_1k.jpg';    Out = 'Metal.tga';     Size = 256 }
)

function Write-Tga([System.Drawing.Bitmap]$bmp, [string]$path) {
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $stride = $data.Stride
    $raw = New-Object byte[] ($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
    $bmp.UnlockBits($data)

    # 18-byte TGA header: uncompressed true-colour, 24 bits, origin bottom-left
    $header = New-Object byte[] 18
    $header[2] = 2
    $header[12] = $w -band 0xFF; $header[13] = ($w -shr 8) -band 0xFF
    $header[14] = $h -band 0xFF; $header[15] = ($h -shr 8) -band 0xFF
    $header[16] = 24
    $header[17] = 0

    $fs = [System.IO.File]::Create($path)
    $fs.Write($header, 0, 18)
    # TGA rows go bottom-up; GDI+ rows are top-down and already in B,G,R order
    for ($y = $h - 1; $y -ge 0; $y--) { $fs.Write($raw, $y * $stride, $w * 3) }
    $fs.Close()
}

# 32-bit TGA (with transparency) from a function f(x, y) -> @(r, g, b, a), values 0..255
function New-GeneratedTexture([string]$name, [int]$w, [int]$h, [scriptblock]$pixel) {
    $bytes = New-Object byte[] ($w * $h * 4)
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = & $pixel $x $y
            $i = ((($h - 1 - $y) * $w) + $x) * 4          # bottom-up rows
            $bytes[$i]     = [byte][Math]::Max(0, [Math]::Min(255, [int]$c[2]))
            $bytes[$i + 1] = [byte][Math]::Max(0, [Math]::Min(255, [int]$c[1]))
            $bytes[$i + 2] = [byte][Math]::Max(0, [Math]::Min(255, [int]$c[0]))
            $bytes[$i + 3] = [byte][Math]::Max(0, [Math]::Min(255, [int]$c[3]))
        }
    }
    $header = New-Object byte[] 18
    $header[2] = 2
    $header[12] = $w -band 0xFF; $header[13] = ($w -shr 8) -band 0xFF
    $header[14] = $h -band 0xFF; $header[15] = ($h -shr 8) -band 0xFF
    $header[16] = 32
    $header[17] = 8          # 8 bits of alpha
    $out = Join-Path $dst "$name.tga"
    $fs = [System.IO.File]::Create($out)
    $fs.Write($header, 0, 18); $fs.Write($bytes, 0, $bytes.Length); $fs.Close()
    "{0,-16} {1}x{2}  {3,6:N0} KB  (generated)" -f "$name.tga", $w, $h, ((Get-Item $out).Length / 1KB)
}

function Lerp($a, $b, $t) { $a + ($b - $a) * $t }

foreach ($job in $jobs) {
    $img = [System.Drawing.Image]::FromFile((Join-Path $src $job.In))
    $bmp = New-Object System.Drawing.Bitmap $job.Size, $job.Size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # Wrap mode avoids dark seams at the edges, so the texture still tiles
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::Tile)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $job.Size, $job.Size), 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose(); $img.Dispose()
    $out = Join-Path $dst $job.Out
    Write-Tga $bmp $out
    $bmp.Dispose()
    "{0,-16} {1}x{1}  {2,6:N0} KB" -f $job.Out, $job.Size, ((Get-Item $out).Length / 1KB)
}

# ---------------------------------------------------------------------------
# Small generated textures (same look as the prototype's CSS details)
# ---------------------------------------------------------------------------

# (Pips and dice are rendered from the prototype in render-assets.ps1.)

# Soft shadow under a die
New-GeneratedTexture 'Shadow' 64 64 {
    param($x, $y)
    $dx = [Math]::Max(0, [Math]::Abs($x + 0.5 - 32) - 18) / 14
    $dy = [Math]::Max(0, [Math]::Abs($y + 0.5 - 32) - 18) / 14
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    return @(0, 0, 0, ([Math]::Max(0, 1 - $d) * 150))
}

# Stitching: light dashes, tiled along an edge
New-GeneratedTexture 'StitchH' 8 2 { param($x, $y) if ($x -lt 5) { @(230, 200, 150, 90) } else { @(0, 0, 0, 0) } }
New-GeneratedTexture 'StitchV' 2 8 { param($x, $y) if ($y -lt 5) { @(230, 200, 150, 90) } else { @(0, 0, 0, 0) } }

# Rivet: a small shaded metal dome
New-GeneratedTexture 'Rivet' 16 16 {
    param($x, $y)
    $dx = ($x + 0.5 - 8) / 6.5; $dy = ($y + 0.5 - 8) / 6.5
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    if ($d -gt 1) { return @(0, 0, 0, 0) }
    $hx = ($x + 0.5 - 6) / 6.5; $hy = ($y + 0.5 - 5.5) / 6.5
    $t = [Math]::Min(1, [Math]::Sqrt($hx * $hx + $hy * $hy))
    $c = @((Lerp 255 74 $t), (Lerp 240 56 $t), (Lerp 196 32 $t))
    if ($d -gt 0.85) { $c = @(34, 24, 12) }
    return @($c[0], $c[1], $c[2], ([Math]::Min(1, (1 - $d) * 8) * 255))
}

# Paper: cream with fine grain and faint fibres (tiles seamlessly)
$rand = New-Object System.Random 11
$grain = New-Object 'double[,]' 128, 128
for ($i = 0; $i -lt 128; $i++) { for ($j = 0; $j -lt 128; $j++) { $grain[$i, $j] = $rand.NextDouble() } }
New-GeneratedTexture 'Paper' 128 128 {
    param($x, $y)
    $n = $grain[$x, $y] * 0.6 + $grain[(($x + 1) % 128), $y] * 0.2 + $grain[$x, (($y + 1) % 128)] * 0.2
    $fibre = [Math]::Sin(($x * 0.21) + [Math]::Sin($y * 0.05) * 3) * 0.5 + 0.5
    $v = ($n - 0.5) * 14 - $fibre * 4
    return @((241 + $v), (230 + $v), (200 + $v * 0.9), 255)
}
