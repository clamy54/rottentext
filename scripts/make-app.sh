#!/usr/bin/env bash
# Fabrique RottenText.app (macOS). Compiler le binaire ne suffit pas sous macOS:
# il faut le bundle .app, y embarquer les ressources runtime (themes/ + syntax/)
# et le signer (ad-hoc suffit pour un lancement local sur Apple Silicon).
#
# themes/ et syntax/ vont dans Contents/MacOS/ (a COTE du binaire) car le code
# les cherche via ExtractFilePath(ParamStr(0)) = dossier de l'exe = Contents/MacOS.
# Les polices sont deja embarquees en ressources (pas besoin de fonts/).
#
# Usage: scripts/make-app.sh [--release]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# 1) compiler le binaire (build.sh localise lazbuild tout seul)
"$root/scripts/build.sh" "$@"

app="$root/RottenText.app"
macos="$app/Contents/MacOS"
res="$app/Contents/Resources"

# 2) (re)fabriquer le bundle propre
rm -rf "$app"
mkdir -p "$macos" "$res"

cp "$root/RottenText" "$macos/RottenText"
chmod +x "$macos/RottenText"

# 3) ressources runtime a cote du binaire
[ -d "$root/themes" ] && cp -R "$root/themes" "$macos/themes"
[ -d "$root/syntax" ] && cp -R "$root/syntax" "$macos/syntax"

# 4) icone .icns (best effort, cosmetique: un echec ne bloque pas le build)
icon_ok=0
if command -v sips >/dev/null && command -v iconutil >/dev/null && [ -f "$root/icons/rottentext.png" ]; then
  tmpset="$(mktemp -d)/RottenText.iconset"
  mkdir -p "$tmpset"
  if for s in 16 32 128 256 512; do
       sips -z "$s" "$s" "$root/icons/rottentext.png" --out "$tmpset/icon_${s}x${s}.png" >/dev/null 2>&1 || exit 1
       d=$((s*2))
       sips -z "$d" "$d" "$root/icons/rottentext.png" --out "$tmpset/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || exit 1
     done; then
    if iconutil -c icns "$tmpset" -o "$res/RottenText.icns" >/dev/null 2>&1; then
      icon_ok=1
    fi
  fi
  rm -rf "$(dirname "$tmpset")"
fi

