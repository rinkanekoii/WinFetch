<#
.SYNOPSIS
    Setup local server to host yt-dlp/ffmpeg binaries
.DESCRIPTION
    Downloads binaries once, then serves via simple HTTP server.
    Clients on LAN can fetch from here instead of GitHub.
#>

param(
    [int]$Port = 8080,
    [string]$BindAddr = "0.0.0.0"
)

$BinDir = Join-Path $PSScriptRoot "bins"

# URLs
$YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$FfmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

function Write-Log {
    param([string]$Msg, [string]$Type = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Type) { "OK" { "Green" } "ERR" { "Red" } default { "White" } }
    Write-Host "[$ts] $Msg" -ForegroundColor $color
}

# Download binaries if needed
function Initialize-Binaries {
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }
    
    $ytdlp = Join-Path $BinDir "yt-dlp.exe"
    $ffmpeg = Join-Path $BinDir "ffmpeg.exe"
    $ffprobe = Join-Path $BinDir "ffprobe.exe"
    
    if (-not (Test-Path $ytdlp)) {
        Write-Log "Downloading yt-dlp..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $YtDlpUrl -OutFile $ytdlp -UseBasicParsing
        Write-Log "yt-dlp downloaded" "OK"
    }
    
    if (-not (Test-Path $ffmpeg)) {
        Write-Log "Downloading ffmpeg..."
        $zip = Join-Path $BinDir "ffmpeg.zip"
        $extract = Join-Path $BinDir "tmp"
        
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $FfmpegUrl -OutFile $zip -UseBasicParsing
        
        Write-Log "Extracting..."
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        
        $ff = Get-ChildItem -Path $extract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
        $fp = Get-ChildItem -Path $extract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
        
        if ($ff) { Copy-Item $ff.FullName -Destination $ffmpeg -Force }
        if ($fp) { Copy-Item $fp.FullName -Destination $ffprobe -Force }
        
        Remove-Item $zip -Force -EA SilentlyContinue
        Remove-Item $extract -Recurse -Force -EA SilentlyContinue
        
        Write-Log "ffmpeg ready" "OK"
    }
    
    Write-Log "Binaries ready in: $BinDir" "OK"
}

# Simple HTTP server
function Start-FileServer {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://${BindAddr}:${Port}/")
    
    try {
        $listener.Start()
    } catch {
        Write-Log "Failed to start server. Try running as Admin or use different port." "ERR"
        Write-Log "Error: $_" "ERR"
        return
    }
    
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Binary Server Running" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Local:   http://localhost:$Port" -ForegroundColor White
    Write-Host "  Network: http://${ip}:$Port" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Files:" -ForegroundColor Gray
    Write-Host "    /yt-dlp.exe" -ForegroundColor Gray
    Write-Host "    /ffmpeg.exe" -ForegroundColor Gray
    Write-Host "    /ffprobe.exe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Update winfetch.ps1 Sources to:" -ForegroundColor Green
    Write-Host "    YtDlp  = `"http://${ip}:$Port/yt-dlp.exe`"" -ForegroundColor White
    Write-Host "    Ffmpeg = `"http://${ip}:$Port/ffmpeg.exe`"" -ForegroundColor White
    Write-Host ""
    Write-Host "  Press Ctrl+C to stop" -ForegroundColor DarkGray
    Write-Host ""
    
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $filename = $request.Url.LocalPath.TrimStart('/')
            $filepath = Join-Path $BinDir $filename
            
            if ((Test-Path $filepath) -and $filename -match '\.(exe|zip)$') {
                Write-Log "200 $filename <- $($request.RemoteEndPoint)"
                
                $bytes = [System.IO.File]::ReadAllBytes($filepath)
                $response.ContentType = "application/octet-stream"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                Write-Log "404 $filename <- $($request.RemoteEndPoint)" "ERR"
                $response.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
                $response.OutputStream.Write($msg, 0, $msg.Length)
            }
            
            $response.Close()
        } catch {
            if ($_.Exception.Message -notmatch "thread exit") {
                Write-Log "Error: $_" "ERR"
            }
        }
    }
}

# Main
Write-Host ""
Write-Log "Initializing binary server..."
Initialize-Binaries
Start-FileServer
