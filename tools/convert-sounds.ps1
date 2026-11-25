# Picks the addon's sounds from the Kenney CC0 packs in tools\sounds-src and writes a
# quiet (Low, default) and a Normal version of each to Yatzy\Media\Sounds\.
# WoW can't set the volume of a single sound, so the volume is baked into the files.
#   powershell -ExecutionPolicy Bypass -File C:\Yatzy\tools\convert-sounds.ps1
# To swap a sound: change the file name in $picks and run again (then restart WoW).

$src = 'C:\Yatzy\tools\sounds-src'
$dst = 'C:\Yatzy\Yatzy\Media\Sounds'

$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
}
if (-not $ffmpeg) { throw 'ffmpeg not found (winget install Gyan.FFmpeg)' }

# addon name -> source file name (found anywhere under tools\sounds-src)
$picks = [ordered]@{
    DiceThrow1 = 'dice-throw-1.ogg'
    DiceThrow2 = 'dice-throw-2.ogg'
    DiceThrow3 = 'dice-throw-3.ogg'
    DieThrow1  = 'die-throw-1.ogg'
    DieThrow2  = 'die-throw-2.ogg'
    DieThrow3  = 'die-throw-3.ogg'
    DieThrow4  = 'die-throw-4.ogg'
    DiceGrab1  = 'dice-grab-1.ogg'
    DiceGrab2  = 'dice-grab-2.ogg'
    YourTurn   = 'bong_001.ogg|lowpass=f=2200'      # soft and low ("file|extra ffmpeg filter")
    Invite     = 'maximize_006.ogg'
    Yatzy      = 'yatzy-friend.ogg'                  # the friend's "Yatzy!" (tools\sounds-src\custom)
    TurnChime  = 'glass_002.ogg|lowpass=f=3200|-4'   # very subtle shimmer with the "Your turn!" popup
}
# Optional third part "|-8": that many dB below the level's normal peak (for subtle sounds)

# Level per version, as the peak in dB. Every sound is first gently compressed (lifts the
# quiet tail of a dice clatter) and then peak-normalized, so all sounds are equally clear.
# Normal peaks at -1 dB; Low is 8 dB softer. (0.7.0 used plain volume factors on the raw
# files, which made the dice almost inaudible on Low.)
# High: much harder compression + a limiter, so it sounds a lot louder at the same peak.
$gentle = 'acompressor=threshold=0.06:ratio=4:attack=3:release=60:makeup=2'
$hard   = "$gentle,volume=7dB,alimiter=limit=0.95:attack=1:release=40"
$levels = [ordered]@{
    Low    = @{ peak = -9;   comp = $gentle }
    Normal = @{ peak = -1;   comp = $gentle }
    High   = @{ peak = -0.3; comp = $hard }
}

foreach ($level in $levels.Keys) {
    New-Item -ItemType Directory -Force (Join-Path $dst $level) | Out-Null
}
New-Item -ItemType Directory -Force (Join-Path $dst 'Custom') | Out-Null

foreach ($name in $picks.Keys) {
    $fileName, $extra, $offset = $picks[$name] -split '\|', 3
    $offset = if ($offset) { [double]::Parse($offset, [Globalization.CultureInfo]::InvariantCulture) } else { 0 }
    $file = Get-ChildItem $src -Recurse -File -Filter $fileName | Select-Object -First 1
    if (-not $file) { Write-Warning "missing source $fileName"; continue }
    foreach ($level in $levels.Keys) {
        # 1) compress (plus any extra filter) into a temporary WAV and measure its peak
        $tmp = Join-Path $env:TEMP "yatzy-sound-$name-$level.wav"
        $pre = $levels[$level].comp
        if ($extra) { $pre = "$extra,$pre" }
        & $ffmpeg -y -loglevel error -i $file.FullName -af $pre -ar 44100 $tmp
        $peakLine = (& $ffmpeg -hide_banner -nostats -i $tmp -af volumedetect -f null - 2>&1 | Select-String 'max_volume').Line
        $peak = [double]::Parse(($peakLine -replace '.*max_volume:\s*([-\d\.]+).*', '$1'), [Globalization.CultureInfo]::InvariantCulture)
        # 2) gain so the peak lands on the level's target
        $out = Join-Path (Join-Path $dst $level) "$name.ogg"
        $gain = ($levels[$level].peak + $offset - $peak).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
        & $ffmpeg -y -loglevel error -i $tmp -af "volume=${gain}dB" -c:a libvorbis -q:a 4 $out
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    "{0,-11} <- {1}" -f $name, $picks[$name]
}
