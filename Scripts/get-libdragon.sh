#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BRANCH="preview"
SDK_ROOT=""
FORCE=0
TOOLCHAIN_ONLY=0
BUILD_TOOLCHAIN=0

RELEASE_BASE="https://github.com/DragonMinded/libdragon/releases/download/toolchain-continuous-prerelease"
LIBDRAGON_GIT="https://github.com/DragonMinded/libdragon.git"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

fail() {
    printf '\n%sERREUR : %s%s\n' "$RED" "$1" "$RESET" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sdk-root)        SDK_ROOT="${2:-}"; shift 2 ;;
        --branch)          BRANCH="${2:-}"; shift 2 ;;
        --force)           FORCE=1; shift ;;
        --toolchain-only)  TOOLCHAIN_ONLY=1; shift ;;
        --build-toolchain) BUILD_TOOLCHAIN=1; shift ;;
        *)                 fail "Option inconnue : $1" ;;
    esac
done

printf '%s=== Installation de libdragon ===%s\n' "$CYAN" "$RESET"

[ -z "$SDK_ROOT" ] && SDK_ROOT="$SCRIPT_DIR/../SDK"
mkdir -p "$SDK_ROOT"
SDK_ROOT="$(cd -- "$SDK_ROOT" && pwd)"

PREFIX="$SDK_ROOT/libdragon"
SOURCES="$SDK_ROOT/libdragon-src"
CACHE="$SDK_ROOT/.cache"
mkdir -p "$CACHE"

printf 'Prefixe   : %s\n' "$PREFIX"
printf 'Sources   : %s\n' "$SOURCES"
printf 'Branche   : %s\n' "$BRANCH"

for tool in curl tar make; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool est necessaire (paquet build-essential / xcode-select --install)."
done

HAS_GIT=0
command -v git >/dev/null 2>&1 && HAS_GIT=1

printf '\n%s--- toolchain mips64-elf ---%s\n' "$CYAN" "$RESET"

case "$(uname -m)" in
    x86_64|amd64) DEB="gcc-toolchain-mips64-x86_64.deb" ;;
    arm64|aarch64) DEB="gcc-toolchain-mips64-aarch64.deb" ;;
    *) DEB="" ;;
esac

if [ -x "$PREFIX/bin/mips64-elf-gcc" ] && [ "$FORCE" -eq 0 ]; then
    printf '%s  deja presente : %s%s\n' "$GREEN" "$PREFIX" "$RESET"
elif [ "$(uname -s)" = "Linux" ] && [ -n "$DEB" ] && [ "$BUILD_TOOLCHAIN" -eq 0 ]; then
    archive="$CACHE/$DEB"
    if [ ! -f "$archive" ] || [ "$FORCE" -eq 1 ]; then
        printf '  telechargement (~94 Mo)\n'
        curl -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            --progress-bar -o "$archive" "$RELEASE_BASE/$DEB" || fail "Telechargement de la toolchain echoue."
    else
        printf '  archive deja en cache\n'
    fi

    printf '  extraction vers %s\n' "$PREFIX"
    staging="$(mktemp -d "$CACHE/deb.XXXXXX")"
    trap 'rm -rf "$staging"' EXIT

    (cd "$staging" && ar x "$archive" 2>/dev/null) || fail "ar est necessaire pour ouvrir le .deb (paquet binutils)."
    data="$(find "$staging" -maxdepth 1 -name 'data.tar.*' | head -n 1)"
    [ -n "$data" ] || fail "data.tar introuvable dans $DEB"
    mkdir -p "$staging/payload"
    tar -xf "$data" -C "$staging/payload"
    [ -d "$staging/payload/opt/libdragon" ] || fail "Arborescence inattendue dans $DEB"
    mkdir -p "$PREFIX"
    cp -a "$staging/payload/opt/libdragon/." "$PREFIX/"
    rm -rf "$staging"
    trap - EXIT
    [ -x "$PREFIX/bin/mips64-elf-gcc" ] || fail "mips64-elf-gcc est absent apres extraction."
    printf '%s  installee%s\n' "$GREEN" "$RESET"
