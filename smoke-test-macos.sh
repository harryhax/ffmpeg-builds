#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

FFMPEG_BIN="${FFMPEG_BIN:-./ffbuild/prefix/bin/ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-./ffbuild/prefix/bin/ffprobe}"
OUT_FILE="${OUT_FILE:-./ffbuild/.x264-smoke.mp4}"

if [[ ! -x "$FFMPEG_BIN" ]]; then
    echo "Missing ffmpeg binary: $FFMPEG_BIN"
    exit 1
fi

if [[ ! -x "$FFPROBE_BIN" ]]; then
    echo "Missing ffprobe binary: $FFPROBE_BIN"
    exit 1
fi

trap 'rm -f "$OUT_FILE"' EXIT

"$FFMPEG_BIN" -hide_banner -y \
    -f lavfi -i testsrc=size=128x128:rate=30 \
    -t 1 -c:v libx264 -pix_fmt yuv420p \
    "$OUT_FILE"

CODEC_NAME="$("$FFPROBE_BIN" -hide_banner -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$OUT_FILE")"

if [[ "$CODEC_NAME" != "h264" ]]; then
    echo "Smoke test failed: expected h264, got '$CODEC_NAME'"
    exit 1
fi

echo "Smoke test passed: libx264 encode works (${CODEC_NAME})."