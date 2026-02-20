#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

RUN_ID="${1:-}"
ARTIFACT_NAME="${2:-ffmpeg-macos-gpl}"

if [[ -z "$RUN_ID" ]]; then
    echo "Usage: ./verify-artifact.sh <run_id> [artifact_name]"
    echo "Example: ./verify-artifact.sh 22168969833"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "Missing dependency: gh (GitHub CLI)"
    exit 1
fi

WORK_DIR="ffbuild/ci-verify"
ART_DIR="$WORK_DIR/artifact"
EXT_DIR="$WORK_DIR/extract"
SMOKE_DIR="$WORK_DIR/smoke"

rm -rf "$WORK_DIR"
mkdir -p "$ART_DIR" "$EXT_DIR" "$SMOKE_DIR"

echo "Downloading artifact '$ARTIFACT_NAME' from run $RUN_ID..."
gh run download "$RUN_ID" -n "$ARTIFACT_NAME" -D "$ART_DIR" >/dev/null

TAR_FILE="$(ls "$ART_DIR"/*.tar.xz | head -n 1)"
tar -xJf "$TAR_FILE" -C "$EXT_DIR"

CI_BIN="$(find "$EXT_DIR" -type f -path '*/bin/ffmpeg' | head -n 1)"
CI_PROBE="$(find "$EXT_DIR" -type f -path '*/bin/ffprobe' | head -n 1)"

if [[ -z "$CI_BIN" || -z "$CI_PROBE" ]]; then
    echo "Could not locate ffmpeg/ffprobe in extracted artifact."
    exit 1
fi

echo "ffmpeg: $CI_BIN"

if ! "$CI_BIN" -hide_banner -version >/dev/null 2>&1; then
    echo "Artifact binary cannot run in this environment (missing runtime dylibs)."
    echo "Try updating Homebrew libraries (for example: brew upgrade libvpx)."
    exit 2
fi

FAILURES=0

check_conf() {
    local lib="$1"
    if "$CI_BIN" -hide_banner -buildconf | grep -q -- "--enable-$lib"; then
        echo "CONF:$lib PASS"
    else
        echo "CONF:$lib FAIL"
        FAILURES=$((FAILURES + 1))
    fi
}

check_cmd() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "SMOKE:$name PASS"
    else
        echo "SMOKE:$name FAIL"
        FAILURES=$((FAILURES + 1))
    fi
}

for lib in libx264 libx265 libaom libvpx libopus libwebp libvorbis libass libbluray libopenjpeg libsrt libsoxr libzimg libssh libzmq libsnappy libopenmpt; do
    check_conf "$lib"
done

check_cmd x264 "$CI_BIN" -hide_banner -y -f lavfi -i testsrc=size=64x64:rate=24 -t 1 -c:v libx264 "$SMOKE_DIR/x264.mp4"
check_cmd x265 "$CI_BIN" -hide_banner -y -f lavfi -i testsrc=size=64x64:rate=24 -t 1 -c:v libx265 "$SMOKE_DIR/x265.mp4"
check_cmd openjpeg "$CI_BIN" -hide_banner -y -f lavfi -i testsrc=size=64x64:rate=1 -frames:v 1 -c:v libopenjpeg "$SMOKE_DIR/openjpeg.jp2"
check_cmd soxr "$CI_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -af aresample=resampler=soxr "$SMOKE_DIR/soxr.wav"
check_cmd zimg "$CI_BIN" -hide_banner -y -f lavfi -i testsrc=size=64x64:rate=1 -frames:v 1 -vf zscale -f null -

if [[ -f "$SMOKE_DIR/x264.mp4" ]]; then
    "$CI_PROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$SMOKE_DIR/x264.mp4" | sed 's/^/PROBE:x264 /'
fi
if [[ -f "$SMOKE_DIR/x265.mp4" ]]; then
    "$CI_PROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$SMOKE_DIR/x265.mp4" | sed 's/^/PROBE:x265 /'
fi
if [[ -f "$SMOKE_DIR/openjpeg.jp2" ]]; then
    "$CI_PROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$SMOKE_DIR/openjpeg.jp2" | sed 's/^/PROBE:openjpeg /'
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "Verification complete: PASS"
    exit 0
fi

echo "Verification complete: FAIL ($FAILURES checks failed)"
exit 1