else
    if [ "$BUILD_TOOLCHAIN" -eq 0 ]; then
        fail "Aucune toolchain precompilee pour $(uname -s)/$(uname -m).
Relance avec --build-toolchain pour la compiler depuis les sources (tres long),
ou compile le menu dans un conteneur : ./build-n64cart-manager.sh --backend docker"
    fi
    printf '%s  compilation de la toolchain depuis les sources (compter ~1 h)%s\n' "$YELLOW" "$RESET"
    [ -d "$SOURCES" ] || git clone --depth 1 --branch "$BRANCH" "$LIBDRAGON_GIT" "$SOURCES"
    (cd "$SOURCES/tools" && N64_INST="$PREFIX" ./build-toolchain.sh) || fail "La compilation de la toolchain a echoue."
fi

printf '\n%s--- sources libdragon (%s) ---%s\n' "$CYAN" "$BRANCH" "$RESET"

if [ -f "$SOURCES/Makefile" ] && [ "$FORCE" -eq 0 ]; then
    printf '  deja presentes\n'
    if [ "$HAS_GIT" -eq 1 ] && [ -d "$SOURCES/.git" ]; then
        git -C "$SOURCES" fetch --depth 1 origin "$BRANCH" && git -C "$SOURCES" checkout -q FETCH_HEAD
    fi
elif [ "$HAS_GIT" -eq 1 ]; then
    rm -rf "$SOURCES"
    git clone --depth 1 --branch "$BRANCH" "$LIBDRAGON_GIT" "$SOURCES" \
        || fail "Le clone de libdragon a echoue (branche $BRANCH)."
else
    printf '  git absent : telechargement de l archive de la branche\n'
    archive="$CACHE/libdragon-$BRANCH.tar.gz"
    curl -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        --progress-bar -o "$archive" \
        "https://codeload.github.com/DragonMinded/libdragon/tar.gz/refs/heads/$BRANCH" \
        || fail "Telechargement des sources de libdragon echoue (branche $BRANCH)."

    staging="$CACHE/libdragon-src-tmp"
    rm -rf "$staging"
    mkdir -p "$staging"
    tar -xzf "$archive" -C "$staging" || fail "Extraction des sources de libdragon echouee."
    extracted="$(find "$staging" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$extracted" ] || fail "Archive de sources inattendue."
    rm -rf "$SOURCES"
    mv "$extracted" "$SOURCES"
    rm -rf "$staging" "$archive"
fi
printf '%s  sources pretes%s\n' "$GREEN" "$RESET"

if [ "$TOOLCHAIN_ONLY" -eq 1 ]; then
    printf '\n%s--toolchain-only demande : compilation de libdragon ignoree.%s\n' "$YELLOW" "$RESET"
    exit 0
fi

printf '\n%s--- compilation de libdragon ---%s\n' "$CYAN" "$RESET"

if [ -f "$PREFIX/mips64-elf/lib/libdragon.a" ] && [ -x "$PREFIX/bin/n64sym" ] && [ "$FORCE" -eq 0 ]; then
    printf '%s  deja compilee%s\n' "$GREEN" "$RESET"
else
    (cd "$SOURCES" && N64_INST="$PREFIX" PATH="$PREFIX/bin:$PATH" ./build.sh --no-examples) \
        || fail "La compilation de libdragon a echoue."
    [ -f "$PREFIX/mips64-elf/lib/libdragon.a" ] || fail "libdragon.a est absente apres compilation."
    [ -x "$PREFIX/bin/n64sym" ] || fail "Les outils hote de libdragon n ont pas ete installes dans $PREFIX/bin."
fi

printf '\n%s=================== Recapitulatif ===================%s\n' "$CYAN" "$RESET"
printf '%s%-12s %s%s\n' "$GREEN" "toolchain" "$PREFIX/bin" "$RESET"
printf '%s%-12s %s%s\n' "$GREEN" "libdragon" "$PREFIX/mips64-elf/lib/libdragon.a" "$RESET"
printf '\n%sN64_INST  : %s%s\n' "$GREEN" "$PREFIX" "$RESET"
printf 'build-n64cart-manager.sh l utilisera automatiquement.\n'
