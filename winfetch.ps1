$Config = @{
    TempDir      = Join-Path $env:TEMP "winfetch"
    OutputDir    = [Environment]::GetFolderPath("MyDocuments") -replace 'Documents$','Downloads'
    
    YtDlp        = $null  # Set in Init
    Ffmpeg       = $null
    Ffprobe      = $null
    
    Sources      = @{
        YtDlp  = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        Ffmpeg = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        Ffprobe = $null
    }
}

$Config.YtDlp    = Join-Path $Config.TempDir "yt-dlp.exe"
$Config.Ffmpeg   = Join-Path $Config.TempDir "ffmpeg.exe"
$Config.Ffprobe  = Join-Path $Config.TempDir "ffprobe.exe"

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
║                            WinFetch                           ║
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

function Get-BinaryFast {
    param([string]$Url, [string]$OutFile, [string]$Name, [int]$Segments = 4)
    
    Write-UI "Downloading $Name..." Run
    
    $simpleDownload = {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600
    }

    try {
        $supportsRange = $true
        $size = 0
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "HEAD"
            $req.UserAgent = "Mozilla/5.0"
            $req.AllowAutoRedirect = $true
            $req.Timeout = 15000
            $resp = $req.GetResponse()
            $size = $resp.ContentLength
            $supportsRange = $resp.Headers["Accept-Ranges"] -eq "bytes"
            $resp.Close()
        } catch {
            $supportsRange = $false
        }
        
        if (-not $supportsRange -or $size -le 1MB) {
            & $simpleDownload
            return $true
        }
        
        $segSize = [Math]::Ceiling($size / $Segments)
        $tempDir = Join-Path $Config.TempDir "dl_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $segFiles = @()
        
        for ($i = 0; $i -lt $Segments; $i++) {
            $start = $i * $segSize
            $end = [Math]::Min(($i + 1) * $segSize - 1, $size - 1)
            $segFile = Join-Path $tempDir "seg_$i"
            $segFiles += $segFile
            
            Write-Host "`r[>] $Name segment $($i+1)/$Segments" -NoNewline
            
            try {
                $dlReq = [System.Net.HttpWebRequest]::Create($Url)
                $dlReq.Method = "GET"
                $dlReq.UserAgent = "Mozilla/5.0"
                $dlReq.AddRange($start, $end)
                $dlReq.Timeout = 300000
                $dlResp = $dlReq.GetResponse()
                $stream = $dlResp.GetResponseStream()
                $fs = [System.IO.File]::Create($segFile)
                $buf = New-Object byte[] 65536
                while (($rd = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    $fs.Write($buf, 0, $rd)
                }
                $fs.Close(); $stream.Close(); $dlResp.Close()
            } catch {
                Remove-Item $tempDir -Recurse -Force -EA SilentlyContinue
                & $simpleDownload
                return $true
            }
        }
        Write-Host ""
        
        $outStream = [System.IO.File]::Create($OutFile)
        $buf = New-Object byte[] 1048576
        foreach ($sf in $segFiles) {
            $inStream = [System.IO.File]::OpenRead($sf)
            while (($rd = $inStream.Read($buf, 0, $buf.Length)) -gt 0) {
                $outStream.Write($buf, 0, $rd)
            }
            $inStream.Close()
        }
        $outStream.Close()
        Remove-Item $tempDir -Recurse -Force -EA SilentlyContinue
        
        return $true
    } catch {
        Write-UI "Failed: $_" Err
        return $false
    }
}

function Get-Binary {
    param([string]$Url, [string]$OutFile, [string]$Name)
    return Get-BinaryFast -Url $Url -OutFile $OutFile -Name $Name -Segments 4
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
        
        $ff = Get-ChildItem -Path $extract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
        $fp = Get-ChildItem -Path $extract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
        
        if ($ff) { Copy-Item $ff.FullName -Destination $Config.Ffmpeg -Force }
        if ($fp) { Copy-Item $fp.FullName -Destination $Config.Ffprobe -Force }
        
        Remove-Item $zip -Force -EA SilentlyContinue
        Remove-Item $extract -Recurse -Force -EA SilentlyContinue
        
        return (Test-Path $Config.Ffmpeg)
    } catch {
        Write-UI "Failed: $_" Err
        return $false
    }
}

function Initialize-Binaries {
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
    
    if ($needYtDlp) {
        if (Get-BinaryFast -Url $Config.Sources.YtDlp -OutFile $Config.YtDlp -Name "yt-dlp" -Segments 4) {
            Write-UI "yt-dlp OK" OK
        }
    }
    
    if ($needFfmpeg) {
        $ffmpegUrl = $Config.Sources.Ffmpeg
        $isZip = $ffmpegUrl -match '\.zip$'
        
        if ($isZip) {
            if (Get-FfmpegFromZip -Url $ffmpegUrl) {
                Write-UI "ffmpeg OK" OK
            }
        } else {
            if (Get-BinaryFast -Url $ffmpegUrl -OutFile $Config.Ffmpeg -Name "ffmpeg" -Segments 4) {
                Write-UI "ffmpeg OK" OK
            }
            
            if ($Config.Sources.Ffprobe) {
                if (Get-BinaryFast -Url $Config.Sources.Ffprobe -OutFile $Config.Ffprobe -Name "ffprobe" -Segments 4) {
                    Write-UI "ffprobe OK" OK
                }
            }
        }
    }
    
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
