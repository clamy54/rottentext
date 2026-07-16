# Packaging RottenText

Build the binary first (see [`../scripts`](../scripts)), then create a
distributable package for the target platform.

Two things every package must carry, whatever the platform:

- **`syntax/` and `themes/` must sit next to the executable.** The loaders
  resolve them as `ExtractFilePath(ParamStr(0)) + 'syntax'` (resp. `themes`) —
  nowhere else. A missing `themes/` is survivable (default colours, no
  `View > Theme` menu); a missing `syntax/` means no syntax highlighting.
  `fonts/` is *not* needed at runtime: the 20 Monaspace TTFs are compiled into
  the binary as resources.
- **The licenses.** Because those fonts live *inside* the executable, the SIL
  OFL requires its text to travel with any distribution, including binary-only
  ones. Every packaging below ships `licenses/OFL-1.1-Monaspace.txt`,
  `LICENSE` and `LICENSE_THIRD_PARTIES.md`. Do not drop them.

The version comes from `RT_VERSION` in `src/uMain.pas` — the single source of
truth, also shown in `Help > About`. All three packagings extract it themselves;
the Inno Setup script reads it at compile time and errors out if it is missing.

## Windows (`windows/`)

Inno Setup 6 installer.

1. `powershell -File scripts\build.ps1 -Release` (produces `RottenText.exe` at
   the repository root).
2. Compile the installer: `ISCC.exe dist\windows\rottentext.iss` (or open it in
   the Inno Setup IDE). Output: `dist\windows\output\RottenText-Setup-<version>.exe`.

Installs the executable, `syntax\`, `themes\` and the licenses into the install
directory, plus Start Menu (and optional desktop) shortcuts.

### License pages

The wizard's **License Agreement** page shows `LICENSE` (GPL-2) — the license of
RottenText itself, the one the user accepts. The **Information** page right after
shows the third-party inventory: embedded Monaspace fonts, LCL, FPC, SynEdit.

Showing it is a courtesy, not an obligation — what the licenses require is that
their text *accompanies* the distribution, which `[Files]` does. But Inno renders
its info file verbatim, and `LICENSE_THIRD_PARTIES.md` shown raw is unreadable
(`#`, `**`, table pipes). So `make-notices.ps1` renders it to plain text
(`third-party.txt`), and `rottentext.iss` **runs that script at compile time**
(`#expr Exec`) — the page therefore can never drift from the Markdown source.
`third-party.txt` is generated, hence git-ignored; the Markdown file stays the
single source of truth and is the one installed into `{app}`.

### Explorer context menu

An optional (ticked) task — **"Add to Explorer context menu"** — registers
**"Open with RottenText"**, with the app icon on the left. A file opened that
way joins the already-running instance as a new tab (mono-instance IPC).
Uninstalling removes the keys.

It is registered through the classic registry keys
(`Software\Classes\*\shell\RottenText`), which work **everywhere**: Windows 10,
Windows Server 2019/2022, and Windows 11.

**Known limitation on Windows 11:** the entry lands under *"Show more options"*
(Shift+F10), not in the main context menu. This is by design, not an oversight.
Windows 11's main menu only accepts extensions that (1) implement
`IExplorerCommand` — a COM DLL, since `IContextMenu` and registry keys are
explicitly relegated to the legacy menu — and (2) are shipped by an app with
**package identity** (MSIX or a sparse package), the extension being declared in
the package manifest rather than the registry. See Microsoft's *"Windows
application development - Best practices"*, section *Context menus*.

Getting into the modern menu would therefore require a COM DLL plus an MSIX
package **signed with a certificate the target machine trusts** — a real cost
for the user installing it (and no way around the certificate). Deliberate
trade-off: we stick to the registry, which works on every supported Windows
without a certificate and without friction.

## Linux (`linux/`)

Debian/Ubuntu `.deb`.

1. `scripts/build.sh --release` (produces `RottenText` at the repository root).
2. `dist/linux/build-deb.sh [version]` (needs `dpkg-deb`; ImageMagick optional,
   for properly sized icons). Output:
   `dist/linux/build/rottentext_<version>_<arch>.deb`.

**Layout note.** The binary is *not* installed as `/usr/bin/rottentext`. Since
the loaders look for `syntax/` and `themes/` next to the executable, everything
lives in `/usr/lib/rottentext/`, and `/usr/bin/rottentext` is a small wrapper
that `exec`s it. A symlink would *not* work: `argv[0]` would remain
`/usr/bin/rottentext` and the data directories would be looked up in `/usr/bin`.

