#!/usr/bin/env bash
# fetch-headers.sh — recupere les headers UHT de Palworld 1.0 dans reference/.
#
# Pourquoi : le dump CTRL+H d'UE4SS n'est pas indispensable, les memes signatures
# sont publiees dans le PalworldModdingKit, mis a jour pour la 1.0. Ce script
# clone uniquement Source/Pal/Public (sparse checkout) : ~3700 headers, sans
# les .cpp ni les Plugins.
#
# reference/ est gitignore (brief SS7) : rien de tout ceci n'entre dans le depot.
# La provenance (SHA + date amont) est ecrite dans .palkit-version et recopiee
# a la main dans docs/sdk-notes.md.
#
# Usage : bash scripts/fetch-headers.sh

set -euo pipefail

REPO_URL="https://github.com/localcc/PalworldModdingKit.git"
SPARSE_PATH="Source/Pal/Public"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/reference/PalworldModdingKit"

if ! command -v git >/dev/null 2>&1; then
    echo "ERREUR : git est introuvable." >&2
    exit 1
fi

if [ -d "$DEST/.git" ]; then
    echo "-- clone existant, mise a jour"
    git -C "$DEST" fetch --depth 1 origin main
    git -C "$DEST" reset --hard origin/main
else
    echo "-- premier clone (sparse : $SPARSE_PATH)"
    rm -rf "$DEST"
    mkdir -p "$(dirname "$DEST")"
    git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$DEST"
    git -C "$DEST" sparse-checkout set "$SPARSE_PATH"
fi

SHA="$(git -C "$DEST" rev-parse --short HEAD)"
UPSTREAM_DATE="$(git -C "$DEST" log -1 --format=%cI)"
SUBJECT="$(git -C "$DEST" log -1 --format=%s)"
COUNT="$(find "$DEST/$SPARSE_PATH" -name '*.h' | wc -l)"

cat > "$DEST/.palkit-version" <<EOF
repo=$REPO_URL
path=$SPARSE_PATH
sha=$SHA
upstream_date=$UPSTREAM_DATE
upstream_subject=$SUBJECT
headers=$COUNT
fetched=$(date -Iseconds)
EOF

echo
echo "-- headers : $COUNT fichiers dans $DEST/$SPARSE_PATH"
echo "-- amont   : $SHA ($UPSTREAM_DATE) -- $SUBJECT"
echo
echo "A reporter dans docs/sdk-notes.md (table Contexte de version) :"
echo "  ModdingKit $SHA, ${UPSTREAM_DATE%%T*}"
