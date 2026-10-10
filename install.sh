#!/bin/bash
# Compatible with the Bash 3.2 shipped with macOS. Run with bash, not sh.
set -euo pipefail

IOQ3_REV=83a776283bdb958f82db25554b5ed0966aaf6e49
PAK0_SHA256=7ce8b3910620cd50a09e4f1100f426e8c6180f68895d589f80e6bd95af54bcae
PATCH_SHA256=95a811825a43260b2c52af97ef6f2c26fcc16d0032b3a132d6c4b20457a10ced
INSTALL_DIR=${Q3_INSTALL_DIR:-"$HOME/Applications/ioquake3"}
CACHE_DIR=${Q3_CACHE_DIR:-"$HOME/Library/Caches/quake3-installer"}
PAK0_URL=${Q3_PAK0_URL:-https://raw.githubusercontent.com/nrempel/q3-server/master/baseq3/pak0.pk3}
PATCH_URL=${Q3_PATCH_URL:-https://files.ioquake3.org/quake3-latest-pk3s.zip}
WORK_DIR=

log() { printf '\n%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
cleanup() { if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

valid_file() {
    [ -f "$1" ] && [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ]
}

download() {
    local url=$1 destination=$2 checksum=$3
    if valid_file "$destination" "$checksum"; then
        log "Using verified cache: $(basename "$destination")"
        return
    fi
    log "Downloading $(basename "$destination")"
    # A failed transfer never replaces a previously downloaded file.
    curl --fail --location --show-error --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 1800 --continue-at - \
        --output "$destination.part" "$url" || return 1
    valid_file "$destination.part" "$checksum" || {
        printf 'Checksum mismatch: %s\n' "$url" >&2
        rm -f "$destination.part"
        return 1
    }
    mv -f "$destination.part" "$destination"
}

usage() {
    cat <<'HELP'
Usage: bash install.sh [--help]
Build and install ioquake3 for Apple Silicon and Intel macOS.
Downloads all original Quake III Arena assets (baseq3/pak0-pak8.pk3).

Optional environment variables:
  Q3_INSTALL_DIR  Destination (default: ~/Applications/ioquake3)
  Q3_CACHE_DIR    Verified download cache (default: ~/Library/Caches/quake3-installer)
  Q3_PAK0        Local retail pak0.pk3 instead of downloading it
  Q3_PAK0_URL    Alternate HTTPS mirror of the same retail pak0.pk3
  Q3_PATCH_URL   Alternate HTTPS mirror of quake3-latest-pk3s.zip
  Q3_JOBS        Parallel build jobs (default: number of CPU cores)
HELP
}

main() {
    if [ "${1:-}" = '--help' ]; then usage; return; fi
    [ "$#" -eq 0 ] || die 'Unknown argument. Use --help.'
    [ "$(uname -s)" = Darwin ] || die 'This installer requires macOS.'
    [ "$(id -u)" -ne 0 ] || die 'Run as your normal user, without sudo.'
    case "$(uname -m)" in arm64|x86_64) ;; *) die 'Only Apple Silicon and Intel Macs are supported.' ;; esac
    # sysctl identifies Apple Silicon even when Terminal is running via Rosetta.
    local native_arch=x86_64
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then native_arch=arm64; fi
    case "$INSTALL_DIR" in /*) ;; *) die 'Q3_INSTALL_DIR must be an absolute path.' ;; esac
    case "$CACHE_DIR" in /*) ;; *) die 'Q3_CACHE_DIR must be an absolute path.' ;; esac
    local tool
    for tool in git curl unzip shasum xcode-select xcrun lipo codesign cmake ditto; do
        command -v "$tool" >/dev/null || die "Missing $tool. Install Command Line Tools (xcode-select --install) and CMake (brew install cmake)."
    done
    xcode-select -p >/dev/null || die 'Install Xcode Command Line Tools: xcode-select --install'
    xcrun --find clang >/dev/null || die 'The Apple C compiler is unavailable.'
    local jobs=${Q3_JOBS:-$(sysctl -n hw.ncpu)}
    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die 'Q3_JOBS must be a positive integer.'
    mkdir -p "$CACHE_DIR" "$INSTALL_DIR"
    [ -w "$INSTALL_DIR" ] || die "Destination is not writable: $INSTALL_DIR"
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quake3-install.XXXXXX")
    mkdir -p "$WORK_DIR/stage/baseq3"

    # Reuse an existing installation or a supplied retail file before downloading 457 MiB.
    local pak0="$CACHE_DIR/pak0.pk3" candidate
    if [ -n "${Q3_PAK0:-}" ]; then
        valid_file "$Q3_PAK0" "$PAK0_SHA256" || die 'Q3_PAK0 is not the expected retail pak0.pk3.'
        pak0=$Q3_PAK0
    else
        for candidate in "$INSTALL_DIR/baseq3/pak0.pk3" \
            "$HOME/Library/Application Support/Quake3/baseq3/pak0.pk3" \
            '/Applications/ioquake3/baseq3/pak0.pk3' \
            "$HOME/Library/Application Support/Steam/steamapps/common/Quake 3 Arena/baseq3/pak0.pk3"; do
            if valid_file "$candidate" "$PAK0_SHA256"; then pak0=$candidate; break; fi
        done
        if ! valid_file "$pak0" "$PAK0_SHA256"; then
            if ! download "$PAK0_URL" "$pak0" "$PAK0_SHA256"; then
                # Alternate GitHub download endpoint for the verified mirror.
                [ -z "${Q3_PAK0_URL:-}" ] || die 'The specified pak0 mirror failed.'
                download 'https://github.com/nrempel/q3-server/raw/refs/heads/master/baseq3/pak0.pk3' \
                    "$pak0" "$PAK0_SHA256" || die 'pak0 download failed. Set Q3_PAK0 or Q3_PAK0_URL and rerun.'
            fi
        fi
    fi
    cp "$pak0" "$WORK_DIR/stage/baseq3/pak0.pk3"
    download "$PATCH_URL" "$CACHE_DIR/quake3-latest-pk3s.zip" "$PATCH_SHA256" || die 'Patch download failed.'
    unzip -tq "$CACHE_DIR/quake3-latest-pk3s.zip" >/dev/null
    unzip -q "$CACHE_DIR/quake3-latest-pk3s.zip" -d "$WORK_DIR/patches"
    cp "$WORK_DIR/patches/quake3-latest-pk3s/baseq3/"*.pk3 "$WORK_DIR/stage/baseq3/"
    mkdir -p "$WORK_DIR/stage/missionpack"
    cp "$WORK_DIR/patches/quake3-latest-pk3s/missionpack/"*.pk3 "$WORK_DIR/stage/missionpack/"
    local index pk3
    for index in 0 1 2 3 4 5 6 7 8; do
        pk3="$WORK_DIR/stage/baseq3/pak$index.pk3"
        [ -s "$pk3" ] || die "Missing pak$index.pk3."
        unzip -tq "$pk3" >/dev/null || die "Corrupt pak$index.pk3."
    done

    log "Building ioquake3 ($IOQ3_REV), with native $native_arch support"
    git init -q "$WORK_DIR/source"
    git -C "$WORK_DIR/source" remote add origin https://github.com/ioquake/ioq3.git
    git -C "$WORK_DIR/source" fetch --depth 1 origin "$IOQ3_REV"
    git -C "$WORK_DIR/source" checkout -q --detach FETCH_HEAD
    # Upstream builds a universal arm64+x86_64 app and bundles SDL2 and renderers.
    # Retail PK3s already contain the game QVMs; loose newly built QVMs can override them.
    cmake -S "$WORK_DIR/source" -B "$WORK_DIR/build" \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_MACOS_APP=ON -DUSE_INTERNAL_LIBS=ON \
        -DBUILD_GAME_LIBRARIES=OFF -DBUILD_GAME_QVMS=OFF
    cmake --build "$WORK_DIR/build" --parallel "$jobs"
    cmake --install "$WORK_DIR/build" --prefix "$WORK_DIR/stage"
    local app="$WORK_DIR/stage/ioquake3.app"
    [ -x "$app/Contents/MacOS/ioquake3" ] || die 'Build did not produce ioquake3.app.'
    lipo -verify_arch "$native_arch" "$app/Contents/MacOS/ioquake3" || die 'Missing native CPU architecture.'
    # Sign all bundled code locally, including the QVM JIT entitlement on Apple Silicon.
    codesign --force --deep --sign - --entitlements "$WORK_DIR/source/cmake/entitlements.plist" "$app"
    codesign --verify --deep --strict "$app"

    log "Installing into $INSTALL_DIR"
    # All downloads, archives and the build have been checked before updating the installation.
    # ditto preserves unrelated mods/configs; remove only the previous app bundle, with rollback.
    local backup="$WORK_DIR/previous.app"
    if [ -e "$INSTALL_DIR/ioquake3.app" ]; then mv "$INSTALL_DIR/ioquake3.app" "$backup"; fi
    if ! ditto "$app" "$INSTALL_DIR/ioquake3.app"; then
        rm -rf "$INSTALL_DIR/ioquake3.app"
        if [ -e "$backup" ]; then mv "$backup" "$INSTALL_DIR/ioquake3.app"; fi
        die 'Could not install the app; previous app restored.'
    fi
    ditto "$WORK_DIR/stage/baseq3" "$INSTALL_DIR/baseq3"
    ditto "$WORK_DIR/stage/missionpack" "$INSTALL_DIR/missionpack"
    if [ -x "$WORK_DIR/stage/ioq3ded" ]; then cp "$WORK_DIR/stage/ioq3ded" "$INSTALL_DIR/ioq3ded"; fi
    log "Quake III Arena installed successfully. All nine baseq3 PK3 files are present."
    printf 'Launch: open "%s/ioquake3.app"\n' "$INSTALL_DIR"
}

main "$@"