# 5) Info.plist
# PIEGE: ne JAMAIS mettre NSPrincipalClass. LCL-Cocoa instancie la classe app
# depuis cette cle (InitApplication, cocoaint.pas); NSApplication brut =
# la boucle LCL ne tourne pas -> Application.Terminate ignore = app inquittable.
# Cle absente -> LCL cree sa TCocoaApplication (comme les bundles Lazarus).
# version = RT_VERSION d'uMain (source unique, aussi montree par Help > About)
ver="$(sed -n "s/.*RT_VERSION = '\([^']*\)'.*/\1/p" "$root/src/uMain.pas" | head -1)"
[ -n "$ver" ] || ver="1.0"
iconline=""
[ "$icon_ok" = 1 ] && iconline="	<key>CFBundleIconFile</key>
	<string>RottenText</string>"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>RottenText</string>
	<key>CFBundleDisplayName</key>
	<string>RottenText</string>
	<key>CFBundleExecutable</key>
	<string>RottenText</string>
	<key>CFBundleIdentifier</key>
	<string>org.clamy.rottentext</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$ver</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Cyril LAMY - GPL v2</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Text Document</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.text</string>
				<string>public.plain-text</string>
				<string>public.source-code</string>
				<string>public.script</string>
				<string>public.shell-script</string>
				<string>public.make-source</string>
				<string>public.xml</string>
				<string>public.json</string>
				<string>public.yaml</string>
				<string>public.comma-separated-values-text</string>
				<string>public.log</string>
				<string>net.daringfireball.markdown</string>
			</array>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
		</dict>
		<dict>
			<!-- outils ops du menu Tools: X.509 Inspector et Mail Trace ouvrent
			     ces formats, ils meritent d'etre proposes dessus. -->
			<key>CFBundleTypeName</key>
			<string>Certificate or Message</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.x509-certificate</string>
				<string>public.email-message</string>
				<string>com.apple.mail.email</string>
			</array>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
		</dict>
		<dict>
			<!-- fichier brut: un Dockerfile (et tout fichier sans extension) sort
			     en public.data. La vue hex ouvre n'importe quoi, donc c'est une
			     revendication honnete.
			     MESURE (pas de la doc): LaunchServices etend la conformance DANS
			     un arbre (public.source-code attrape public.pascal-source) mais
			     public.data ne descend PAS vers ses sous-types -- un .jpg ne
			     matche donc pas ce type. Le joker CFBundleTypeExtensions=* est,
			     lui, purement ignore (verifie): les seules revendications qui
			     comptent sont les UTI. -->
			<key>CFBundleTypeName</key>
			<string>Any File</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.data</string>
				<string>public.item</string>
			</array>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
		</dict>
		<dict>
			<!-- fourre-tout Carbon: le SEUL mecanisme qui marche encore pour "je
			     sais ouvrir n'importe quoi". Il ne nous ajoute PAS au sous-menu
			     "Ouvrir avec" de chaque photo (pas de bruit), il evite juste
			     d'etre GRISE dans "Ouvrir avec > Autre..." sur un type qu'on ne
			     revendique pas (binaire -> vue hex). Pas de LSHandlerRank ici:
			     on ne veut candidater a aucune association par defaut. -->
			<key>CFBundleTypeName</key>
			<string>Document</string>
			<key>CFBundleTypeOSTypes</key>
			<array>
				<string>****</string>
			</array>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
		</dict>
	</array>
	<!-- Les formats ops du menu Tools n'ont AUCUN UTI systeme: macOS leur colle
	     un UTI dynamique qui ne se conforme qu'a public.data, donc ils
	     n'heritaient d'aucun type texte et "Ouvrir avec" ne proposait rien.
	     On les DECLARE (imported = on ne pretend pas les posseder) comme du
	     texte: ils tombent alors dans le type "Text Document" ci-dessus. -->
	<key>UTImportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>org.toml.toml</string>
			<key>UTTypeDescription</key>
			<string>TOML Document</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>toml</string>
				</array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>org.dotenv.env</string>
			<key>UTTypeDescription</key>
			<string>Env File</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>env</string>
				</array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>io.terraform.tf</string>
			<key>UTTypeDescription</key>
			<string>Terraform Source</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>tf</string>
					<string>tfvars</string>
				</array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>org.ini.ini</string>
			<key>UTTypeDescription</key>
			<string>Configuration File</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>ini</string>
					<string>cfg</string>
					<string>conf</string>
				</array>
			</dict>
		</dict>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>org.freedesktop.systemd.unit</string>
			<key>UTTypeDescription</key>
			<string>systemd Unit</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
				<string>public.source-code</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>service</string>
					<string>timer</string>
					<string>socket</string>
					<string>container</string>
					<string>pod</string>
					<string>kube</string>
					<string>volume</string>
					<string>network</string>
				</array>
			</dict>
		</dict>
	</array>
$iconline
</dict>
</plist>
PLIST

plutil -lint "$app/Contents/Info.plist" >/dev/null

# 6) signature ad-hoc (arm64 doit etre signe pour s'executer; pas d'identite
# Developer ID ici -> ad-hoc, OK en local)
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app" && echo "signature OK"

# 7) declarer le bundle a LaunchServices (best effort): sans ca "Ouvrir avec" ne
# propose pas une app qui vit hors de /Applications tant que le Finder ne l'a pas
# croisee. -f = relire l'Info.plist meme si le chemin est deja connu (sinon les
# CFBundleDocumentTypes modifies ne sont pas repris).
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$lsreg" ] && "$lsreg" -f "$app" 2>/dev/null || true

echo "OK -> $app"