Also installs a `rottentext.desktop` launcher and the icon in the hicolor theme.
The source icon is not square (629×754), so it is padded rather than distorted.

**The launcher is not cosmetic.** On GNOME >= 45 a window with no matching
`.desktop` is a "window-backed app" whose `_NET_WM_ICON` is ignored: the shell
shows a generic gear in the dock and the alt-tab switcher. `StartupWMClass`
(= `WM_CLASS` = `RottenText`) is what ties the window to the launcher. To get
the same result while running the binary straight from the build directory
(development), use `scripts/install-desktop.sh`.

**Dependencies are computed, never hand-written**, by `dpkg-shlibdeps`: package
names drift (Ubuntu's time64 transition renamed `libgtk2.0-0` to
`libgtk2.0-0t64`), and a `Depends` on a package that no longer exists yields a
`.deb` that installs nowhere — with nothing failing at build time.

Validated end to end on 2026-07-13 (Ubuntu, GNOME 50): build, `dpkg -i`, launch,
uninstall.

## macOS (`macos/`)

`.app` bundle then `.dmg`.

1. `scripts/make-app.sh --release` builds `RottenText.app` at the repository
   root. **That script is the macOS pipeline** (build → bundle → `themes/` and
   `syntax/` copied *inside* `Contents/MacOS/` next to the binary → `.icns` →
   `Info.plist` → ad-hoc signature, which is mandatory on Apple Silicon →
   `lsregister -f`). It is not duplicated here.
2. `dist/macos/make-dmg.sh [version]` wraps that bundle into a
   drag-to-Applications `.dmg`. Output: `dist/macos/build/RottenText-<ver>.dmg`.
   The install window is laid out (app left, `/Applications` alias right,
   `Licenses/` below). That layout lives in the volume's `.DS_Store`, so the
   script builds a read/write image, styles it **through the Finder**, then
   compresses it. Driving the Finder needs an automation (TCC) permission that
   may be missing (CI, locked machine): the script gives it 30 s, then ships the
   `.dmg` unstyled rather than hanging the build.

**"Open With" (LaunchServices).** `Info.plist` declares four document types, all
role `Editor` and rank `Alternate` — the app shows up in the menu but never
steals a default association. Measured, not assumed: a
`public.data` claim does **not** reach its subtypes, the `CFBundleTypeExtensions
= *` wildcard is ignored outright, and the ops formats (`.toml`, `.env`, `.tf`,
`.ini`, `.conf`) carry **no system UTI** at all — they get a dynamic one, so they
are declared as text via `UTImportedTypeDeclarations`.

With only an ad-hoc signature, Gatekeeper warns on first launch (right-click >
Open to get past it). Developer ID signing and notarization are documented at
the top of `make-dmg.sh`.

## Status

The Inno Setup installer is **tested end to end** on Windows 11: silent install,
syntax highlighting from the install directory, the context-menu command replayed
exactly as Explorer runs it (first click opens a window, the next ones land as
tabs in it), clean uninstall with no registry residue.

The `.deb` is **tested end to end** on Ubuntu/GNOME (build, `dpkg -i`, launch,
uninstall). Its `Depends` are computed by `dpkg-shlibdeps`, never hand-written:
the hand-written ones named packages that no longer exist on current Ubuntu (the
time64 transition renamed `libgtk2.0-0` to `libgtk2.0-0t64`), which would have
made the package installable nowhere.

The macOS `.app` pipeline is known good, and the `.dmg` is **tested**: layout
persisted, `/Applications` alias, the signature of the app *inside the image*
verified, and opening a file through "Open With" checked against LaunchServices.

## Releases (GitHub Actions)

Everything above also runs unattended in `.github/workflows/release.yml`:

1. Bump `RT_VERSION` in `src/uMain.pas`, commit.
2. `git tag v<version> && git push origin v<version>`.

The workflow refuses a tag that does not match `RT_VERSION`, builds the three
packages (macOS arm64 `.dmg`, Ubuntu amd64 `.deb`, Windows x64 setup, zipped)
and attaches them to a **draft** release. Review the draft on the releases page,
then publish it.

Dry run without a tag: *Actions > release > Run workflow*. Builds and uploads
the packages as run artifacts, skips the release.

Rerunning a failed run is safe: an existing release is reused and its files are
replaced, never duplicated.
