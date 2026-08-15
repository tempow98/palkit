#!/usr/bin/env bash
#
# PalKit -- build.sh
#
# Assemble chaque mod de mods/ en un paquet installable dans dist/.
#
# Le brief (SS7) prevoit un build.ps1. Il ne peut pas tourner ici : le developpement se fait
# sur le Raspberry Pi (Linux), alors que Palworld est sur le PC Windows. build.sh est donc
# le script principal ; scripts/install-dev.ps1 prend le relais cote Windows pour deployer.
#
# Regle structurante (brief SS3.5) : la lib commune est COPIEE dans chaque mod au build.
# Aucune dependance croisee entre dossiers de mods a l'execution -- chaque mod reste
# installable seul, et sa suppression n'affecte aucun autre.
#
# Usage :
#   ./scripts/build.sh            # construit tous les mods
#   ./scripts/build.sh PalKitSpike  # n'en construit qu'un

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$ROOT/shared"
MODS="$ROOT/mods"
DIST="$ROOT/dist"

only="${1:-}"

# --- Controle syntaxique : rien ne part avec une erreur de syntaxe ------------------
# Le Lua local est en 5.1 et UE4SS tourne en 5.4 ; le code evite donc volontairement la
# syntaxe 5.4-only, ce qui rend ce controle valable. C'est la seule verification possible
# hors du jeu -- il n'y a ni Palworld ni UE4SS sur le Pi.
if command -v luac >/dev/null 2>&1; then
    echo "== Controle syntaxique =="
    while IFS= read -r -d '' f; do
        if ! luac -p "$f"; then
            echo "ECHEC : erreur de syntaxe dans $f" >&2
            exit 1
        fi
        echo "  ok  ${f#$ROOT/}"
    done < <(find "$SHARED" "$MODS" -name '*.lua' -print0)
else
    echo "!! luac absent -- controle syntaxique saute" >&2
fi

# --- Tests de la lib commune --------------------------------------------------------
if command -v lua >/dev/null 2>&1 && [ -f "$ROOT/scripts/test-shared.lua" ]; then
    echo "== Tests lib commune =="
    ( cd "$ROOT" && lua scripts/test-shared.lua ) || {
        echo "ECHEC : tests de la lib commune en echec" >&2
        exit 1
    }
fi

# --- Assemblage ---------------------------------------------------------------------
mkdir -p "$DIST"

built=0
for modpath in "$MODS"/*/; do
    mod="$(basename "$modpath")"
    [ -n "$only" ] && [ "$mod" != "$only" ] && continue

    if [ ! -f "$modpath/Scripts/main.lua" ]; then
        echo "!! $mod : pas de Scripts/main.lua, ignore" >&2
        continue
    fi

    echo "== $mod =="
    staging="$DIST/$mod"
    rm -rf "$staging"
    mkdir -p "$staging/Scripts"

    # Sources du mod
    cp -r "$modpath/Scripts/." "$staging/Scripts/"

    # Lib commune dupliquee a plat dans Scripts/, pour que `require("log")` resolve
    # directement : UE4SS ajoute le dossier Scripts/ du mod a package.path.
    cp "$SHARED"/*.lua "$staging/Scripts/"

    # UE4SS active les mods via Mods\mods.txt, mais certains builds lisent aussi
    # enabled.txt dans le dossier du mod. Le poser coute rien et evite un aller-retour.
    : > "$staging/enabled.txt"

    ( cd "$DIST" && zip -qr "$mod.zip" "$mod" )
    echo "  -> dist/$mod.zip"
    built=$((built + 1))
done

if [ "$built" -eq 0 ]; then
    echo "Aucun mod construit." >&2
    exit 1
fi

echo
echo "$built mod(s) construit(s) dans dist/."
echo "Rappel : ajouter '<NomDuMod> : 1' a Mods\\mods.txt cote jeu."
