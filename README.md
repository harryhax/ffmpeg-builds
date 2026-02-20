# FFmpeg Static Auto-Builds

Static Windows (x86_64) and Linux (x86_64) Builds of ffmpeg master and latest release branch.

Windows builds are targetting Windows 7 and newer, provided UCRT is installed.
The minimum supported version is Windows 10 22H2, no guarantees on anything older.

Linux builds are targetting RHEL/CentOS 8 (glibc-2.28 + linux-4.18) and anything more recent.

## Auto-Builds

Builds run daily at 12:00 UTC (or GitHubs idea of that time) and are automatically released on success.

**Auto-Builds run ONLY for win(arm)64 and linux(arm)64. There are no win32/x86 auto-builds, though you can produce win32 builds yourself following the instructions below.**

### Release Retention Policy

- The last build of each month is kept for two years.
- The last 14 daily builds are kept.
- The special "latest" build floats and provides consistent URLs always pointing to the latest build.

## Package List

For a list of included dependencies check the scripts.d directory.
Every file corresponds to its respective package.

## How to make a build

### Prerequisites

* bash
* docker

### Build Image

* `./makeimage.sh target variant [addin [addin] [addin] ...]`

### Build FFmpeg

* `./build.sh target variant [addin [addin] [addin] ...]`

On success, the resulting zip file will be in the `artifacts` subdir.

### Targets, Variants and Addins

Available targets:
* `win64` (x86_64 Windows)
* `win32` (x86 Windows)
* `linux64` (x86_64 Linux, glibc>=2.28, linux>=4.18)
* `linuxarm64` (arm64 (aarch64) Linux, glibc>=2.28, linux>=4.18)

The linuxarm64 target will not build some dependencies due to lack of arm64 (aarch64) architecture support or cross-compiling restrictions.

* `davs2` and `xavs2`: aarch64 support is broken.
* `libmfx` and `libva`: Library for Intel QSV, so there is no aarch64 support.

Available variants:
* `gpl` Includes all dependencies, even those that require full GPL instead of just LGPL.
* `lgpl` Lacking libraries that are GPL-only. Most prominently libx264 and libx265.
* `nonfree` Includes fdk-aac in addition to all the dependencies of the gpl variant.
* `gpl-shared` Same as gpl, but comes with the libav* family of shared libs instead of pure static executables.
* `lgpl-shared` Same again, but with the lgpl set of dependencies.
* `nonfree-shared` Same again, but with the nonfree set of dependencies.

All of those can be optionally combined with any combination of addins:
* `4.4`/`5.0`/`5.1`/`6.0`/`6.1`/`7.0`/`7.1` to build from the respective release branch instead of master.
* `debug` to not strip debug symbols from the binaries. This increases the output size by about 250MB.
* `lto` build all dependencies and ffmpeg with -flto=auto (HIGHLY EXPERIMENTAL, broken for Windows, sometimes works for Linux)

## macOS Native Builds

This fork adds native macOS FFmpeg builds (no Docker) for testing and iteration on macOS support.

- Build style: native macOS build (no Docker), reusing `scripts.d` patterns where possible with macOS-specific mapping in `scripts.macos.d`
- Default dependency behavior: if no `FF_ENABLE_*` flags are set, all mapped macOS dependencies are enabled by default
- Explicit dependency behavior: if any `FF_ENABLE_*` flag is provided, only flags explicitly set to `1` are enabled
- CI workflow: **Build macOS FFmpeg** (manual trigger only via `workflow_dispatch`)

### Build locally (recommended)

Build with default dependency set (all mapped macOS dependencies):

```bash
./build-macos.sh gpl
```

Build a different variant or use addins:

```bash
./build-macos.sh lgpl-shared 7.1 debug
```

Build with explicit dependency flags (example subset):

```bash
FF_ENABLE_X264=1 FF_ENABLE_X265=1 FF_ENABLE_LIBASS=1 FF_ENABLE_LIBVMAF=1 ./build-macos.sh gpl
```

Disable a dependency explicitly:

```bash
FF_ENABLE_X264=1 FF_ENABLE_LIBAOM=0 ./build-macos.sh gpl
```

Run the macOS smoke suite after a successful build:

```bash
./smoke-test-macos.sh
```

### Trigger a manual CI macOS build

```bash
gh workflow run "Build macOS FFmpeg" --repo harryhax/FFmpeg-Builds --ref macos-builds -f variant=gpl -f addins='' -f enabled_deps='all'
```

### Trigger build + publish release

```bash
gh workflow run "Build macOS FFmpeg" --repo harryhax/FFmpeg-Builds --ref macos-builds -f doRelease=true -f variant=gpl -f addins='' -f enabled_deps='all'
```

### macOS Dependency Status

#### Integrated in this fork

`x264`, `x265`, `libaom`, `libvpx`, `libopus`, `libwebp`, `libvorbis`, `libass`, `libbluray`, `libopenjpeg`, `libsrt`, `libsoxr`, `zimg`, `libssh`, `libzmq`, `snappy`, `libopenmpt`, `libsamplerate`, `libkvazaar`, `sdl2`, `libgme`, `libaribcaption`, `librubberband`, `libvvenc`, `whisper`, `libxvid`, `dav1d`, `libtheora`, `twolame`, `openh264`, `rav1e`, `libmp3lame`, `chromaprint`, `opencore-amr`, `openal`, `svt-av1`, `gmp`, `fribidi`, `frei0r`, `vidstab`, `libvmaf`.

#### Remaining from upstream feature set

##### Likely not a good fit for native macOS

- `50-schannel.sh` - Windows TLS backend (not usable on macOS).
- `50-amf.sh` - AMD AMF path is Windows-centric.
- `50-avisynth.sh` - Avisynth integration is Windows-oriented.
- `50-ffnvcodec.sh` - NVENC/CUDA path is generally Linux/Windows focused.
- `50-onevpl.sh` - Intel oneVPL/QSV path is not a standard macOS target.

##### Possible but difficult / lower priority on macOS

- `50-libplacebo.sh` - often tied to Vulkan-focused rendering stacks.
- `50-openapv.sh` - newer/niche codec path with uncertain macOS value.
- `50-lcevcdec.sh` - niche decoder path with additional integration complexity.

##### Feasible but not integrated yet

- `50-davs2.sh`
- `50-fdk-aac.sh` (nonfree licensing implications)
- `50-uavs3d.sh`
- `50-xavs2.sh`
- `50-zvbi.sh`

### Notes

- This macOS path is fork-specific and not intended to replace upstream Windows/Linux automation.
- Dependency parity with upstream is in progress; some upstream dependencies are platform-specific and may not be practical on macOS.
- If `openal` detection fails locally, install `openal-soft` and ensure Homebrew `pkg-config` paths are exported in your shell environment.
- `.github_bak/` temporarily stores the original upstream GitHub Actions files while macOS-native workflow testing is isolated in `.github/workflows/macos-build.yml`.
- This avoids accidentally triggering upstream-style win/linux image/build pipelines during fork iteration.
- `.github_bak/` will be removed after workflow integration is finalized (macOS flow stabilized and any kept upstream workflows intentionally re-enabled in `.github/workflows`).
