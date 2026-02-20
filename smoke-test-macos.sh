#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

FFMPEG_BIN="${FFMPEG_BIN:-./ffbuild/prefix/bin/ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-./ffbuild/prefix/bin/ffprobe}"
WORK_DIR="${WORK_DIR:-./ffbuild/.smoke-all}"

if [[ ! -x "$FFMPEG_BIN" ]]; then
    echo "Missing ffmpeg binary: $FFMPEG_BIN"
    exit 1
fi

if [[ ! -x "$FFPROBE_BIN" ]]; then
    echo "Missing ffprobe binary: $FFPROBE_BIN"
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

FAILURES=0

check_flag() {
    local flag="$1"
    if "$FFMPEG_BIN" -hide_banner -buildconf | grep -q -- "$flag"; then
        echo "CONF:${flag} PASS"
    else
        echo "CONF:${flag} FAIL"
        FAILURES=$((FAILURES + 1))
    fi
}

check_cmd() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "SMOKE:${name} PASS"
    else
        echo "SMOKE:${name} FAIL"
        FAILURES=$((FAILURES + 1))
    fi
}

check_codec() {
    local name="$1"
    local file="$2"
    local expected="$3"
    local got
    got="$("$FFPROBE_BIN" -hide_banner -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$file" 2>/dev/null || true)"
    if [[ "$got" == "$expected" ]]; then
        echo "PROBE:${name} PASS (${got})"
    else
        echo "PROBE:${name} FAIL (expected ${expected}, got ${got:-none})"
        FAILURES=$((FAILURES + 1))
    fi
}

for flag in \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libaom \
    --enable-libvpx \
    --enable-libopus \
    --enable-libwebp \
    --enable-libvorbis \
    --enable-libass \
    --enable-libbluray \
    --enable-libopenjpeg \
    --enable-libsrt \
    --enable-libsoxr \
    --enable-libzimg \
    --enable-libssh \
    --enable-libzmq \
    --enable-libsnappy \
    --enable-libopenmpt \
    --enable-libkvazaar \
    --enable-sdl2 \
    --enable-libdav1d \
    --enable-libtheora \
    --enable-libtwolame \
    --enable-libopenh264 \
    --enable-librav1e \
    --enable-libmp3lame \
    --enable-chromaprint \
    --enable-libopencore-amrnb \
    --enable-libopencore-amrwb \
    --enable-openal \
    --enable-libsvtav1 \
    --enable-gmp \
    --enable-libfribidi \
    --enable-frei0r \
    --enable-libvidstab \
    --enable-libvmaf; do
    check_flag "$flag"
done

check_cmd x264 "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=24 -t 1 -c:v libx264 "$WORK_DIR/x264.mp4"
check_cmd x265 "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=24 -t 1 -c:v libx265 "$WORK_DIR/x265.mp4"
check_cmd aom "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -t 1 -c:v libaom-av1 -cpu-used 8 "$WORK_DIR/aom.mkv"
check_cmd vpx "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -t 1 -c:v libvpx-vp9 "$WORK_DIR/vpx.webm"
check_cmd openh264 "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=24 -t 1 -c:v libopenh264 "$WORK_DIR/openh264.mp4"
check_cmd openjpeg "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=1 -frames:v 1 -c:v libopenjpeg "$WORK_DIR/openjpeg.jp2"
check_cmd webp "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=1 -frames:v 1 -c:v libwebp "$WORK_DIR/webp.webp"
check_cmd theora "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -t 1 -c:v libtheora "$WORK_DIR/theora.ogv"
check_cmd rav1e "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -t 1 -c:v librav1e -speed 10 "$WORK_DIR/rav1e.mkv"
check_cmd svtav1 "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -t 1 -c:v libsvtav1 -preset 12 "$WORK_DIR/svtav1.mkv"
check_cmd kvazaar "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=24 -t 1 -c:v libkvazaar "$WORK_DIR/kvazaar.mp4"

check_cmd mp3lame "$FFMPEG_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -c:a libmp3lame "$WORK_DIR/mp3lame.mp3"
check_cmd twolame "$FFMPEG_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -c:a libtwolame "$WORK_DIR/twolame.mp2"
check_cmd opus "$FFMPEG_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -c:a libopus "$WORK_DIR/opus.ogg"
check_cmd vorbis "$FFMPEG_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -c:a libvorbis "$WORK_DIR/vorbis.ogg"

check_cmd soxr "$FFMPEG_BIN" -hide_banner -y -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 1 -af aresample=resampler=soxr "$WORK_DIR/soxr.wav"
check_cmd zimg "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=1 -frames:v 1 -vf zscale -f null -
check_cmd sdl2_device bash -lc '"$0" -hide_banner -devices 2>/dev/null | grep -q "sdl2"' "$FFMPEG_BIN"
check_cmd vmaf_filter "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -f lavfi -i testsrc=size=96x96:rate=12 -frames:v 10 -lavfi libvmaf -f null -
check_cmd vidstab_filter "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc=size=96x96:rate=12 -frames:v 10 -vf vidstabdetect=shakiness=5:result="$WORK_DIR/vidstab.trf" -f null -

check_cmd dav1d_decode "$FFMPEG_BIN" -hide_banner -y -c:v libdav1d -i "$WORK_DIR/aom.mkv" -f null -

if [[ -f "$WORK_DIR/x264.mp4" ]]; then
    check_codec x264 "$WORK_DIR/x264.mp4" h264
fi
if [[ -f "$WORK_DIR/x265.mp4" ]]; then
    check_codec x265 "$WORK_DIR/x265.mp4" hevc
fi
if [[ -f "$WORK_DIR/aom.mkv" ]]; then
    check_codec aom "$WORK_DIR/aom.mkv" av1
fi
if [[ -f "$WORK_DIR/vpx.webm" ]]; then
    check_codec vpx "$WORK_DIR/vpx.webm" vp9
fi
if [[ -f "$WORK_DIR/openjpeg.jp2" ]]; then
    check_codec openjpeg "$WORK_DIR/openjpeg.jp2" jpeg2000
fi
if [[ -f "$WORK_DIR/kvazaar.mp4" ]]; then
    check_codec kvazaar "$WORK_DIR/kvazaar.mp4" hevc
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "Smoke test suite passed."
    exit 0
fi

echo "Smoke test suite failed: ${FAILURES} checks failed."
exit 1