#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BOARD="v3"
REGION="both"
PROJECT_ROOT=""
OUTPUT_DIR=""
SDK_ROOT=""
NO_DOWNLOAD=0
CLEAN=0

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

fail() {
    printf '\n%sERREUR : %s%s\n' "$RED" "$1" "$RESET" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board)        BOARD="${2:-}"; shift 2 ;;
        --region)       REGION="${2:-}"; shift 2 ;;
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --output)       OUTPUT_DIR="${2:-}"; shift 2 ;;
        --sdk-root)     SDK_ROOT="${2:-}"; shift 2 ;;
        --no-download)  NO_DOWNLOAD=1; shift ;;
        --clean)        CLEAN=1; shift ;;
        *)              fail "Option inconnue : $1" ;;
    esac
done

case "$BOARD" in
    v3|v2|pico|pico-lite) ;;
    *) fail "Carte inconnue : $BOARD (v3, v2, pico, pico-lite)" ;;
esac

case "$REGION" in
    pal|ntsc) REGIONS=("$REGION") ;;
    both)     REGIONS=(pal ntsc) ;;
    *)        fail "Region inconnue : $REGION (pal, ntsc, both)" ;;
esac

printf '%s=== Compilation firmware n64cart (carte %s, region %s) ===%s\n' "$CYAN" "$BOARD" "$REGION" "$RESET"

is_project_dir() {
    [ -f "$1/fw/CMakeLists.txt" ]
}

