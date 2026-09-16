#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BOARD="v3"
BACKEND="auto"
PROJECT_ROOT=""
OUTPUT_DIR=""
IMAGE="ghcr.io/dragonminded/libdragon:latest"
CLEAN=0

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

fail() {
    printf '\n%sERREUR : %s%s\n' "$RED" "$1" "$RESET" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board)        BOARD="${2:-}"; shift 2 ;;
        --backend)      BACKEND="${2:-}"; shift 2 ;;
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --output)       OUTPUT_DIR="${2:-}"; shift 2 ;;
        --image)        IMAGE="${2:-}"; shift 2 ;;
        --clean)        CLEAN=1; shift ;;
        *)              fail "Option inconnue : $1" ;;
    esac
done

case "$BOARD" in
    v3|v2|pico|pico-lite) ;;
    *) fail "Carte inconnue : $BOARD (v3, v2, pico, pico-lite)" ;;
esac

printf '%s=== Compilation du menu n64cart-manager (carte %s) ===%s\n' "$CYAN" "$BOARD" "$RESET"

is_project_dir() {
    [ -f "$1/rom/Makefile" ] && [ -f "$1/fw/CMakeLists.txt" ]
}

if [ -n "$PROJECT_ROOT" ]; then
    is_project_dir "$PROJECT_ROOT" || fail "Aucun projet n64cart sous $PROJECT_ROOT (rom/Makefile attendu)."
