#!/usr/bin/env bash
# Installe le lanceur + l'icone pour l'utilisateur courant (~/.local), en
# pointant sur le binaire du dossier de build. Sert au dev et a qui n'installe
# pas le .deb.
#
# POURQUOI: sur GNOME recent (>= 45), une fenetre qui ne correspond a AUCUN
# .desktop est une "window-backed app" et le shell lui colle une icone
# generique -- le _NET_WM_ICON publie par l'app, meme correct, est ignore pour
# le dock et l'alt-tab. Le seul moyen d'avoir la bonne icone est un .desktop
# installe, relie a la fenetre par StartupWMClass (= WM_CLASS = RottenText).
#
# Usage: scripts/install-desktop.sh [--uninstall]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor"
entry="$apps/rottentext.desktop"

if [ "${1:-}" = "--uninstall" ]; then
	rm -f "$entry"
	find "$icons" -name 'rottentext.png' -delete 2>/dev/null || true
	update-desktop-database "$apps" 2>/dev/null || true
	echo "desinstalle."
	exit 0
fi

[ -x "$root/RottenText" ] || { echo "binaire absent: compile d'abord (scripts/build.sh)" >&2; exit 1; }

mkdir -p "$apps"
sed -e "s|^Exec=.*|Exec=$root/RottenText %f|" \
    -e "s|^TryExec=.*|TryExec=$root/RottenText|" \
    "$root/scripts/rottentext.desktop" > "$entry"
chmod 0644 "$entry"

# La source (icons/rottentext.png) n'est PAS carree: on part du PNG 256 carre
# (celui embarque dans le binaire). ImageMagick est optionnel.
src="$root/icons/rottentext-256.png"
if command -v magick >/dev/null 2>&1; then im=magick
elif command -v convert >/dev/null 2>&1; then im=convert
else im=""
fi
if [ -n "$im" ]; then
	for s in 16 24 32 48 64 128 256; do
		d="$icons/${s}x${s}/apps"
		mkdir -p "$d"
		"$im" "$src" -resize "${s}x${s}" "$d/rottentext.png"
	done
else
	d="$icons/256x256/apps"
	mkdir -p "$d"
	install -m 0644 "$src" "$d/rottentext.png"
fi

update-desktop-database "$apps" 2>/dev/null || true
gtk-update-icon-cache -f -t "$icons" 2>/dev/null || true

echo "installe: $entry"
echo "icone   : $icons/*/apps/rottentext.png"
echo "Le dock/alt-tab peuvent garder l'ancienne icone jusqu'a la prochaine"
echo "ouverture de la fenetre (le shell relie la fenetre au lanceur a sa creation)."
