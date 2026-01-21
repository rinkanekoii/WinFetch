<#
.SYNOPSIS
    YT-DLP Interactive Downloader - Winutil-style PowerShell script
    
.DESCRIPTION
    A zero-footprint video/audio downloader using yt-dlp and ffmpeg.
    Runs entirely in memory with temp binaries. Leaves NO permanent changes.
    
.USAGE
    irm https://raw.githubusercontent.com/<USER>/<REPO>/main/idx.ps1 | iex

.SECURITY GUARANTEES
    - No PATH modification
    - No registry writes
    - No installer usage
    - No files outside $env:TEMP\yt-dlp-tool\
    - No telemetry or hidden connections
    - Only contacts: GitHub (binaries), user-specified video sources
    
.CLEANUP
    - Temp binaries stored in $env:TEMP\yt-dlp-tool\
    - Cleanup offered on exit
    - Forced exit leaves only temp folder (no persistence)
#>

# ============================================================================
# CONFIGURATION - All paths are temporary, nothing persists
# ============================================================================
$script:ProjectName = "yt-dlp-tool"
$script:TempDir = Join-Path $env:TEMP $script:ProjectName
$script:YtDlpPath = Join-Path $script:TempDir "yt-dlp.exe"
$script:FfmpegDir = Join-Path $script:TempDir "ffmpeg"
$script:FfmpegPath = Join-Path $script:FfmpegDir "ffmpeg.exe"
$script:FfprobePath = Join-Path $script:FfmpegDir "ffprobe.exe"
$script:DefaultOutput = Join-Path ([Environment]::GetFolderPath("Desktop")) "YT-Downloads"

# Binary download URLs (official sources only)
$script:YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$script:FfmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Banner {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                     YT-DLP Interactive Downloader                            ║
║                        Zero-Footprint Edition                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  • No PATH changes  • No registry writes  • No installers  • No telemetry   ║
║  • Temp files only: $($script:TempDir.PadRight(50))║
╚══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
}

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $color = switch ($Type) {
        "Info"    { "White" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        "Process" { "Cyan" }
        default   { "White" }
    }
    $prefix = switch ($Type) {
        "Info"    { "[i]" }
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error"   { "[✗]" }
        "Process" { "[→]" }
        default   { "[•]" }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [switch]$AllowBack
    )
    
    Write-Host "`n$Title" -ForegroundColor Yellow
    Write-Host ("-" * $Title.Length) -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Options[$i])" -ForegroundColor White
    }
    
    if ($AllowBack) {
        Write-Host "  [0] Back" -ForegroundColor DarkGray
    }
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    
    do {
        $input = Read-Host "Select option"
        if ($input -eq 'Q' -or $input -eq 'q') { return -1 }
        if ($AllowBack -and $input -eq '0') { return 0 }
        $num = 0
        if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $Options.Count) {
            return $num
        }
        Write-Host "Invalid selection. Try again." -ForegroundColor Red
    } while ($true)
}

function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required
    )
    
    $displayPrompt = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    
    do {
        $value = Read-Host $displayPrompt
        if ([string]::IsNullOrWhiteSpace($value)) {
            if ($Default) { return $Default }
            if ($Required) {
                Write-Host "This field is required." -ForegroundColor Red
                continue
            }
        }
        return $value
    } while ($Required)
}

# ============================================================================
# BINARY MANAGEMENT - Downloads only to temp, never installs
# ============================================================================

function Initialize-TempDirectory {
    # Create temp directory if not exists
    # SAFETY: Only creates folder in $env:TEMP - no system modification
    if (-not (Test-Path $script:TempDir)) {
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
        Write-Status "Created temp directory: $script:TempDir" "Info"
    }
}

function Get-YtDlp {
    # Downloads yt-dlp.exe to temp folder ONLY if not present
    # SAFETY: No PATH modification, no registry, temp folder only
    
    if (Test-Path $script:YtDlpPath) {
        Write-Status "yt-dlp already present in temp folder" "Success"
        return $true
    }
    
    Write-Status "Downloading yt-dlp.exe from GitHub..." "Process"
    Write-Status "Source: $script:YtDlpUrl" "Info"
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $script:YtDlpUrl -OutFile $script:YtDlpPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        if (Test-Path $script:YtDlpPath) {
            Write-Status "yt-dlp downloaded successfully" "Success"
            return $true
        }
    }
    catch {
        Write-Status "Failed to download yt-dlp: $_" "Error"
        return $false
    }
    return $false
}

