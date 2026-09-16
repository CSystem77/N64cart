#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SDK_VERSION="2.3.1"
TOOLCHAIN_VERSION="15_2_Rel1"
CMAKE_VERSION="v4.3.4"
NINJA_VERSION="v1.13.2"
PICOTOOL_VERSION="2.3.1"
TOOLS_TAG="v2.3.1-0"

SDK_ROOT=""
CACHE_DIR=""
COMPONENTS=()
FORCE=0
INCLUDE_OPENOCD=0
KEEP_ARCHIVES=0

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

fail() {
    printf '\n%sERREUR : %s%s\n' "$RED" "$1" "$RESET" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sdk-root)       SDK_ROOT="${2:-}"; shift 2 ;;
        --cache-dir)      CACHE_DIR="${2:-}"; shift 2 ;;
        --component)      COMPONENTS+=("${2:-}"); shift 2 ;;
        --force)          FORCE=1; shift ;;
        --include-openocd) INCLUDE_OPENOCD=1; shift ;;
        --keep-archives)  KEEP_ARCHIVES=1; shift ;;
        *)                fail "Option inconnue : $1" ;;
    esac
done

case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    *)      fail "Plateforme non geree : $(uname -s). Utilise get-pico-sdk.ps1 sous Windows." ;;
esac

case "$(uname -m)" in
    x86_64|amd64) ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) fail "Architecture non geree : $(uname -m)" ;;
esac

ARM_BASE="https://armkeil.blob.core.windows.net/developer"
TOOLS_BASE="https://github.com/raspberrypi/pico-sdk-tools/releases/download/$TOOLS_TAG"

case "${OS}_${ARCH}" in
    linux_x64)
        TOOLCHAIN_URL="$ARM_BASE/files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-eabi.tar.xz"
        CMAKE_URL="https://github.com/Kitware/CMake/releases/download/$CMAKE_VERSION/cmake-4.3.4-linux-x86_64.tar.gz"
        NINJA_URL="https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-linux.zip"
        PICOTOOL_URL="$TOOLS_BASE/picotool-$PICOTOOL_VERSION-x86_64-lin.tar.gz"
        SDKTOOLS_URL="$TOOLS_BASE/pico-sdk-tools-$SDK_VERSION-x86_64-lin.tar.gz"
        OPENOCD_URL="$TOOLS_BASE/openocd-0.12.0%2Bdev-x86_64-lin.tar.gz"
        CMAKE_PROBE="bin/cmake"
        ;;
    linux_arm64)
        TOOLCHAIN_URL="$ARM_BASE/files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-aarch64-arm-none-eabi.tar.xz"
        CMAKE_URL="https://github.com/Kitware/CMake/releases/download/$CMAKE_VERSION/cmake-4.3.4-linux-aarch64.tar.gz"
        NINJA_URL="https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-linux-aarch64.zip"
        PICOTOOL_URL="$TOOLS_BASE/picotool-$PICOTOOL_VERSION-aarch64-lin.tar.gz"
        SDKTOOLS_URL="$TOOLS_BASE/pico-sdk-tools-$SDK_VERSION-aarch64-lin.tar.gz"
        OPENOCD_URL="$TOOLS_BASE/openocd-0.12.0%2Bdev-aarch64-lin.tar.gz"
        CMAKE_PROBE="bin/cmake"
        ;;
    darwin_arm64)
        TOOLCHAIN_URL="$ARM_BASE/files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-darwin-arm64-arm-none-eabi.tar.xz"
        CMAKE_URL="https://github.com/Kitware/CMake/releases/download/$CMAKE_VERSION/cmake-4.3.4-macos-universal.tar.gz"
        NINJA_URL="https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-mac.zip"
        PICOTOOL_URL="$TOOLS_BASE/picotool-$PICOTOOL_VERSION-mac.zip"
        SDKTOOLS_URL="$TOOLS_BASE/pico-sdk-tools-$SDK_VERSION-mac.zip"
        OPENOCD_URL="$TOOLS_BASE/openocd-0.12.0%2Bdev-mac.zip"
        CMAKE_PROBE="CMake.app/Contents/bin/cmake"
        ;;
    darwin_x64)

        TOOLCHAIN_VERSION="13_2_Rel1"
        TOOLCHAIN_URL="$ARM_BASE/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-darwin-x86_64-arm-none-eabi.tar.xz"
        CMAKE_URL="https://github.com/Kitware/CMake/releases/download/$CMAKE_VERSION/cmake-4.3.4-macos-universal.tar.gz"
        NINJA_URL="https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-mac.zip"
        PICOTOOL_URL="$TOOLS_BASE/picotool-$PICOTOOL_VERSION-mac.zip"
        SDKTOOLS_URL="$TOOLS_BASE/pico-sdk-tools-$SDK_VERSION-mac.zip"
        OPENOCD_URL="$TOOLS_BASE/openocd-0.12.0%2Bdev-mac.zip"
        CMAKE_PROBE="CMake.app/Contents/bin/cmake"
        ;;
