#!/usr/bin/env bash
# Build portable (Linux / macOS). Localise lazbuild tout seul, chemin .lpi
# relatif, tue l'exe avant de recompiler. Marche depuis n'importe quelle machine.
#
# Usage: scripts/build.sh [--release]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lpi="$root/RottenText.lpi"

# lazbuild : PATH d'abord, puis emplacements d'install classiques
lazbuild="$(command -v lazbuild || true)"
if [ -z "$lazbuild" ]; then
  for c in \
    /usr/bin/lazbuild \
    /usr/local/bin/lazbuild \
    /Applications/Lazarus/lazbuild \
    "$HOME/Applications/Lazarus/lazbuild" \
    "$HOME/fpcupdeluxe/lazarus/lazbuild" \
    /Applications/fpcupdeluxe/lazarus/lazbuild \
    /snap/bin/lazbuild; do
    if [ -x "$c" ]; then lazbuild="$c"; break; fi
  done
fi
[ -n "$lazbuild" ] || { echo "lazbuild introuvable. Ajoute-le au PATH ou installe Lazarus." >&2; exit 1; }

# tuer l'exe s'il tourne (sinon lien impossible)
pkill -f RottenText 2>/dev/null || true

buildarg=""
[ "${1:-}" = "--release" ] && buildarg="--build-mode=Release"

echo "lazbuild: $lazbuild"
"$lazbuild" $buildarg "$lpi"
echo "OK -> $root/RottenText"
