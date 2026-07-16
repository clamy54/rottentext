#!/usr/bin/env bash
# Cree un .dmg de RottenText : une fenetre contenant RottenText.app et un
# raccourci vers /Applications, cote a cote (glisser-deposer pour installer).
#
# Prerequis : avoir construit le bundle avec scripts/make-app.sh --release.
# C'est LUI le pipeline macOS (build + bundle + themes/syntax dans
# Contents/MacOS/ + .icns + Info.plist + signature ad-hoc) ; on ne le duplique
# pas ici, on empaquette juste son resultat.
#
# Usage : ./make-dmg.sh [version]
#
# Notarisation (optionnelle, pour une vraie distribution) : il faut d'abord une
# signature Developer ID (la signature ad-hoc de make-app.sh ne suffit pas),
# puis :
#   xcrun notarytool submit RottenText-<ver>.dmg --keychain-profile <profil> --wait
#   xcrun stapler staple RottenText-<ver>.dmg
# Sans ca, Gatekeeper bloque le premier lancement : ouvrir l'app une fois puis
# l'autoriser dans Reglages Systeme > Confidentialite et securite (Ouvrir quand
# meme). C'est normal sur de l'ad-hoc.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# version = RT_VERSION d'uMain (source unique, aussi montree par Help > About)
ver="${1:-$(sed -n "s/.*RT_VERSION = '\([^']*\)'.*/\1/p" "$root/src/uMain.pas" | head -1)}"
[ -n "$ver" ] || { echo "Version introuvable dans src/uMain.pas" >&2; exit 1; }

app="$root/RottenText.app"
if [ ! -d "$app" ]; then
	echo "Bundle absent : construis d'abord avec scripts/make-app.sh --release" >&2
	exit 1
fi

vol="RottenText"
stage="$here/build/dmg"
rm -rf "$stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

# les licences voyagent avec le .dmg : les polices Monaspace sont compilees DANS
# le binaire (ressources), l'OFL impose que son texte accompagne la distribution.
# Regroupees dans un dossier pour ne pas encombrer la fenetre d'installation.
mkdir -p "$stage/Licenses"
cp "$root/LICENSE" "$stage/Licenses/LICENSE.txt"
cp "$root/LICENSE_THIRD_PARTIES.md" "$stage/Licenses/"
cp "$root/licenses/OFL-1.1-Monaspace.txt" "$stage/Licenses/"

# image lecture/ecriture d'abord : la mise en page (positions des icones, taille
# de la fenetre) est stockee dans le .DS_Store du volume, donc il faut pouvoir
# ECRIRE dedans. La compression vient apres.
rw="$here/build/rw.dmg"
rm -f "$rw"
mb=$(( $(du -sm "$stage" | cut -f1) + 40 ))
hdiutil create -volname "$vol" -srcfolder "$stage" -ov -format UDRW \
	-size "${mb}m" "$rw" >/dev/null

att="$(hdiutil attach -readwrite -noverify -noautoopen "$rw")"
dev="$(printf '%s\n' "$att" | grep '^/dev/' | head -1 | awk '{print $1}')"
mnt="$(printf '%s\n' "$att" | grep -o '/Volumes/.*$' | head -1)"
[ -n "$dev" ] && [ -d "$mnt" ] || { echo "montage du dmg rate" >&2; exit 1; }
trap 'hdiutil detach "$dev" -force >/dev/null 2>&1 || true' EXIT

# Mise en page via le Finder. BEST EFFORT : piloter le Finder demande une
# autorisation d'automatisation (TCC) qui peut etre refusee ou absente en CI ->
# on borne l'attente et on continue sans layout plutot que de bloquer le build
# (le dmg reste fonctionnel, les icones sont juste non positionnees).
layout() {
	osascript <<-APPLESCRIPT
	tell application "Finder"
		tell disk "$vol"
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 120, 840, 520}
			set opts to the icon view options of container window
			set arrangement of opts to not arranged
			set icon size of opts to 128
			set text size of opts to 13
			set position of item "RottenText.app" of container window to {160, 175}
			set position of item "Applications" of container window to {480, 175}
			set position of item "Licenses" of container window to {320, 320}
			update without registering applications
			close
		end tell
	end tell
	APPLESCRIPT
}
layout >/dev/null 2>&1 &
lp=$!
for _ in $(seq 1 30); do
	kill -0 "$lp" 2>/dev/null || break
	sleep 1
done
if kill -0 "$lp" 2>/dev/null; then
	kill -9 "$lp" 2>/dev/null || true
	echo "ATTENTION: mise en page Finder abandonnee (autorisation d'automatisation ?)" >&2
elif wait "$lp"; then
	echo "mise en page OK"
else
	echo "ATTENTION: mise en page Finder echouee, dmg non stylise" >&2
fi

sync
rm -rf "$mnt/.fseventsd" "$mnt/.Trashes" 2>/dev/null || true
hdiutil detach "$dev" >/dev/null
trap - EXIT

dmg="$here/build/RottenText-${ver}.dmg"
rm -f "$dmg"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg" >/dev/null
rm -f "$rw"
rm -rf "$stage"
echo "OK -> $dmg"
