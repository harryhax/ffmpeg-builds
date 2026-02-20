#!/bin/bash
set -euo pipefail

if [[ "${FF_VERBOSE:-0}" == "1" ]]; then
    set -x
fi

cd "$(dirname "$0")"

FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/FFmpeg/FFmpeg.git}"
FFMPEG_REPO="${FFMPEG_REPO_OVERRIDE:-$FFMPEG_REPO}"
GIT_BRANCH="${GIT_BRANCH:-master}"
GIT_BRANCH="${GIT_BRANCH_OVERRIDE:-$GIT_BRANCH}"

TARGET="macos64"
VARIANT="${1:-gpl}"
shift $(( $# > 0 ? 1 : 0 ))

ADDINS=()
ADDINS_STR=""
while [[ "$#" -gt 0 ]]; do
    if ! [[ -f "addins/${1}.sh" ]]; then
        echo "Invalid addin: $1"
        exit 1
    fi
    ADDINS+=( "$1" )
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}$1"
    shift
done

case "$VARIANT" in
    gpl)
        FF_CONFIGURE="--enable-gpl --enable-version3 --disable-debug --disable-shared --enable-static"
        LICENSE_FILE="COPYING.GPLv3"
        ;;
    lgpl)
        FF_CONFIGURE="--enable-version3 --disable-debug --disable-shared --enable-static"
        LICENSE_FILE="COPYING.LGPLv3"
        ;;
    nonfree)
        FF_CONFIGURE="--enable-nonfree --enable-gpl --enable-version3 --disable-debug --disable-shared --enable-static"
        LICENSE_FILE=""
        ;;
    gpl-shared)
        FF_CONFIGURE="--enable-gpl --enable-version3 --disable-debug --enable-shared --disable-static"
        LICENSE_FILE="COPYING.GPLv3"
        ;;
    lgpl-shared)
        FF_CONFIGURE="--enable-version3 --disable-debug --enable-shared --disable-static"
        LICENSE_FILE="COPYING.LGPLv3"
        ;;
    nonfree-shared)
        FF_CONFIGURE="--enable-nonfree --enable-gpl --enable-version3 --disable-debug --enable-shared --disable-static"
        LICENSE_FILE=""
        ;;
    *)
        echo "Invalid variant: ${VARIANT}"
        echo "Supported variants: gpl, lgpl, nonfree, gpl-shared, lgpl-shared, nonfree-shared"
        exit 1
        ;;
esac