else
    parent="$(cd -- "$SCRIPT_DIR/.." && pwd)"
    if is_project_dir "$parent"; then
        PROJECT_ROOT="$parent"
    else
        found=()
        for dir in "$parent"/*/; do
            [ -d "$dir" ] || continue
            if is_project_dir "$dir"; then
                found+=("$(cd -- "$dir" && pwd)")
            fi
        done
        [ "${#found[@]}" -gt 0 ] || fail "Projet n64cart introuvable autour de $parent. Utilise --project-root <chemin>."
        if [ "${#found[@]}" -gt 1 ]; then
            printf '%sPlusieurs projets trouves :%s\n' "$YELLOW" "$RESET"
            printf '  %s\n' "${found[@]}"
            fail "Precise lequel utiliser avec --project-root <chemin>."
        fi
        PROJECT_ROOT="${found[0]}"
    fi
fi
PROJECT_ROOT="$(cd -- "$PROJECT_ROOT" && pwd)"
ROM_DIR="$PROJECT_ROOT/rom"

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$SCRIPT_DIR/../Output"
fi
mkdir -p "$OUTPUT_DIR/rom"
OUT_DIR="$(cd -- "$OUTPUT_DIR/rom" && pwd)"

printf 'Script    : %s\n' "$SCRIPT_DIR"
printf 'Racine    : %s\n' "$PROJECT_ROOT"
printf 'Sources   : %s\n' "$ROM_DIR"
printf 'Sortie    : %s\n' "$OUT_DIR"

LOCAL_LIBDRAGON="$SCRIPT_DIR/../SDK/libdragon"
if [ -z "${N64_INST:-}" ] && [ -f "$LOCAL_LIBDRAGON/mips64-elf/lib/libdragon.a" ] \
   && [ -x "$LOCAL_LIBDRAGON/bin/n64sym" ]; then
    N64_INST="$(cd -- "$LOCAL_LIBDRAGON" && pwd)"
    export N64_INST
    export PATH="$N64_INST/bin:$PATH"
fi

has_native() {
    [ -n "${N64_INST:-}" ] && [ -x "$N64_INST/bin/mips64-elf-gcc" ] && command -v make >/dev/null 2>&1
}

has_docker() {
    command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1
}

if [ "$BACKEND" = "auto" ]; then
    if ! has_native; then

        GETTER="$SCRIPT_DIR/get-libdragon.sh"
        [ -f "$GETTER" ] || fail "libdragon est absent et get-libdragon.sh est introuvable dans $SCRIPT_DIR."

        printf '\n%slibdragon absent : installation dans %s%s\n' \
            "$YELLOW" "$(cd -- "$SCRIPT_DIR/.." && pwd)/SDK" "$RESET"
        bash "$GETTER" || fail "L installation de libdragon a echoue."

        if [ -f "$LOCAL_LIBDRAGON/mips64-elf/lib/libdragon.a" ] && [ -x "$LOCAL_LIBDRAGON/bin/n64sym" ]; then
            N64_INST="$(cd -- "$LOCAL_LIBDRAGON" && pwd)"
            export N64_INST
            export PATH="$N64_INST/bin:$PATH"
        fi
    fi

    if has_native; then
        BACKEND="native"
    else
        fail "libdragon est installe mais make ou mips64-elf-gcc reste introuvable dans ${N64_INST:-<non defini>}."
    fi
fi

printf 'Backend   : %s\n' "$BACKEND"

MAKE_ARGS="BOARD=$BOARD"
[ "$CLEAN" -eq 1 ] && MAKE_ARGS="clean $MAKE_ARGS"

case "$BACKEND" in
    native)
        has_native || fail "Backend native demande mais N64_INST ou make est absent."
        printf 'N64_INST  : %s\n' "$N64_INST"

        if ! command -v xxd >/dev/null 2>&1; then
            command -v python3 >/dev/null 2>&1 \
                || fail "Le Makefile de la ROM a besoin de xxd, absent du systeme, et python3 n est pas la pour le remplacer.
Installe l un des deux : sudo apt install xxd    (ou vim-common sur les Debian plus anciennes)"

            SHIM_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)/SDK/shims"
            mkdir -p "$SHIM_DIR"
            cat > "$SHIM_DIR/xxd" <<'XXD_SHIM'
#!/usr/bin/env python3
import sys

args = sys.argv[1:]
if not args or args[0] != "-i":
    sys.exit("xxd: seul -i est gere par ce remplacant")

path = args[1]
name = "".join(c if c.isalnum() else "_" for c in path)
data = open(path, "rb").read()

out = [f"unsigned char {name}[] = {{"]
for start in range(0, len(data), 12):
    chunk = data[start:start + 12]
    out.append("  " + ", ".join(f"0x{b:02x}" for b in chunk) + ("," if start + 12 < len(data) else ""))
out.append("};")
out.append(f"unsigned int {name}_len = {len(data)};")
sys.stdout.buffer.write(("\n".join(out) + "\n").encode())
XXD_SHIM
            chmod +x "$SHIM_DIR/xxd"
            PATH="$SHIM_DIR:$PATH"
            export PATH
            printf '%sxxd absent : remplacant local utilise (%s)%s\n' "$YELLOW" "$SHIM_DIR/xxd" "$RESET"
        fi

        (cd "$ROM_DIR" && make $MAKE_ARGS) || fail "make a echoue."
        ;;
    docker)
        has_docker || fail "Docker n est pas disponible (le service tourne-t-il ?)."
        printf '\n%s--- docker run %s ---%s\n' "$CYAN" "$IMAGE" "$RESET"

        docker run --rm -v "$PROJECT_ROOT:/src" -w /src/rom "$IMAGE" /bin/bash -lc \
            "command -v xxd >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq xxd || apt-get install -y -qq vim-common); make $MAKE_ARGS" \
            || fail "La compilation dans le conteneur a echoue."
        ;;
    *)
        fail "Backend inconnu : $BACKEND (auto, native, docker)"
        ;;
esac

ROM="$ROM_DIR/n64cart-manager.z64"
[ -f "$ROM" ] || fail "n64cart-manager.z64 n a pas ete produit."

cp -f "$ROM" "$OUT_DIR/n64cart-manager.z64"

printf '\n%s=================== Recapitulatif ===================%s\n' "$CYAN" "$RESET"
printf '%s%-28s %10s%s\n' "$GREEN" "n64cart-manager.z64" "$(du -h "$OUT_DIR/n64cart-manager.z64" | cut -f1)" "$RESET"
printf '\n%sFichier dans : %s%s\n' "$GREEN" "$OUT_DIR" "$RESET"
printf "N64 Cart Control le proposera automatiquement si la cartouche ne l a pas.\n"