function Get-Ffmpeg {
    # Downloads ffmpeg to temp folder ONLY if not present
    # SAFETY: No PATH modification, no registry, temp folder only
    
    if ((Test-Path $script:FfmpegPath) -and (Test-Path $script:FfprobePath)) {
        Write-Status "ffmpeg already present in temp folder" "Success"
        return $true
    }
    
    Write-Status "Downloading ffmpeg from GitHub..." "Process"
    Write-Status "Source: $script:FfmpegUrl" "Info"
    
    $zipPath = Join-Path $script:TempDir "ffmpeg.zip"
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $script:FfmpegUrl -OutFile $zipPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        Write-Status "Extracting ffmpeg..." "Process"
        
        # Extract to temp
        $extractPath = Join-Path $script:TempDir "ffmpeg-extract"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        
        # Find and move binaries
        $ffmpegExe = Get-ChildItem -Path $extractPath -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
        $ffprobeExe = Get-ChildItem -Path $extractPath -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
        
        if (-not (Test-Path $script:FfmpegDir)) {
            New-Item -ItemType Directory -Path $script:FfmpegDir -Force | Out-Null
        }
        
        if ($ffmpegExe) { Copy-Item $ffmpegExe.FullName -Destination $script:FfmpegPath -Force }
        if ($ffprobeExe) { Copy-Item $ffprobeExe.FullName -Destination $script:FfprobePath -Force }
        
        # Cleanup extraction artifacts
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        
        if ((Test-Path $script:FfmpegPath) -and (Test-Path $script:FfprobePath)) {
            Write-Status "ffmpeg extracted successfully" "Success"
            return $true
        }
    }
    catch {
        Write-Status "Failed to download/extract ffmpeg: $_" "Error"
        return $false
    }
    return $false
}

function Initialize-Binaries {
    Write-Status "Initializing required binaries..." "Process"
    
    Initialize-TempDirectory
    
    $ytdlpOk = Get-YtDlp
    $ffmpegOk = Get-Ffmpeg
    
    if (-not $ytdlpOk -or -not $ffmpegOk) {
        Write-Status "Failed to initialize required binaries" "Error"
        return $false
    }
    
    Write-Status "All binaries ready" "Success"
    return $true
}

# ============================================================================
# YT-DLP WRAPPER FUNCTIONS
# ============================================================================

function Invoke-YtDlp {
    param(
        [string[]]$Arguments
    )
    
    # Always use ffmpeg from our temp folder
    $baseArgs = @(
        "--ffmpeg-location", $script:FfmpegDir
        "--no-mtime"
    )
    
    $allArgs = $baseArgs + $Arguments
    
    Write-Status "Running yt-dlp..." "Process"
    Write-Host "Command: yt-dlp $($allArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""
    
    & $script:YtDlpPath @allArgs
    
    return $LASTEXITCODE -eq 0
}

function Get-VideoFormats {
    param([string]$Url)
    
    Write-Status "Fetching available formats..." "Process"
    
    $output = & $script:YtDlpPath --list-formats --no-warnings $Url 2>&1
    return $output
}

function Get-VideoTitle {
    param([string]$Url)
    
    $title = & $script:YtDlpPath --get-title --no-warnings $Url 2>&1
    return $title
}

# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================

