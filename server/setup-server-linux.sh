#!/usr/bin/env bash
set -euo pipefail

PORT=8080
BIND="0.0.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bins"

YT_DLP_URL="${YT_DLP_URL:-https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe}"
FFMPEG_URL="${FFMPEG_URL:-https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --port <PORT>    Port to bind (default: 8080)
  -b, --bind <IP>      Bind address (default: 0.0.0.0)
  -h, --help           Show this help

Environment overrides:
  YT_DLP_URL, FFMPEG_URL
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"; shift 2;;
        -b|--bind)
            BIND="$2"; shift 2;;
        -h|--help)
            usage;;
        *)
            echo "Unknown option: $1" >&2
            usage;;
    esac
done

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_cmd curl
require_cmd unzip
require_cmd python3

mkdir -p "$BIN_DIR"

YT_DLP_PATH="$BIN_DIR/yt-dlp.exe"
FFMPEG_PATH="$BIN_DIR/ffmpeg.exe"
FFPROBE_PATH="$BIN_DIR/ffprobe.exe"

if [[ ! -f "$YT_DLP_PATH" ]]; then
    echo "[+] Downloading yt-dlp.exe"
    curl -L "$YT_DLP_URL" -o "$YT_DLP_PATH"
fi

if [[ ! -f "$FFMPEG_PATH" || ! -f "$FFPROBE_PATH" ]]; then
    echo "[+] Downloading ffmpeg essentials zip"
    tmp_zip="$(mktemp -t ffmpeg.XXXXXX.zip)"
    tmp_dir="$(mktemp -d -t ffmpeg.XXXXXX)"
    curl -L "$FFMPEG_URL" -o "$tmp_zip"
    unzip -q "$tmp_zip" -d "$tmp_dir"

    ff="$(find "$tmp_dir" -type f -name 'ffmpeg.exe' | head -n 1)"
    fp="$(find "$tmp_dir" -type f -name 'ffprobe.exe' | head -n 1)"

    if [[ -z "$ff" || -z "$fp" ]]; then
        echo "Failed to locate ffmpeg.exe or ffprobe.exe inside archive" >&2
        exit 1
    fi

    cp "$ff" "$FFMPEG_PATH"
    cp "$fp" "$FFPROBE_PATH"

    rm -f "$tmp_zip"
    rm -rf "$tmp_dir"
fi

cat <<EOF
============================================================
 Binary server running (Linux)
============================================================
Directory : $BIN_DIR
Bind      : $BIND
Port      : $PORT

Available files:
  /yt-dlp.exe
  /ffmpeg.exe
  /ffprobe.exe

Example client config (winfetch.ps1):
Sources = @{
    YtDlp  = "http://<server-ip>:$PORT/yt-dlp.exe"
    Ffmpeg = "http://<server-ip>:$PORT/ffmpeg.exe"
}
EOF

cd "$BIN_DIR"
python3 -m http.server "$PORT" --bind "$BIND"
