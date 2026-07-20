#!/bin/sh
# Fiabilise la detection d'avance fractionnaire de SynEdit (macOS/CoreText):
# les echantillons courts (M, MM, MMM) s'arrondissent de facon coherente et
# masquent une derive par caractere (Monaspace: 9.086 px arrondis a 9). Sans
# le mode ETO le texte se corrompt au passage du curseur et la selection se
# decale. On sonde une longue chaine, ou la derive depasse l'arrondi.
# Usage: patch-synedit-fractional.sh <racine lazarus>
set -eu
f="$1/components/synedit/syntextdrawer.pp"
[ -f "$f" ] || { echo "syntextdrawer.pp introuvable: $f" >&2; exit 1; }
if grep -q 'Fractional advance (CoreText)' "$f"; then
  echo "deja patche: $f"
  exit 0
fi
python3 - "$f" <<'EOF'
import sys
p = sys.argv[1]
src = open(p).read()
anchor = "  // Make sure we get the correct Height"
block = """  // Fractional advance (CoreText): short samples round consistently and hide
  // a small per-char drift; probe a long run to detect it reliably.
  if (not ETO) and GetTextExtentPoint(DC, PChar('MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM'), 48, Size1) then
    if Size1.cx <> 48 * Width then
      ETO := True;

"""
if anchor not in src:
    sys.exit("ancre introuvable dans " + p)
open(p, 'w').write(src.replace(anchor, block + anchor, 1))
EOF
echo "OK -> $f"
