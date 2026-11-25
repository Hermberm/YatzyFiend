# Tiny static file server for the addon preview (no Python/Node needed).
# Serves C:\Yatzy on http://localhost:8766/ (only the preview\ and Yatzy\ folders) —
# only reachable from this PC. The preview page is http://localhost:8766/preview/
param([int]$Port = $(if ($env:PORT) { [int]$env:PORT } else { 8766 }))

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$allowed = @((Join-Path $root 'preview'), (Join-Path $root 'Yatzy'))
$types = @{ '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.lua'='text/plain; charset=utf-8';
            '.toc'='text/plain; charset=utf-8'; '.txt'='text/plain; charset=utf-8'; '.css'='text/css'; '.png'='image/png';
            '.jpg'='image/jpeg'; '.tga'='application/octet-stream'; '.ttf'='font/ttf'; '.ogg'='audio/ogg' }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving preview at http://localhost:$Port/preview/"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ($path -eq '' -or $path -eq 'preview' -or $path -eq 'preview/') { $path = 'preview/index.html' }
        $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
        $ok = $false
        foreach ($a in $allowed) { if ($file.StartsWith($a + [IO.Path]::DirectorySeparatorChar)) { $ok = $true } }
        if ($path -eq '') { $ok = $false }
        if ($ok -and (Test-Path $file -PathType Leaf)) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file).ToLower()
            $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
            $ctx.Response.Headers.Add('Cache-Control', 'no-store')
            $ctx.Response.ContentLength64 = $bytes.Length
            if ($ctx.Request.HttpMethod -ne 'HEAD') { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) }
        } elseif ($path -eq '') {
            $ctx.Response.Redirect('/preview/')
        } else {
            $ctx.Response.StatusCode = 404
        }
    } catch { $ctx.Response.StatusCode = 500 }
    $ctx.Response.Close()
}