if [[ ${#ADDINS[@]} -gt 0 ]]; then
    for addin in "${ADDINS[@]}"; do
        source "addins/${addin}.sh"
    done
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Missing dependency: git"
    exit 1
fi

if ! command -v make >/dev/null 2>&1; then
    echo "Missing dependency: make"
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo "Missing dependency: clang (install Xcode Command Line Tools)"
    exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
    echo "Missing dependency: pkg-config"
    echo "Install it with: brew install pkg-config"
    exit 1
fi

if ! command -v xcode-select >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required. Run: xcode-select --install"
    exit 1
fi

if command -v sysctl >/dev/null 2>&1; then
    JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
else
    JOBS=4
fi

if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH:-}"

    for formula in libsoxr snappy libopenmpt; do
        formula_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
        if [[ -n "$formula_prefix" && -d "$formula_prefix/lib/pkgconfig" ]]; then
            export PKG_CONFIG_PATH="${formula_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH}"
        fi
    done
fi

EXTRA_CONFIGURE="${FF_EXTRA_CONFIGURE:-}"

FF_CFLAGS="${FF_CFLAGS:-}"
FF_CXXFLAGS="${FF_CXXFLAGS:-}"
FF_LDFLAGS="${FF_LDFLAGS:-}"
FF_LDEXEFLAGS="${FF_LDEXEFLAGS:-}"
FF_LIBS="${FF_LIBS:-}"

ffbuild_ffver() {
    local branch="${GIT_BRANCH:-master}"

    if [[ "$branch" == "master" || "$branch" == "main" ]]; then
        echo 999
        return 0
    fi

    if [[ "$branch" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        echo "$((10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]} * 10))"
        return 0
    fi

    if [[ "$branch" =~ ^release/([0-9]+)\.([0-9]+)$ ]]; then
        echo "$((10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]} * 10))"
        return 0
    fi

    echo 999
}

get_scriptsd_stage() {
    local stage="$1"
    local script=(scripts.d/??-${stage}.sh)
    [[ -f "${script[0]}" ]] || return 1
    echo "${script[0]}"
}

get_scriptsd_output() {
    local script="$1"
    local fn="$2"
    (
        source "$script"
        if declare -F "$fn" >/dev/null 2>&1; then
            "$fn"
        fi
        return 0
    )
}

load_macos_dependency_matrix() {
    local overlay="scripts.macos.d/dependencies.sh"
    [[ -f "$overlay" ]] || return 1
    source "$overlay"
    declare -F ffmacos_dependency_matrix >/dev/null 2>&1
}

macos_dep_fail_or_skip() {
    local stage="$1"
    local reason="$2"

    if [[ "${has_explicit_dep_toggles:-0}" -eq 0 ]]; then
        echo "Skipping ${stage}: ${reason}"
        return 0
    fi

    echo "${reason}"
    exit 1
}

enable_scriptsd_dependency() {
    local stage="$1"
    local pkg_module="$2"
    local fallback_mode="${3:-}"

    local dep_script
    dep_script="$(get_scriptsd_stage "$stage")" || {
        echo "Unable to locate scripts.d entry for $stage"
        exit 1
    }

    if ! (
        source "$dep_script"
        if declare -F ffbuild_enabled >/dev/null 2>&1; then
            ffbuild_enabled
        fi
    ); then
        macos_dep_fail_or_skip "$stage" "$stage is disabled for variant '${VARIANT}' according to ${dep_script}"
        return 0
    fi

    local soxr_prefix=""
    local theora_prefix=""
    local ogg_prefix=""
    local twolame_prefix=""
    local mp3lame_prefix=""
    local opencore_amr_prefix=""
    local frei0r_prefix=""
    local gmp_prefix=""
    local xvid_prefix=""
    if [[ "$fallback_mode" == "soxr" ]]; then
        soxr_prefix="$(brew --prefix libsoxr 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "theora" ]]; then
        theora_prefix="$(brew --prefix theora 2>/dev/null || true)"
        ogg_prefix="$(brew --prefix libogg 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "twolame" ]]; then
        twolame_prefix="$(brew --prefix two-lame 2>/dev/null || brew --prefix twolame 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "mp3lame" ]]; then
        mp3lame_prefix="$(brew --prefix lame 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "opencore_amr" ]]; then
        opencore_amr_prefix="$(brew --prefix opencore-amr 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "frei0r" ]]; then
        frei0r_prefix="$(brew --prefix frei0r 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "gmp" ]]; then
        gmp_prefix="$(brew --prefix gmp 2>/dev/null || true)"
    elif [[ "$fallback_mode" == "xvid" ]]; then
        xvid_prefix="$(brew --prefix xvid 2>/dev/null || true)"
    fi

    if [[ -n "$pkg_module" ]] && ! pkg-config --static --exists "$pkg_module"; then
        if [[ "$fallback_mode" == "snappy" ]]; then
            local snappy_prefix
            snappy_prefix="$(brew --prefix snappy 2>/dev/null || true)"
            if [[ -z "$snappy_prefix" || ! -f "$snappy_prefix/include/snappy-c.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and snappy fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${snappy_prefix}/include"
            FF_LIBS="${FF_LIBS} -L${snappy_prefix}/lib -lsnappy -lc++"
        elif [[ "$fallback_mode" == "soxr" ]]; then
            local soxr_pc_dir
            soxr_pc_dir="${soxr_prefix}/lib/pkgconfig"
            if [[ -z "$soxr_prefix" || ! -f "$soxr_prefix/include/soxr.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and soxr fallback failed"
                exit 1
            fi
            if [[ -d "$soxr_pc_dir" ]]; then
                export PKG_CONFIG_PATH="${soxr_pc_dir}:${PKG_CONFIG_PATH:-}"
            fi
            if ! pkg-config --static --exists "$pkg_module"; then
                echo "$stage not found via pkg-config module '$pkg_module' after soxr fallback"
                exit 1
            fi
        elif [[ "$fallback_mode" == "mp3lame" ]]; then
            if [[ -z "$mp3lame_prefix" || ! -f "$mp3lame_prefix/include/lame/lame.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and mp3lame fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${mp3lame_prefix}/include"
            FF_LIBS="${FF_LIBS} -L${mp3lame_prefix}/lib -lmp3lame"
        elif [[ "$fallback_mode" == "opencore_amr" ]]; then
            if [[ -z "$opencore_amr_prefix" || ! -f "$opencore_amr_prefix/include/opencore-amrnb/interf_dec.h" || ! -f "$opencore_amr_prefix/include/opencore-amrwb/dec_if.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and opencore-amr fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${opencore_amr_prefix}/include"
            FF_LIBS="${FF_LIBS} -L${opencore_amr_prefix}/lib -lopencore-amrnb -lopencore-amrwb"
        elif [[ "$fallback_mode" == "frei0r" ]]; then
            if [[ -z "$frei0r_prefix" || ! -f "$frei0r_prefix/include/frei0r.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and frei0r fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${frei0r_prefix}/include"
        elif [[ "$fallback_mode" == "gmp" ]]; then
            if [[ -z "$gmp_prefix" || ! -f "$gmp_prefix/include/gmp.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and gmp fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${gmp_prefix}/include"
            FF_LIBS="${FF_LIBS} -L${gmp_prefix}/lib -lgmp"
        elif [[ "$fallback_mode" == "xvid" ]]; then
            if [[ -z "$xvid_prefix" || ! -f "$xvid_prefix/include/xvid.h" ]]; then
                echo "$stage not found via pkg-config module '$pkg_module' and xvid fallback failed"
                exit 1
            fi
            FF_CFLAGS="${FF_CFLAGS} -I${xvid_prefix}/include"
            FF_LIBS="${FF_LIBS} -L${xvid_prefix}/lib -lxvidcore"
        else
            macos_dep_fail_or_skip "$stage" "$stage not found via pkg-config module '$pkg_module'. Install it with Homebrew and ensure pkg-config can resolve it."
            return 0
        fi
    fi

    if [[ "$fallback_mode" == "soxr" ]]; then
        if [[ -z "$soxr_prefix" || ! -f "$soxr_prefix/include/soxr.h" ]]; then
            echo "$stage fallback could not locate libsoxr headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${soxr_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${soxr_prefix}/lib -lsoxr"
    elif [[ "$fallback_mode" == "theora" ]]; then
        if [[ -z "$theora_prefix" || ! -f "$theora_prefix/include/theora/theoraenc.h" ]]; then
            echo "$stage fallback could not locate libtheora headers"
            exit 1
        fi
        if [[ -z "$ogg_prefix" || ! -f "$ogg_prefix/include/ogg/ogg.h" ]]; then
            echo "$stage fallback could not locate libogg headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${theora_prefix}/include"
        FF_CFLAGS="${FF_CFLAGS} -I${ogg_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${theora_prefix}/lib -L${ogg_prefix}/lib"
    elif [[ "$fallback_mode" == "twolame" ]]; then
        if [[ -z "$twolame_prefix" || ! -f "$twolame_prefix/include/twolame.h" ]]; then
            echo "$stage fallback could not locate libtwolame headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${twolame_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${twolame_prefix}/lib -ltwolame"
    elif [[ "$fallback_mode" == "mp3lame" ]]; then
        if [[ -z "$mp3lame_prefix" || ! -f "$mp3lame_prefix/include/lame/lame.h" ]]; then
            echo "$stage fallback could not locate libmp3lame headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${mp3lame_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${mp3lame_prefix}/lib -lmp3lame"
    elif [[ "$fallback_mode" == "opencore_amr" ]]; then
        if [[ -z "$opencore_amr_prefix" || ! -f "$opencore_amr_prefix/include/opencore-amrnb/interf_dec.h" || ! -f "$opencore_amr_prefix/include/opencore-amrwb/dec_if.h" ]]; then
            echo "$stage fallback could not locate opencore-amr headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${opencore_amr_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${opencore_amr_prefix}/lib -lopencore-amrnb -lopencore-amrwb"
    elif [[ "$fallback_mode" == "frei0r" ]]; then
        if [[ -z "$frei0r_prefix" || ! -f "$frei0r_prefix/include/frei0r.h" ]]; then
            echo "$stage fallback could not locate frei0r headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${frei0r_prefix}/include"
    elif [[ "$fallback_mode" == "gmp" ]]; then
        if [[ -z "$gmp_prefix" || ! -f "$gmp_prefix/include/gmp.h" ]]; then
            echo "$stage fallback could not locate gmp headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${gmp_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${gmp_prefix}/lib -lgmp"
    elif [[ "$fallback_mode" == "xvid" ]]; then
        if [[ -z "$xvid_prefix" || ! -f "$xvid_prefix/include/xvid.h" ]]; then
            echo "$stage fallback could not locate xvid headers"
            exit 1
        fi
        FF_CFLAGS="${FF_CFLAGS} -I${xvid_prefix}/include"
        FF_LIBS="${FF_LIBS} -L${xvid_prefix}/lib -lxvidcore"
    fi

    local dep_conf dep_cflags dep_cxxflags dep_ldflags dep_ldexeflags dep_libs
    dep_conf="$(get_scriptsd_output "$dep_script" ffbuild_configure | xargs)"
    [[ -n "$dep_conf" ]] && EXTRA_CONFIGURE="${EXTRA_CONFIGURE} ${dep_conf}"

    dep_cflags="$(get_scriptsd_output "$dep_script" ffbuild_cflags | xargs)"
    [[ -n "$dep_cflags" ]] && FF_CFLAGS="${FF_CFLAGS} ${dep_cflags}"

    dep_cxxflags="$(get_scriptsd_output "$dep_script" ffbuild_cxxflags | xargs)"
    [[ -n "$dep_cxxflags" ]] && FF_CXXFLAGS="${FF_CXXFLAGS} ${dep_cxxflags}"

    if [[ "$TARGET" != macos* ]]; then
        dep_ldflags="$(get_scriptsd_output "$dep_script" ffbuild_ldflags | xargs)"
        [[ -n "$dep_ldflags" ]] && FF_LDFLAGS="${FF_LDFLAGS} ${dep_ldflags}"

        dep_ldexeflags="$(get_scriptsd_output "$dep_script" ffbuild_ldexeflags | xargs)"
        [[ -n "$dep_ldexeflags" ]] && FF_LDEXEFLAGS="${FF_LDEXEFLAGS} ${dep_ldexeflags}"

        dep_libs="$(get_scriptsd_output "$dep_script" ffbuild_libs | xargs)"
        [[ -n "$dep_libs" ]] && FF_LIBS="${FF_LIBS} ${dep_libs}"
    fi

    return 0
}

if [[ "$(uname -m)" == "x86_64" ]] && ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
    echo "Neither nasm nor yasm found on x86_64 macOS; using --disable-x86asm for baseline build."
    EXTRA_CONFIGURE="${EXTRA_CONFIGURE} --disable-x86asm"
fi

if ! load_macos_dependency_matrix; then
    echo "Missing macOS dependency matrix: scripts.macos.d/dependencies.sh"
    exit 1
fi

has_explicit_dep_toggles=0
while IFS='|' read -r env_var _ _ _; do
    [[ -z "$env_var" ]] && continue
    [[ "$env_var" =~ ^# ]] && continue
    if [[ -n "${!env_var+x}" ]]; then
        has_explicit_dep_toggles=1
        break
    fi
done < <(ffmacos_dependency_matrix)

if [[ "$has_explicit_dep_toggles" -eq 0 ]]; then
    echo "No FF_ENABLE_* dependency toggles provided; defaulting to enabling all mapped macOS dependencies."
fi

while IFS='|' read -r env_var stage pkg_module fallback_mode; do
    [[ -z "$env_var" ]] && continue
    [[ "$env_var" =~ ^# ]] && continue

    if [[ "$has_explicit_dep_toggles" -eq 0 || "${!env_var:-0}" == "1" ]]; then
        enable_scriptsd_dependency "$stage" "$pkg_module" "$fallback_mode"
    fi
done < <(ffmacos_dependency_matrix)

rm -rf ffbuild
mkdir -p ffbuild

git clone --filter=blob:none --depth=1 --branch="$GIT_BRANCH" "$FFMPEG_REPO" ffbuild/ffmpeg

pushd ffbuild/ffmpeg >/dev/null

./configure \
    --prefix="$PWD/../prefix" \
    --disable-autodetect \
    --enable-videotoolbox \
    ${FF_CONFIGURE} \
    --extra-cflags="${FF_CFLAGS}" \
    --extra-cxxflags="${FF_CXXFLAGS}" \
    --extra-ldflags="${FF_LDFLAGS}" \
    --extra-ldexeflags="${FF_LDEXEFLAGS}" \
    --extra-libs="${FF_LIBS}" \
    ${EXTRA_CONFIGURE}

make -j"$JOBS" V=1
make install

popd >/dev/null

ARTIFACTS_DIR="artifacts/macos"
mkdir -p "$ARTIFACTS_DIR"
BUILD_NAME="ffmpeg-$(./ffbuild/ffmpeg/ffbuild/version.sh ffbuild/ffmpeg)-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"

mkdir -p "ffbuild/pkgroot/$BUILD_NAME"

mkdir -p "ffbuild/pkgroot/$BUILD_NAME/bin"
cp ffbuild/prefix/bin/* "ffbuild/pkgroot/$BUILD_NAME/bin"

if [[ "$VARIANT" == *-shared ]]; then
    mkdir -p "ffbuild/pkgroot/$BUILD_NAME/lib"
    if [[ -d ffbuild/prefix/lib ]]; then
        cp -a ffbuild/prefix/lib/*.dylib* "ffbuild/pkgroot/$BUILD_NAME/lib" 2>/dev/null || true
    fi

    mkdir -p "ffbuild/pkgroot/$BUILD_NAME/lib/pkgconfig"
    if [[ -d ffbuild/prefix/lib/pkgconfig ]]; then
        cp -a ffbuild/prefix/lib/pkgconfig/*.pc "ffbuild/pkgroot/$BUILD_NAME/lib/pkgconfig" 2>/dev/null || true
        sed -i '' \
            -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
            -e 's|'"$PWD/../prefix"'|${prefix}|' \
            -e '/Libs.private:/d' \
            "ffbuild/pkgroot/$BUILD_NAME/lib/pkgconfig"/*.pc 2>/dev/null || true
    fi

    mkdir -p "ffbuild/pkgroot/$BUILD_NAME/include"
    if [[ -d ffbuild/prefix/include ]]; then
        cp -r ffbuild/prefix/include/* "ffbuild/pkgroot/$BUILD_NAME/include" 2>/dev/null || true
    fi
fi

mkdir -p "ffbuild/pkgroot/$BUILD_NAME/doc"
if [[ -d ffbuild/prefix/share/doc/ffmpeg ]]; then
    cp -r ffbuild/prefix/share/doc/ffmpeg/* "ffbuild/pkgroot/$BUILD_NAME/doc" 2>/dev/null || true
fi

mkdir -p "ffbuild/pkgroot/$BUILD_NAME/man"
if [[ -d ffbuild/prefix/share/man ]]; then
    cp -r ffbuild/prefix/share/man/* "ffbuild/pkgroot/$BUILD_NAME/man" 2>/dev/null || true
fi

mkdir -p "ffbuild/pkgroot/$BUILD_NAME/presets"
if [[ -d ffbuild/prefix/share/ffmpeg ]]; then
    cp ffbuild/prefix/share/ffmpeg/*.ffpreset "ffbuild/pkgroot/$BUILD_NAME/presets" 2>/dev/null || true
fi

if [[ -n "$LICENSE_FILE" ]]; then
    cp "ffbuild/ffmpeg/$LICENSE_FILE" "ffbuild/pkgroot/$BUILD_NAME/LICENSE.txt"
fi

pushd ffbuild/pkgroot >/dev/null
tar cJf "$PWD/../../${ARTIFACTS_DIR}/${BUILD_NAME}.tar.xz" "$BUILD_NAME"
popd >/dev/null

echo
echo "Build complete: ${ARTIFACTS_DIR}/${BUILD_NAME}.tar.xz"
echo "Tip: add options incrementally with FF_EXTRA_CONFIGURE, e.g."
echo "  FF_EXTRA_CONFIGURE='--enable-libx264 --enable-gpl' ./build-macos.sh gpl"
echo "Or use built-in x264 step:"
echo "  FF_ENABLE_X264=1 ./build-macos.sh gpl"
echo "Additional scripts.d-backed toggles:"
echo "  FF_ENABLE_X265=1 FF_ENABLE_LIBAOM=1 FF_ENABLE_LIBVPX=1 FF_ENABLE_LIBOPUS=1 FF_ENABLE_LIBWEBP=1 FF_ENABLE_LIBVORBIS=1 ./build-macos.sh gpl"
echo "  FF_ENABLE_LIBASS=1 FF_ENABLE_LIBBLURAY=1 FF_ENABLE_LIBOPENJPEG=1 FF_ENABLE_LIBSRT=1 FF_ENABLE_LIBSOXR=1 FF_ENABLE_LIBZIMG=1 FF_ENABLE_LIBSSH=1 FF_ENABLE_LIBZMQ=1 FF_ENABLE_LIBSNAPPY=1 FF_ENABLE_LIBOPENMPT=1 ./build-macos.sh gpl"
echo "  FF_ENABLE_LIBDAV1D=1 FF_ENABLE_LIBTHEORA=1 FF_ENABLE_LIBTWOLAME=1 FF_ENABLE_LIBOPENH264=1 FF_ENABLE_LIBRAV1E=1 ./build-macos.sh gpl"