esac

SDK_GIT="https://github.com/raspberrypi/pico-sdk.git"

CATALOG=(
    "sdk|sdk/$SDK_VERSION|https://github.com/raspberrypi/pico-sdk/releases/download/$SDK_VERSION/pico-sdk-$SDK_VERSION.tar.gz|1|src/rp2_common/pico_stdlib/CMakeLists.txt|SDK Pico $SDK_VERSION"
    "toolchain|toolchain/$TOOLCHAIN_VERSION|$TOOLCHAIN_URL|1|bin/arm-none-eabi-gcc|chaine Arm GNU"
    "cmake|cmake/$CMAKE_VERSION|$CMAKE_URL|1|$CMAKE_PROBE|CMake 4.3.4"
    "ninja|ninja/$NINJA_VERSION|$NINJA_URL|0|ninja|Ninja 1.13.2"
    "picotool|picotool/$PICOTOOL_VERSION|$PICOTOOL_URL|0|picotool|picotool $PICOTOOL_VERSION"
    "tools|tools/$SDK_VERSION|$SDKTOOLS_URL|0|pioasm|outils du SDK (pioasm)"
)

if [ "$INCLUDE_OPENOCD" -eq 1 ]; then
    CATALOG+=("openocd|openocd/0.12.0+dev|$OPENOCD_URL|0|openocd|openocd 0.12.0+dev")
fi

if [ -z "$SDK_ROOT" ]; then
    SDK_ROOT="$SCRIPT_DIR/../SDK"
fi
mkdir -p "$SDK_ROOT"
SDK_ROOT="$(cd -- "$SDK_ROOT" && pwd)"

if [ -z "$CACHE_DIR" ]; then
    CACHE_DIR="$SDK_ROOT/.cache"
fi
mkdir -p "$CACHE_DIR"
CACHE_DIR="$(cd -- "$CACHE_DIR" && pwd)"

printf '%s=== Telechargement du SDK Pico (%s %s) ===%s\n' "$CYAN" "$OS" "$ARCH" "$RESET"
printf 'Destination : %s\n' "$SDK_ROOT"
printf 'Cache       : %s\n' "$CACHE_DIR"

if command -v curl >/dev/null 2>&1; then
    DL=curl
elif command -v wget >/dev/null 2>&1; then
    DL=wget
else
    fail "curl ou wget est necessaire pour telecharger le SDK."
fi

command -v tar >/dev/null 2>&1 || fail "tar est necessaire."
command -v unzip >/dev/null 2>&1 || fail "unzip est necessaire (paquet unzip)."

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ] && [ "$FORCE" -eq 0 ]; then
        printf '  archive deja en cache : %s\n' "$(basename "$dest")"
        return
    fi
    printf '  telechargement de %s\n' "$url"
    if [ "$DL" = curl ]; then
        curl -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            --progress-bar -o "$dest" "$url" || fail "Telechargement echoue ($url)"
    else
        wget -q --show-progress -O "$dest" "$url" || fail "Telechargement echoue ($url)"
    fi
}

