# Tiny static file server for the UI prototype (no Python/Node needed).
# Serves C:\Yatzy\prototype on http://localhost:8765/ — only reachable from this PC.
param([int]$Port = $(if ($env:PORT) { [int]$env:PORT } else { 8765 }))

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\prototype')).Path
$types = @{ '.html'='text/html; charset=utf-8'; '.jpg'='image/jpeg'; '.png'='image/png'; '.css'='text/css'; '.js'='text/javascript'; '.md'='text/plain; charset=utf-8'; '.ogg'='audio/ogg'; '.mp3'='audio/mpeg' }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ($path -eq '') { $path = 'index.html' }
    $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
    if ($file.StartsWith($root) -and (Test-Path $file -PathType Leaf)) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
        $ctx.Response.Headers.Add('Cache-Control', 'no-store')
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $ctx.Response.StatusCode = 404
    }
    $ctx.Response.Close()
}
