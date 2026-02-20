#!/bin/bash
set -euo pipefail

BREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH:-}"

for formula in gmp fribidi frei0r vid.stab libvmaf; do
    formula_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -n "$formula_prefix" && -d "$formula_prefix/lib/pkgconfig" ]]; then
        export PKG_CONFIG_PATH="$formula_prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
    fi
done

FF_ENABLE_GMP=1 \
FF_ENABLE_LIBFRIBIDI=1 \
FF_ENABLE_FREI0R=1 \
FF_ENABLE_LIBVIDSTAB=1 \
FF_ENABLE_LIBVMAF=1 \
FF_VERBOSE=1 \
./build-macos.sh gpl 2>&1 | tee /tmp/local-next5-build.log