extract() {
    local archive="$1" target="$2" strip="$3"
    local staging
    staging="$(mktemp -d "$CACHE_DIR/stage.XXXXXX")"

    trap "rm -rf '$staging'" RETURN

    case "$archive" in
        *.zip)              unzip -q "$archive" -d "$staging" ;;
        *.tar.gz|*.tgz)     tar -xzf "$archive" -C "$staging" ;;
        *.tar.xz)           tar -xJf "$archive" -C "$staging" ;;
        *)                  fail "Format d archive inconnu : $archive" ;;
    esac

    local source="$staging" i children
    for ((i = 0; i < strip; i++)); do
        mapfile -t children < <(find "$source" -mindepth 1 -maxdepth 1)
        if [ "${#children[@]}" -ne 1 ] || [ ! -d "${children[0]}" ]; then
            fail "Archive inattendue (pas un dossier unique a la racine) : $archive"
        fi
        source="${children[0]}"
    done

    rm -rf "$target"
    mkdir -p "$(dirname "$target")"
    mv "$source" "$target"
}

INSTALLED=()

for entry in "${CATALOG[@]}"; do
    IFS='|' read -r name dir url strip probe label <<< "$entry"

    if [ "${#COMPONENTS[@]}" -gt 0 ]; then
        skip=1
        for wanted in "${COMPONENTS[@]}"; do
            [ "$wanted" = "$name" ] && skip=0
        done
        [ "$skip" -eq 0 ] || continue
    fi

    target="$SDK_ROOT/$dir"

    printf '\n%s--- %s ---%s\n' "$CYAN" "$label" "$RESET"

    if [ -e "$target/$probe" ] && [ "$FORCE" -eq 0 ]; then
        printf '%s  deja installe : %s%s\n' "$GREEN" "$target" "$RESET"
        INSTALLED+=("$name|$target")
        continue
    fi

    if [ "$name" = "sdk" ] && command -v git >/dev/null 2>&1; then
        printf '  clone de %s (branche %s, sous-modules inclus)\n' "$SDK_GIT" "$SDK_VERSION"

        rm -rf "$target.tmp" "$target"
        mkdir -p "$(dirname "$target")"
        if ! git clone --depth 1 --branch "$SDK_VERSION" --recurse-submodules --shallow-submodules \
            "$SDK_GIT" "$target"; then
            rm -rf "$target"
            fail "Le clone du SDK a echoue (relance le script pour reprendre)."
        fi
    else
        if [ "$name" = "sdk" ]; then
            printf '%s  git absent : archive de release utilisee, les sous-modules (tinyusb, lwip...) resteront vides.%s\n' \
                "$YELLOW" "$RESET"
        fi
        archive="$CACHE_DIR/$(basename "${url%%\?*}")"
        download "$url" "$archive"
        printf '  extraction vers %s\n' "$target"
        extract "$archive" "$target" "$strip"
        [ "$KEEP_ARCHIVES" -eq 1 ] || rm -f "$archive"
    fi

    [ -e "$target/$probe" ] || fail "$label : $probe est absent apres installation."
    printf '%s  installe%s\n' "$GREEN" "$RESET"
    INSTALLED+=("$name|$target")
done

[ "$KEEP_ARCHIVES" -eq 1 ] || rm -rf "$CACHE_DIR"

printf '\n%s=================== Recapitulatif ===================%s\n' "$CYAN" "$RESET"
for entry in "${INSTALLED[@]}"; do
    IFS='|' read -r name target <<< "$entry"
    printf '%s%-10s %s%s\n' "$GREEN" "$name" "$target" "$RESET"
done

printf '\n%sSDK pret dans : %s%s\n' "$GREEN" "$SDK_ROOT" "$RESET"
printf 'build-n64cart.sh l utilisera automatiquement.\n'
