## WinFetch - Fast YT-DLP Downloader

Zero-footprint video/audio downloader with **parallel binary fetching**.

## Quick Start

```powershell
# Run directly
.\winfetch.ps1

# Or one-liner from web
irm https://raw.githubusercontent.com/rinkanekoii/WinFetch/main/winfetch.ps1 | iex
```

## Server Mode (Faster Downloads)

Host binaries on your LAN server for instant client setup:

```powershell
# On server - downloads binaries once, serves via HTTP
.\server\setup-server.ps1 -Port 8080

# On clients - edit winfetch.ps1 Sources section:
Sources = @{
    YtDlp  = "http://YOUR_SERVER_IP:8080/yt-dlp.exe"
    Ffmpeg = "http://YOUR_SERVER_IP:8080/ffmpeg.exe"
}
```

### Linux server

```bash
chmod +x server/setup-server-linux.sh
./server/setup-server-linux.sh --port 8080 --bind 0.0.0.0

# Then point clients to http://<server-ip>:8080
```

## Features

- **Parallel downloads** - yt-dlp + ffmpeg fetch simultaneously
- **Smaller ffmpeg** - Uses essentials build (~30MB vs ~100MB)
- **Server hosting** - Pre-cache binaries on LAN
- **Batch mode** - Download multiple URLs
- **Clean code** - ~300 lines vs 800+

## Files

| File | Description |
|------|-------------|
| `winfetch.ps1` | Main client script |
| `server/setup-server.ps1` | Binary hosting server |
| `idx.ps1` | Original script (legacy) |