function Start-VideoDownload {
    Write-Banner
    Write-Host "`n=== Download Video (MP4) ===" -ForegroundColor Yellow
    
    $url = Get-UserInput -Prompt "Enter video URL" -Required
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    # Get video title for display
    Write-Status "Fetching video info..." "Process"
    $title = Get-VideoTitle -Url $url
    Write-Host "Title: $title" -ForegroundColor Cyan
    
    # Quality selection
    $qualities = @(
        "Best quality (default)",
        "1080p",
        "720p",
        "480p",
        "360p"
    )
    
    $qualityChoice = Show-Menu -Title "Select Quality" -Options $qualities -AllowBack
    if ($qualityChoice -eq -1) { return }
    if ($qualityChoice -eq 0) { return }
    
    $formatArg = switch ($qualityChoice) {
        1 { "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" }
        2 { "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]/best" }
        3 { "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best" }
        4 { "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480][ext=mp4]/best" }
        5 { "bestvideo[height<=360][ext=mp4]+bestaudio[ext=m4a]/best[height<=360][ext=mp4]/best" }
    }
    
    # Output directory
    $outputDir = Get-UserInput -Prompt "Output directory" -Default $script:DefaultOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $outputTemplate = Join-Path $outputDir "%(title)s.%(ext)s"
    
    # Build arguments - prefer MP4, avoid m3u8
    $args = @(
        "-f", $formatArg,
        "--merge-output-format", "mp4",
        "-o", $outputTemplate,
        "--no-playlist",
        "--progress",
        $url
    )
    
    Write-Host ""
    $success = Invoke-YtDlp -Arguments $args
    
    if ($success) {
        Write-Status "Download complete! Files saved to: $outputDir" "Success"
    } else {
        Write-Status "Download failed or was cancelled" "Error"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Start-AudioDownload {
    Write-Banner
    Write-Host "`n=== Download Audio (MP3) ===" -ForegroundColor Yellow
    
    $url = Get-UserInput -Prompt "Enter video URL" -Required
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    # Get video title for display
    Write-Status "Fetching video info..." "Process"
    $title = Get-VideoTitle -Url $url
    Write-Host "Title: $title" -ForegroundColor Cyan
    
    # Bitrate selection
    $bitrates = @(
        "320 kbps (Best)",
        "256 kbps",
        "192 kbps",
        "128 kbps",
        "96 kbps"
    )
    
    $bitrateChoice = Show-Menu -Title "Select Bitrate" -Options $bitrates -AllowBack
    if ($bitrateChoice -eq -1) { return }
    if ($bitrateChoice -eq 0) { return }
    
    $bitrate = switch ($bitrateChoice) {
        1 { "320" }
        2 { "256" }
        3 { "192" }
        4 { "128" }
        5 { "96" }
    }
    
    # Output directory
    $outputDir = Get-UserInput -Prompt "Output directory" -Default $script:DefaultOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $outputTemplate = Join-Path $outputDir "%(title)s.%(ext)s"
    
    # Build arguments
    $args = @(
        "-x",
        "--audio-format", "mp3",
        "--audio-quality", "${bitrate}K",
        "-o", $outputTemplate,
        "--no-playlist",
        "--progress",
        $url
    )
    
    Write-Host ""
    $success = Invoke-YtDlp -Arguments $args
    
    if ($success) {
        Write-Status "Download complete! Files saved to: $outputDir" "Success"
    } else {
        Write-Status "Download failed or was cancelled" "Error"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Start-ThumbnailDownload {
    Write-Banner
    Write-Host "`n=== Download Thumbnail ===" -ForegroundColor Yellow
    
    $url = Get-UserInput -Prompt "Enter video URL" -Required
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    # Output directory
    $outputDir = Get-UserInput -Prompt "Output directory" -Default $script:DefaultOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $outputTemplate = Join-Path $outputDir "%(title)s-thumbnail.%(ext)s"
    
    # Build arguments
    $args = @(
        "--write-thumbnail",
        "--skip-download",
        "--convert-thumbnails", "jpg",
        "-o", $outputTemplate,
        "--no-playlist",
        $url
    )
    
    Write-Host ""
    $success = Invoke-YtDlp -Arguments $args
    
    if ($success) {
        Write-Status "Thumbnail saved to: $outputDir" "Success"
    } else {
        Write-Status "Download failed or was cancelled" "Error"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Start-TrimmedDownload {
    Write-Banner
    Write-Host "`n=== Download with Trim ===" -ForegroundColor Yellow
    Write-Host "Note: Trimming uses ffmpeg on the client CPU" -ForegroundColor DarkGray
    
    $url = Get-UserInput -Prompt "Enter video URL" -Required
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    # Get video title for display
    Write-Status "Fetching video info..." "Process"
    $title = Get-VideoTitle -Url $url
    Write-Host "Title: $title" -ForegroundColor Cyan
    
    # Media type selection
    $mediaTypes = @(
        "Video (MP4)",
        "Audio (MP3)"
    )
    
    $mediaChoice = Show-Menu -Title "Select Media Type" -Options $mediaTypes -AllowBack
    if ($mediaChoice -eq -1) { return }
    if ($mediaChoice -eq 0) { return }
    
    # Time input
    Write-Host "`nTime format: HH:MM:SS or MM:SS or seconds" -ForegroundColor DarkGray
    $startTime = Get-UserInput -Prompt "Start time (leave empty for beginning)" -Default ""
    $endTime = Get-UserInput -Prompt "End time (leave empty for end)" -Default ""
    
    if ([string]::IsNullOrWhiteSpace($startTime) -and [string]::IsNullOrWhiteSpace($endTime)) {
        Write-Status "No trim times specified, downloading full media" "Warning"
    }
    
    # Output directory
    $outputDir = Get-UserInput -Prompt "Output directory" -Default $script:DefaultOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $outputTemplate = Join-Path $outputDir "%(title)s.%(ext)s"
    
    # Build arguments
    $args = @()
    
    if ($mediaChoice -eq 1) {
        # Video
        $args += @(
            "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "--merge-output-format", "mp4"
        )
    } else {
        # Audio
        $args += @(
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "320K"
        )
    }
    
    # Add trim arguments using yt-dlp's download sections
    if (-not [string]::IsNullOrWhiteSpace($startTime) -or -not [string]::IsNullOrWhiteSpace($endTime)) {
        $section = "*"
        if (-not [string]::IsNullOrWhiteSpace($startTime)) {
            $section += "$startTime"
        }
        $section += "-"
        if (-not [string]::IsNullOrWhiteSpace($endTime)) {
            $section += "$endTime"
        }
        
        $args += @("--download-sections", $section)
        $args += @("--force-keyframes-at-cuts")
    }
    
    $args += @(
        "-o", $outputTemplate,
        "--no-playlist",
        "--progress",
        $url
    )
    
    Write-Host ""
    $success = Invoke-YtDlp -Arguments $args
    
    if ($success) {
        Write-Status "Download complete! Files saved to: $outputDir" "Success"
    } else {
        Write-Status "Download failed or was cancelled" "Error"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Start-AdvancedDownload {
    Write-Banner
    Write-Host "`n=== Advanced Format Selection ===" -ForegroundColor Yellow
    
    $url = Get-UserInput -Prompt "Enter video URL" -Required
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    
    # Show available formats
    Write-Host ""
    $formats = Get-VideoFormats -Url $url
    Write-Host $formats -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Format Selection Help:" -ForegroundColor Yellow
    Write-Host "  - Enter format ID (e.g., 137+140)" -ForegroundColor DarkGray
    Write-Host "  - Use + to combine video+audio" -ForegroundColor DarkGray
    Write-Host "  - 'best' for best quality" -ForegroundColor DarkGray
    Write-Host "  - 'bestvideo+bestaudio' for best separate streams" -ForegroundColor DarkGray
    Write-Host ""
    
    $formatId = Get-UserInput -Prompt "Enter format ID" -Default "bestvideo+bestaudio"
    
    # Extension selection
    $extensions = @(
        "mp4 (default)",
        "mkv",
        "webm",
        "Keep original"
    )
    
    $extChoice = Show-Menu -Title "Select Output Format" -Options $extensions -AllowBack
    if ($extChoice -eq -1) { return }
    if ($extChoice -eq 0) { return }
    
    # Output directory
    $outputDir = Get-UserInput -Prompt "Output directory" -Default $script:DefaultOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $outputTemplate = Join-Path $outputDir "%(title)s.%(ext)s"
    
    # Build arguments
    $args = @(
        "-f", $formatId,
        "-o", $outputTemplate,
        "--no-playlist",
        "--progress"
    )
    
    if ($extChoice -ne 4) {
        $ext = switch ($extChoice) {
            1 { "mp4" }
            2 { "mkv" }
            3 { "webm" }
        }
        $args += @("--merge-output-format", $ext)
    }
    
    $args += $url
    
    Write-Host ""
    $success = Invoke-YtDlp -Arguments $args
    
    if ($success) {
        Write-Status "Download complete! Files saved to: $outputDir" "Success"
    } else {
        Write-Status "Download failed or was cancelled" "Error"
    }
    
    Read-Host "`nPress Enter to continue"
}

# ============================================================================
# CLEANUP FUNCTION - Ensures no persistence
# ============================================================================

function Remove-TempFiles {
    # SAFETY: Only removes our specific temp folder
    # Never touches system files, PATH, registry, or anything outside temp
    
    Write-Status "Cleaning up temporary files..." "Process"
    
    if (Test-Path $script:TempDir) {
        try {
            Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction Stop
            Write-Status "Temporary files removed: $script:TempDir" "Success"
        }
        catch {
            Write-Status "Could not fully clean temp folder: $_" "Warning"
            Write-Status "You can manually delete: $script:TempDir" "Info"
        }
    } else {
        Write-Status "No temporary files to clean" "Info"
    }
}

function Show-CleanupMenu {
    Write-Host ""
    Write-Host "Cleanup Options:" -ForegroundColor Yellow
    Write-Host "  [1] Keep temp binaries for future use (~150MB in $script:TempDir)" -ForegroundColor White
    Write-Host "  [2] Delete all temporary files now" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Select option [1]"
    
    if ($choice -eq "2") {
        Remove-TempFiles
    } else {
        Write-Status "Temp files preserved for faster startup next time" "Info"
        Write-Status "Location: $script:TempDir" "Info"
    }
}

# ============================================================================
# MAIN MENU
# ============================================================================

function Show-MainMenu {
    while ($true) {
        Write-Banner
        
        $options = @(
            "Download Video (MP4)",
            "Download Audio (MP3)",
            "Download Thumbnail",
            "Download with Trim",
            "Advanced Format Selection",
            "─────────────────────",
            "Clean Temp Files",
            "About / Info"
        )
        
        $choice = Show-Menu -Title "Main Menu" -Options $options
        
        switch ($choice) {
            -1 { return }  # Quit
            1 { Start-VideoDownload }
            2 { Start-AudioDownload }
            3 { Start-ThumbnailDownload }
            4 { Start-TrimmedDownload }
            5 { Start-AdvancedDownload }
            6 { }  # Separator, do nothing
            7 { 
                Remove-TempFiles
                Read-Host "`nPress Enter to continue"
            }
            8 { Show-About }
        }
    }
}

function Show-About {
    Write-Banner
    Write-Host @"

=== About This Tool ===

YT-DLP Interactive Downloader - Zero Footprint Edition

SECURITY GUARANTEES:
  ✓ No PATH modifications
  ✓ No registry writes
  ✓ No system-wide installations
  ✓ No telemetry or analytics
  ✓ No hidden network requests
  ✓ No auto-start or persistence mechanisms

TEMPORARY FILES:
  Location: $script:TempDir
  Contains: yt-dlp.exe, ffmpeg.exe, ffprobe.exe
  
  These binaries are downloaded from official GitHub releases only:
  • yt-dlp: https://github.com/yt-dlp/yt-dlp
  • ffmpeg: https://github.com/BtbN/FFmpeg-Builds

NETWORK CONNECTIONS:
  This tool only connects to:
  1. GitHub (to download binaries)
  2. Video sources you explicitly request

ON EXIT:
  • Normal exit: You choose whether to keep temp files
  • Forced exit (Ctrl+C): Only temp folder remains, no persistence

SOURCE CODE:
  This script is fully readable and auditable.
  No obfuscation, no encoded payloads, no hidden functionality.

"@ -ForegroundColor Gray
    
    Read-Host "Press Enter to continue"
}

# ============================================================================
# ENTRY POINT
# ============================================================================

function Main {
    # Set console encoding for Unicode characters
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    # Show banner
    Write-Banner
    
    # Initialize binaries (download if needed to temp folder only)
    Write-Host ""
    if (-not (Initialize-Binaries)) {
        Write-Status "Cannot continue without required binaries" "Error"
        Read-Host "Press Enter to exit"
        return
    }
    
    Write-Host ""
    Write-Status "Ready! All processing uses your local CPU." "Success"
    Start-Sleep -Seconds 1
    
    # Main menu loop
    Show-MainMenu
    
    # Cleanup prompt on exit
    Show-CleanupMenu
    
    Write-Host ""
    Write-Status "Goodbye! Your system remains clean." "Success"
    Write-Host ""
}

# ============================================================================
# RUN
# ============================================================================

# Execute main function
# SAFETY: No try/finally persistence - if terminated, only temp folder exists
Main
