#!/bin/bash
set -euo pipefail

ffbin="./ffbuild/prefix/bin/ffmpeg"
summary="/tmp/local-smoke-summary.txt"
: > "$summary"

if [[ ! -x "$ffbin" ]]; then
  echo "FAIL missing_ffmpeg_binary" >> "$summary"
  echo "SUMMARY pass=0 fail=1" >> "$summary"
  exit 1
fi

bc="$($ffbin -hide_banner -buildconf 2>/dev/null)"
enc="$($ffbin -hide_banner -encoders 2>/dev/null)"
dec="$($ffbin -hide_banner -decoders 2>/dev/null)"
flt="$($ffbin -hide_banner -filters 2>/dev/null)"
pro="$($ffbin -hide_banner -protocols 2>/dev/null)"
dev="$($ffbin -hide_banner -devices 2>/dev/null)"
mux="$($ffbin -hide_banner -muxers 2>/dev/null)"

pass=0
fail=0
check() {
  local name="$1"
  local text="$2"
  local pattern="$3"
  if echo "$text" | grep -qE -- "$pattern"; then
    echo "PASS $name" >> "$summary"
    pass=$((pass+1))
  else
    echo "FAIL $name" >> "$summary"
    fail=$((fail+1))
  fi
}

check flag_x264 "$bc" '--enable-libx264'
check flag_x265 "$bc" '--enable-libx265'
check flag_libaom "$bc" '--enable-libaom'
check flag_libvpx "$bc" '--enable-libvpx'
check flag_libopus "$bc" '--enable-libopus'
check flag_libwebp "$bc" '--enable-libwebp'
check flag_libvorbis "$bc" '--enable-libvorbis'
check flag_libass "$bc" '--enable-libass'
check flag_libbluray "$bc" '--enable-libbluray'
check flag_libopenjpeg "$bc" '--enable-libopenjpeg'
check flag_libsrt "$bc" '--enable-libsrt'
check flag_libsoxr "$bc" '--enable-libsoxr'
check flag_libzimg "$bc" '--enable-libzimg'
check flag_libssh "$bc" '--enable-libssh'
check flag_libzmq "$bc" '--enable-libzmq'
check flag_libsnappy "$bc" '--enable-libsnappy'
check flag_libopenmpt "$bc" '--enable-libopenmpt'
check flag_libdav1d "$bc" '--enable-libdav1d'
check flag_libtheora "$bc" '--enable-libtheora'
check flag_libtwolame "$bc" '--enable-libtwolame'
check flag_libopenh264 "$bc" '--enable-libopenh264'
check flag_librav1e "$bc" '--enable-librav1e'
check flag_libmp3lame "$bc" '--enable-libmp3lame'
check flag_chromaprint "$bc" '--enable-chromaprint'
check flag_libopencore_amrnb "$bc" '--enable-libopencore-amrnb'
check flag_libopencore_amrwb "$bc" '--enable-libopencore-amrwb'
check flag_openal "$bc" '--enable-openal'
check flag_libsvtav1 "$bc" '--enable-libsvtav1'

check enc_libx264 "$enc" 'libx264'
check enc_libx265 "$enc" 'libx265'
check enc_libaom_av1 "$enc" 'libaom-av1'
check enc_libvpx_vp9 "$enc" 'libvpx-vp9'
check enc_libopus "$enc" 'libopus'
check enc_libwebp "$enc" 'libwebp'
check enc_libvorbis "$enc" 'libvorbis'
check enc_libopenjpeg "$enc" 'libopenjpeg'
check enc_libtwolame "$enc" 'libtwolame'
check enc_libopenh264 "$enc" 'libopenh264'
check enc_librav1e "$enc" 'librav1e'
check enc_libmp3lame "$enc" 'libmp3lame'
check enc_libopencore_amrnb "$enc" 'libopencore_amrnb'
check enc_libsvtav1 "$enc" 'libsvtav1'
check dec_libdav1d "$dec" 'libdav1d'
check pro_srt "$pro" '\<srt\>'
check flt_zscale "$flt" '\<zscale\>'
check flt_ass "$flt" '\<ass\>'
check dev_openal "$dev" '\<openal\>'
check mux_chromaprint "$mux" '\<chromaprint\>'

echo "SUMMARY pass=$pass fail=$fail" >> "$summary"
[[ $fail -eq 0 ]]
