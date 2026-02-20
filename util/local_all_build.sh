#!/bin/bash
set -euo pipefail

BREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH:-}"

for formula in libsoxr snappy libopenmpt openal-soft svt-av1 chromaprint opencore-amr lame theora two-lame; do
    formula_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -n "$formula_prefix" && -d "$formula_prefix/lib/pkgconfig" ]]; then
        export PKG_CONFIG_PATH="$formula_prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
    fi
done

FF_ENABLE_X264=1 \
FF_ENABLE_X265=1 \
FF_ENABLE_LIBAOM=1 \
FF_ENABLE_LIBVPX=1 \
FF_ENABLE_LIBOPUS=1 \
FF_ENABLE_LIBWEBP=1 \
FF_ENABLE_LIBVORBIS=1 \
FF_ENABLE_LIBASS=1 \
FF_ENABLE_LIBBLURAY=1 \
FF_ENABLE_LIBOPENJPEG=1 \
FF_ENABLE_LIBSRT=1 \
FF_ENABLE_LIBSOXR=1 \
FF_ENABLE_LIBZIMG=1 \
FF_ENABLE_LIBSSH=1 \
FF_ENABLE_LIBZMQ=1 \
FF_ENABLE_LIBSNAPPY=1 \
FF_ENABLE_LIBOPENMPT=1 \
FF_ENABLE_LIBDAV1D=1 \
FF_ENABLE_LIBTHEORA=1 \
FF_ENABLE_LIBTWOLAME=1 \
FF_ENABLE_LIBOPENH264=1 \
FF_ENABLE_LIBRAV1E=1 \
FF_ENABLE_LIBMP3LAME=1 \
FF_ENABLE_CHROMAPRINT=1 \
FF_ENABLE_LIBOPENCORE_AMR=1 \
FF_ENABLE_OPENAL=1 \
FF_ENABLE_LIBSVTAV1=1 \
FF_VERBOSE=1 \
./build-macos.sh gpl 2>&1 | tee /tmp/local-all-build.log
