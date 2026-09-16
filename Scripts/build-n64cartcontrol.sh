#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ROOT=""
OUTPUT_DIR=""
TARGETS=()
CLEAN=0
NATIVE_ONLY=0

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

fail() {
    printf '\n%sERREUR : %s%s\n' "$RED" "$1" "$RESET" >&2
    exit 1
}

step() {
    printf '\n%s--- %s ---%s\n' "$CYAN" "$1" "$RESET"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --output)       OUTPUT_DIR="${2:-}"; shift 2 ;;
        --target)       TARGETS+=("${2:-}"); shift 2 ;;
        --clean)        CLEAN=1; shift ;;
        --native-only)  NATIVE_ONLY=1; shift ;;
        *)              fail "Option inconnue : $1" ;;
    esac
done

case "$(uname -s)" in
    Linux)  PLATFORM="linux"; PLATFORM_FLAG="--linux"; DEFAULT_TARGETS=(AppImage deb) ;;
    Darwin) PLATFORM="mac";   PLATFORM_FLAG="--mac";   DEFAULT_TARGETS=(dmg zip) ;;
    *)      fail "Plateforme non geree : $(uname -s). Utilise build-n64cartcontrol.ps1 sous Windows." ;;
esac

if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("${DEFAULT_TARGETS[@]}")
fi

printf '%s=== Compilation N64CartControl (%s, cibles %s) ===%s\n' \
    "$CYAN" "$PLATFORM" "${TARGETS[*]}" "$RESET"

is_project_dir() {
    [ -f "$1/binding.gyp" ] && [ -f "$1/package.json" ]
}

if [ -n "$PROJECT_ROOT" ]; then
    [ -d "$PROJECT_ROOT" ] || fail "ProjectRoot introuvable : $PROJECT_ROOT"
else
    for candidate in "$SCRIPT_DIR/../N64CartControl" "$SCRIPT_DIR/N64CartControl" "$SCRIPT_DIR/.."; do
        if is_project_dir "$candidate"; then
            PROJECT_ROOT="$candidate"
            break
        fi
    done
fi

if [ -z "$PROJECT_ROOT" ] || ! is_project_dir "$PROJECT_ROOT"; then
    fail "Projet N64CartControl introuvable (dossier contenant package.json et binding.gyp).
Utilise --project-root <chemin> pour le designer explicitement."
fi
PROJECT_ROOT="$(cd -- "$PROJECT_ROOT" && pwd)"

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$SCRIPT_DIR/../Output"
fi
mkdir -p "$OUTPUT_DIR"

APP_OUT="$(cd -- "$OUTPUT_DIR" && pwd)/app"

printf 'Script    : %s\n' "$SCRIPT_DIR"
printf 'Projet    : %s\n' "$PROJECT_ROOT"
printf 'Sortie    : %s\n' "$APP_OUT"

for tool in node npm; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool est absent du PATH. Installe Node.js 22 ou plus recent."
done

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || fail "Node.js 22 minimum est requis (version detectee : $NODE_MAJOR).
node-gyp 13, qui compile le module natif, exige Node ^22.22.2, ^24.15.0 ou >=26 ;
en dessous il echoue sur \"ReferenceError: File is not defined\".
  nvm    : nvm install 22 && nvm use 22
  Debian : curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"

command -v python3 >/dev/null 2>&1 || printf '%sNote      : python3 absent du PATH, node-gyp risque d echouer.%s\n' "$YELLOW" "$RESET"

if ! command -v pkg-config >/dev/null 2>&1; then
    fail "pkg-config est absent : le module natif ne peut pas localiser libusb.
  Debian/Ubuntu : sudo apt install pkg-config libusb-1.0-0-dev build-essential
  Fedora        : sudo dnf install pkgconf-pkg-config libusbx-devel gcc-c++
  Arch          : sudo pacman -S pkgconf libusb base-devel
  macOS         : brew install pkg-config libusb"
fi

if ! pkg-config --exists libusb-1.0; then
    fail "libusb-1.0 et ses en-tetes sont introuvables.
  Debian/Ubuntu : sudo apt install libusb-1.0-0-dev
  Fedora        : sudo dnf install libusbx-devel
  Arch          : sudo pacman -S libusb
  macOS         : brew install libusb
Le module natif compile libusb lui-meme sous Windows, mais s appuie sur celle du
systeme sous Linux et macOS."
fi

printf 'Node      : %s\n' "$(node -v)"
printf 'npm       : %s\n' "$(npm -v)"
printf 'libusb    : %s\n' "$(pkg-config --modversion libusb-1.0)"

cd "$PROJECT_ROOT"

if [ ! -d node_modules ]; then
    step "npm install"
    npm install --ignore-scripts
else
    printf '\nnode_modules deja present, installation ignoree.\n'
fi

if [ "$CLEAN" -eq 1 ]; then
    step "node-gyp clean"
    npx node-gyp clean
fi

step "module natif (node-gyp)"
npx node-gyp rebuild

ADDON="$PROJECT_ROOT/build/Release/n64cart.node"
[ -f "$ADDON" ] || fail "n64cart.node n a pas ete produit."
printf '%sModule natif : %s%s\n' "$GREEN" "$ADDON" "$RESET"

if [ "$NATIVE_ONLY" -eq 1 ]; then
    printf '\n%s--native-only demande, empaquetage ignore.%s\n' "$GREEN" "$RESET"
    exit 0
fi

step "empaquetage (electron-builder)"
npx electron-builder "$PLATFORM_FLAG" "${TARGETS[@]}" --config.directories.output="$APP_OUT"

printf '\n%s=================== Recapitulatif ===================%s\n' "$CYAN" "$RESET"

found=0
while IFS= read -r artifact; do
    found=1
    size="$(du -h "$artifact" | cut -f1)"
    printf '%s%-52s %8s%s\n' "$GREEN" "$(basename "$artifact")" "$size" "$RESET"
done < <(find "$APP_OUT" -maxdepth 1 -type f \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' -o -name '*.dmg' -o -name '*.zip' \) | sort)

[ "$found" -eq 1 ] || fail "Aucun paquet produit dans $APP_OUT."

printf '\n%sFichiers dans : %s%s\n' "$GREEN" "$APP_OUT" "$RESET"
if [ "$PLATFORM" = "linux" ]; then
    printf 'Rappel        : pour acceder a la cartouche sans root, ajoute une regle udev :\n'
    printf '  echo '"'"'SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="6800", MODE="0666"'"'"' \\\n'
    printf '    | sudo tee /etc/udev/rules.d/99-n64cart.rules && sudo udevadm control --reload\n'
fi