find_project_root() {
    local dir="$1" chain=() i sub
    for ((i = 0; i < 5; i++)); do
        chain+=("$dir")
        [ "$dir" = "/" ] && break
        dir="$(dirname -- "$dir")"
    done

    for dir in "${chain[@]}"; do
        if is_project_dir "$dir"; then
            printf '%s\n' "$(cd -- "$dir" && pwd)"
            return 0
        fi
    done

    for dir in "${chain[@]}"; do
        for sub in "$dir"/*/; do
            [ -d "$sub" ] || continue
            if is_project_dir "$sub"; then
                printf '%s\n' "$(cd -- "$sub" && pwd)"
            fi
        done
    done
}

if [ -n "$PROJECT_ROOT" ]; then
    [ -d "$PROJECT_ROOT" ] || fail "ProjectRoot introuvable : $PROJECT_ROOT"
    if ! is_project_dir "$PROJECT_ROOT"; then
        PROJECT_ROOT="$(find_project_root "$(cd -- "$PROJECT_ROOT" && pwd)" | head -n 1)"
    fi
else
    mapfile -t FOUND < <(find_project_root "$SCRIPT_DIR")
    if [ "${#FOUND[@]}" -gt 1 ]; then
        printf '\n%sPlusieurs projets n64cart trouves :%s\n' "$YELLOW" "$RESET"
        printf '  %s\n' "${FOUND[@]}"
        fail "Precise lequel utiliser avec --project-root <chemin>."
    fi
    PROJECT_ROOT="${FOUND[0]:-}"
fi

[ -n "$PROJECT_ROOT" ] && is_project_dir "$PROJECT_ROOT" || fail "Racine du projet introuvable (dossier contenant fw/CMakeLists.txt).
Utilise --project-root <chemin> pour la designer explicitement."

FW="$PROJECT_ROOT/fw"
case "$FW" in
    *" "*) fail "Le chemin contient un espace :
  $FW
Le SDK Pico echoue de facon obscure dans ce cas. Deplace le projet vers un
chemin sans espace, puis relance le script." ;;
esac

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$SCRIPT_DIR/../Output"
fi
mkdir -p "$OUTPUT_DIR/fw"

OUT_DIR="$(cd -- "$OUTPUT_DIR/fw" && pwd)"

printf 'Script    : %s\n' "$SCRIPT_DIR"
printf 'Racine    : %s\n' "$PROJECT_ROOT"
printf 'Firmware  : %s\n' "$FW"
printf 'Sortie    : %s\n' "$OUT_DIR"

command -v git >/dev/null 2>&1 || \
    printf '%sNote      : git absent du PATH, le hash de version sera vide (sans gravite).%s\n' "$YELLOW" "$RESET"

latest_dir() {

    local base="$1"
    [ -d "$base" ] || return 1
    local newest
    newest="$(find "$base" -mindepth 1 -maxdepth 1 -type d | sort -rV | head -n 1)"
    [ -n "$newest" ] || return 1
    printf '%s\n' "$newest"
}

has_pico_layout() {
    [ -n "${1:-}" ] && [ -d "$1/sdk" ]
}

DEFAULT_SDK_ROOT="$SCRIPT_DIR/../SDK"
PICO_ROOT=""

if [ -n "$SDK_ROOT" ]; then
    has_pico_layout "$SDK_ROOT" || fail "Aucun SDK Pico sous $SDK_ROOT (sous-dossier sdk/ attendu)."
    PICO_ROOT="$SDK_ROOT"
else
    for candidate in "$DEFAULT_SDK_ROOT" "$HOME/.pico-sdk"; do
        if has_pico_layout "$candidate"; then
            PICO_ROOT="$candidate"
            break
        fi
    done
fi

if [ -z "$PICO_ROOT" ] && [ -n "${PICO_SDK_PATH:-}" ] && [ -f "${PICO_SDK_PATH}/pico_sdk_init.cmake" ]; then

    SDK_DIR="$PICO_SDK_PATH"
    SDK_SOURCE="PICO_SDK_PATH"
else
    if [ -z "$PICO_ROOT" ]; then
        [ "$NO_DOWNLOAD" -eq 0 ] || fail "SDK Pico introuvable ($DEFAULT_SDK_ROOT, ~/.pico-sdk).
Relance sans --no-download, lance get-pico-sdk.sh, ou passe --sdk-root <chemin>."

        GETTER="$SCRIPT_DIR/get-pico-sdk.sh"
        [ -f "$GETTER" ] || fail "SDK Pico introuvable et get-pico-sdk.sh est absent de $SCRIPT_DIR."

        printf '\n%sSDK Pico introuvable, telechargement dans %s%s\n' "$YELLOW" "$DEFAULT_SDK_ROOT" "$RESET"
        bash "$GETTER" --sdk-root "$DEFAULT_SDK_ROOT" || fail "Le telechargement du SDK a echoue."
        has_pico_layout "$DEFAULT_SDK_ROOT" || fail "Le SDK est toujours absent apres telechargement."
        PICO_ROOT="$DEFAULT_SDK_ROOT"
    fi

    PICO_ROOT="$(cd -- "$PICO_ROOT" && pwd)"
    SDK_SOURCE="$PICO_ROOT"

    SDK_DIR="$(latest_dir "$PICO_ROOT/sdk")" || fail "Aucun SDK sous $PICO_ROOT/sdk (lance get-pico-sdk.sh)."
    TOOLCHAIN_DIR="$(latest_dir "$PICO_ROOT/toolchain" 2>/dev/null || true)"
    CMAKE_DIR="$(latest_dir "$PICO_ROOT/cmake" 2>/dev/null || true)"
    NINJA_DIR="$(latest_dir "$PICO_ROOT/ninja" 2>/dev/null || true)"
    PICOTOOL_DIR="$(latest_dir "$PICO_ROOT/picotool" 2>/dev/null || true)"
    TOOLS_DIR="$(latest_dir "$PICO_ROOT/tools" 2>/dev/null || true)"

    [ -n "$TOOLCHAIN_DIR" ] && PATH="$TOOLCHAIN_DIR/bin:$PATH"
    if [ -n "$CMAKE_DIR" ]; then

        if [ -d "$CMAKE_DIR/CMake.app/Contents/bin" ]; then
            PATH="$CMAKE_DIR/CMake.app/Contents/bin:$PATH"
        else
            PATH="$CMAKE_DIR/bin:$PATH"
        fi
    fi
    [ -n "$NINJA_DIR" ] && PATH="$NINJA_DIR:$PATH"
    export PATH
fi

export PICO_SDK_PATH="$SDK_DIR"
[ -n "${TOOLCHAIN_DIR:-}" ] && export PICO_TOOLCHAIN_PATH="$TOOLCHAIN_DIR"

for tool in cmake ninja arm-none-eabi-gcc; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool est absent du PATH.
Lance ./get-pico-sdk.sh pour installer cmake, ninja et la chaine Arm dans SDK/,
ou installe-les : sudo apt install cmake ninja-build gcc-arm-none-eabi libnewlib-arm-none-eabi"
done

printf 'SDK Pico  : %s\n' "$SDK_SOURCE"
printf 'SDK       : %s\n' "$PICO_SDK_PATH"
printf 'CMake     : %s\n' "$(cmake --version | head -n 1)"
printf 'Toolchain : %s\n' "$(arm-none-eabi-gcc -dumpversion)"

CMAKE_LISTS="$FW/CMakeLists.txt"
MARKER="# --- toolchain pico, ajoute par build-n64cart ---"

BLOCK="$MARKER
set(PICO_SDK_PATH \"$PICO_SDK_PATH\")"
if [ -n "${TOOLCHAIN_DIR:-}" ]; then
    BLOCK="$BLOCK
set(PICO_TOOLCHAIN_PATH \"$TOOLCHAIN_DIR\")"
fi
if [ -n "${PICOTOOL_DIR:-}" ] && [ -f "$PICOTOOL_DIR/picotool/picotoolConfig.cmake" ]; then
    BLOCK="$BLOCK
set(picotool_DIR \"$PICOTOOL_DIR/picotool\")"
fi
if [ -n "${TOOLS_DIR:-}" ] && [ -f "$TOOLS_DIR/pioasm/pioasmConfig.cmake" ]; then
    BLOCK="$BLOCK
set(pioasm_DIR \"$TOOLS_DIR/pioasm\")"
fi
BLOCK="$BLOCK
# --- fin ---"

python_rewrite() {
    MARKER_BLOCK="$BLOCK" python3 - "$CMAKE_LISTS" <<'PYEOF'
import os, sys

path = sys.argv[1]
block = os.environ["MARKER_BLOCK"].splitlines()

with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

cleaned, in_block = [], False
for line in lines:
    if not in_block and line.startswith("# --- toolchain pico"):
        in_block = True
        continue
    if in_block:
        if line.startswith("# --- fin ---"):
            in_block = False
        continue
    cleaned.append(line)

if in_block:
    sys.exit("bloc toolchain non termine")

anchor = next((i for i, l in enumerate(cleaned) if "cmake_minimum_required" in l), None)
if anchor is None:
    sys.exit("cmake_minimum_required introuvable")

out = cleaned[: anchor + 1] + block + cleaned[anchor + 1 :]
if out == lines:
    print("unchanged")
else:
    if not os.path.exists(path + ".bak"):
        with open(path + ".bak", "w", encoding="utf-8", newline="\n") as backup:
            backup.write("\n".join(lines) + "\n")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out) + "\n")
    print("updated")
PYEOF
}

command -v python3 >/dev/null 2>&1 || fail "python3 est necessaire pour configurer $CMAKE_LISTS."
case "$(python_rewrite)" in
    unchanged) printf 'CMakeLists: deja configure pour ce SDK\n' ;;
    updated)   printf '%sCMakeLists: pointe sur %s%s\n' "$GREEN" "$SDK_SOURCE" "$RESET" ;;
    *)         fail "Impossible de configurer $CMAKE_LISTS." ;;
esac

file_size() {

    stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

RESULT_LINES=()
INCOMPATIBLE=0

for reg in "${REGIONS[@]}"; do
    printf '\n%s=================== %s / %s ===================%s\n' \
        "$CYAN" "$BOARD" "$(printf '%s' "$reg" | tr '[:lower:]' '[:upper:]')" "$RESET"

    BUILD="$FW/build-$BOARD-$reg"
    if [ "$CLEAN" -eq 1 ] && [ -d "$BUILD" ]; then
        printf 'Nettoyage de %s\n' "$BUILD"
        rm -rf "$BUILD"
    fi
    mkdir -p "$BUILD"

    printf '\n%s--- cmake ---%s\n' "$CYAN" "$RESET"
    (cd "$BUILD" && cmake -G Ninja -DBOARD="$BOARD" -DREGION="$reg" ..) || fail "cmake a echoue pour $reg"

    printf '\n%s--- ninja ---%s\n' "$CYAN" "$RESET"
    (cd "$BUILD" && ninja) || fail "ninja a echoue pour $reg"

    BIN="$BUILD/n64cart.bin"
    UF2="$BUILD/n64cart.uf2"
    [ -f "$UF2" ] || fail "n64cart.uf2 n a pas ete produit pour $reg."

    SIZE="$(file_size "$BIN")"
    ALIGN=32768
    ROMFS_START=$(( ((SIZE + ALIGN - 1) / ALIGN) * ALIGN ))

    FINAL="$OUT_DIR/n64cart-$BOARD-$reg.uf2"
    cp -f "$UF2" "$FINAL"

    if [ "$ROMFS_START" -eq 65536 ]; then
        STATE="compatible"
    else
        STATE="INCOMPATIBLE"
        INCOMPATIBLE=1
    fi
    RESULT_LINES+=("$(printf '%-5s %7s o   ROMFS 0x%08X   %-24s %s' \
        "$(printf '%s' "$reg" | tr '[:lower:]' '[:upper:]')" "$SIZE" "$ROMFS_START" "$(basename "$FINAL")" "$STATE")")
done

printf '\n%s=================== Recapitulatif ===================%s\n' "$CYAN" "$RESET"
for line in "${RESULT_LINES[@]}"; do
    case "$line" in
        *INCOMPATIBLE) printf '%s%s%s\n' "$YELLOW" "$line" "$RESET" ;;
        *)             printf '%s%s%s\n' "$GREEN" "$line" "$RESET" ;;
    esac
done

if [ "$INCOMPATIBLE" -eq 1 ]; then
    printf '\n%sATTENTION : un binaire depasse 64 Ko, le ROMFS ne demarrerait plus a\n' "$YELLOW"
    printf '0x00010000. Flasher ce firmware rendrait le catalogue illisible et imposerait\n'
    printf 'un format suivi d un rechargement complet des ROMs.%s\n' "$RESET"
fi

printf '\n%sFichiers dans : %s%s\n' "$GREEN" "$OUT_DIR" "$RESET"
printf 'Flashage      : ROM FS Manager -> File -> Bootloader, puis glisser sur RPI-RP2.\n'
