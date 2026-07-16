#!/usr/bin/env bash
# Construit un paquet Debian/Ubuntu (.deb) de RottenText.
# Prerequis : avoir compile l'executable avec scripts/build.sh --release, et
# disposer de dpkg-deb. Usage : ./build-deb.sh [version]
#
# Valide le 2026-07-13 (Ubuntu, GNOME 50) : construction, dpkg -i, lancement,
# desinstallation.
#
# Layout : le binaire N'EST PAS dans /usr/bin. Les loaders cherchent syntax/ et
# themes/ A COTE de l'executable (ExtractFilePath(ParamStr(0))), donc un
# /usr/bin/rottentext nu irait chercher /usr/bin/syntax/. Tout vit dans
# /usr/lib/rottentext/ et /usr/bin/rottentext est un WRAPPER qui fait exec sur
# le vrai binaire -- exec remplace argv[0] par le chemin reel, donc ParamStr(0)
# pointe bien vers /usr/lib/rottentext/ (un simple symlink ne suffirait PAS :
# argv[0] resterait /usr/bin/rottentext).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# version = RT_VERSION d'uMain (source unique, aussi montree par Help > About)
ver="${1:-$(sed -n "s/.*RT_VERSION = '\([^']*\)'.*/\1/p" "$root/src/uMain.pas" | head -1)}"
[ -n "$ver" ] || { echo "Version introuvable dans src/uMain.pas" >&2; exit 1; }
arch="$(dpkg --print-architecture)"
bin="$root/RottenText"

if [ ! -x "$bin" ]; then
	echo "Executable absent : compile d'abord avec scripts/build.sh --release" >&2
	exit 1
fi

pkg="$here/build/rottentext_${ver}_${arch}"
rm -rf "$pkg"
mkdir -p "$pkg/DEBIAN" \
	"$pkg/usr/bin" \
	"$pkg/usr/lib/rottentext" \
	"$pkg/usr/share/applications" \
	"$pkg/usr/share/doc/rottentext"

# binaire + donnees runtime, cote a cote (contrainte des loaders)
install -m 0755 "$bin" "$pkg/usr/lib/rottentext/RottenText"
cp -r "$root/syntax" "$pkg/usr/lib/rottentext/"
cp -r "$root/themes" "$pkg/usr/lib/rottentext/"
chmod -R a+rX "$pkg/usr/lib/rottentext/syntax" "$pkg/usr/lib/rottentext/themes"

# wrapper : exec => argv[0] = le vrai chemin, syntax/ et themes/ sont trouves
cat > "$pkg/usr/bin/rottentext" <<'EOF'
#!/bin/sh
exec /usr/lib/rottentext/RottenText "$@"
EOF
chmod 0755 "$pkg/usr/bin/rottentext"

install -m 0644 "$here/rottentext.desktop" "$pkg/usr/share/applications/rottentext.desktop"

# Licences. Les polices Monaspace sont COMPILEES DANS le binaire (ressources
# RCDATA), donc l'OFL impose que son texte accompagne meme une distribution
# binaire seule -- d'ou licenses/ dans le paquet, pas seulement le copyright.
install -m 0644 "$root/LICENSE" "$pkg/usr/share/doc/rottentext/copyright"
install -m 0644 "$root/LICENSE_THIRD_PARTIES.md" "$pkg/usr/share/doc/rottentext/"
install -m 0644 "$root/licenses/OFL-1.1-Monaspace.txt" "$pkg/usr/share/doc/rottentext/"

# Icones dans le theme hicolor. La source (icons/rottentext.png) n'est PAS
# carree (629x754) : on la met au carre avec du transparent plutot que de la
# deformer. ImageMagick est optionnel ; sans lui on pose la source telle quelle.
if command -v magick >/dev/null 2>&1; then im="magick"
elif command -v convert >/dev/null 2>&1; then im="convert"
else im=""
fi
src_icon="$root/icons/rottentext.png"
if [ -n "$im" ]; then
	for s in 16 24 32 48 64 128 256; do
		d="$pkg/usr/share/icons/hicolor/${s}x${s}/apps"
		mkdir -p "$d"
		"$im" "$src_icon" -resize "${s}x${s}" -background none -gravity center \
			-extent "${s}x${s}" "$d/rottentext.png"
		chmod 0644 "$d/rottentext.png"
	done
else
	# repli sans ImageMagick : le PNG 256 carre embarque dans le binaire fait
	# l'affaire (la source brute, elle, est rectangulaire et sortirait de travers)
	echo "ImageMagick absent : icone 256x256 posee telle quelle" >&2
	d="$pkg/usr/share/icons/hicolor/256x256/apps"
	mkdir -p "$d"
	install -m 0644 "$root/icons/rottentext-256.png" "$d/rottentext.png"
fi

# Depends CALCULE, jamais ecrit a la main: les noms de paquets bougent (la
# transition time64 d'Ubuntu a renomme libgtk2.0-0 en libgtk2.0-0t64, et un
# Depends sur un paquet inexistant = paquet INSTALLABLE NULLE PART, vecu).
# dpkg-shlibdeps lit les libs reellement liees et rend noms + versions minimales.
deps=""
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
	sd="$here/build/shlibdeps"
	rm -rf "$sd"; mkdir -p "$sd/debian"
	: > "$sd/debian/control"   # shlibdeps exige un debian/control, meme vide
	if (cd "$sd" && dpkg-shlibdeps -O --ignore-missing-info \
		"$pkg/usr/lib/rottentext/RottenText" 2>/dev/null) > "$sd/out"; then
		deps="$(sed -n 's/^shlibs:Depends=//p' "$sd/out")"
	fi
	rm -rf "$sd"
fi
if [ -z "$deps" ]; then
	echo "dpkg-shlibdeps indisponible : Depends de repli (a verifier)" >&2
	deps="libc6, libgtk2.0-0t64 | libgtk2.0-0, libx11-6"
fi

sed -e "s/@VERSION@/$ver/" -e "s/@ARCH@/$arch/" -e "s/@DEPENDS@/$deps/" \
	"$here/control.in" > "$pkg/DEBIAN/control"

dpkg-deb --build --root-owner-group "$pkg"
echo "OK -> ${pkg}.deb"
echo "Depends: $deps"
