# Third-party licenses

RottenText is released by Cyril LAMY under the **GNU General Public License,
version 3 or (at your option) any later version** — full text in
[`LICENSE`](LICENSE), as announced in `Help > About RottenText`.

This file inventories every third-party work that ends up in a RottenText
build, or that RottenText derives from, together with its license and what a
redistributor has to do about it. Every entry below was checked against the
actual upstream file or the metadata embedded in the shipped artifact, not
from memory.

---

## 1. Monaspace font family — SIL Open Font License 1.1



| | |
|---|---|
| Upstream | <https://github.com/githubnext/monaspace> |
| Copyright | Copyright (c) 2023, GitHub — with Reserved Font Name "Monaspace", including subfamilies "Argon", "Neon", "Xenon", "Radon" and "Krypton" |
| Designers | Riley Cran & the Lettermatic Team (<https://lettermatic.com>) |
| License | SIL Open Font License, Version 1.1 |
| Full text | [`licenses/OFL-1.1-Monaspace.txt`](licenses/OFL-1.1-Monaspace.txt) |

**Where it is used:** the 20 TTF files
`Monaspace{Neon,Argon,Xenon,Radon,Krypton}Frozen-{Regular,Bold,Italic,BoldItalic}.ttf`
are compiled into the executable as RCDATA resources by the RottenUI kit (see
section 7; `rottenui/src/uFontEmbed.pas`, sources in `rottenui/assets/fonts/`),
so **the shipped binary itself contains the font software**. The editor font is
picked in `View > Font...`.

**Compliance notes:**

- The fonts are redistributed **unmodified**.
- OFL clause 2 explicitly allows the font software to be *bundled, embedded,
  redistributed and/or sold with any software*, so shipping OFL fonts inside a
  GPL-3 application is fine.
- OFL clause 5 requires the font software to remain **entirely under the OFL** —
  it is *not* relicensed to GPL-3 by being embedded. The GPL-3 covers
  RottenText's own code; the fonts stay OFL.
- The license text must travel with the fonts: that is what
  `licenses/OFL-1.1-Monaspace.txt` is for. **Keep it in any redistribution**,
  including binary-only ones.
- The **Reserved Font Names** must not be used to name a modified version of the
  fonts. RottenText ships no modified version, so nothing to do — but do not
  rename/patch the TTFs and keep calling them "Monaspace".

## 1b. JetBrains Mono NL, Nerd Fonts patched — SIL Open Font License 1.1

| | |
|---|---|
| Upstream | <https://github.com/JetBrains/JetBrainsMono> (font), <https://github.com/ryanoasis/nerd-fonts> (patch) |
| Copyright | Copyright 2020 The JetBrains Mono Project Authors — Reserved Font Name "JetBrains Mono" |
| License | SIL Open Font License, Version 1.1 |
| Full text | [`licenses/OFL-1.1-JetBrainsMono.txt`](licenses/OFL-1.1-JetBrainsMono.txt) |

**Where it is used:** the 4 TTF files
`JetBrainsMonoNLNerdFontMono-{Regular,Bold,Italic,BoldItalic}.ttf` are
compiled into the executable the same way as Monaspace, and offered as an
alternative editor font in `View > Font...`.

**Compliance notes:**

- The shipped files are the Nerd Fonts build (family name `JetBrainsMonoNL NFM`):
  a Modified Version under the OFL, already renamed by the Nerd Fonts project
  so as not to carry the Reserved Font Name. RottenText does not modify them
  further.
- The added icon glyphs come from third-party icon sets under their own
  licenses (Font Awesome, Devicons, Octicons, Powerline, Material Design Icons,
  Codicons, Seti-UI...), see the Nerd Fonts repository.
- Same OFL obligations as Monaspace: keep
  `licenses/OFL-1.1-JetBrainsMono.txt` in any redistribution, the fonts stay
  under the OFL.

## 1c. Hack, Nerd Fonts patched — MIT and Bitstream Vera License

| | |
|---|---|
| Upstream | <https://github.com/source-foundry/Hack> (font), <https://github.com/ryanoasis/nerd-fonts> (patch) |
| Copyright | Copyright (c) 2018 Source Foundry Authors; Bitstream Vera Sans Mono Copyright (c) 2003 by Bitstream, Inc. — Reserved Font Names "Bitstream" and "Vera" |
| License | MIT License (the Hack work) and Bitstream Vera License (the Vera glyphs it derives from) |
| Full text | [`licenses/MIT-BitstreamVera-Hack.txt`](licenses/MIT-BitstreamVera-Hack.txt) |

**Where it is used:** the 4 TTF files
`HackNerdFontMono-{Regular,Bold,Italic,BoldItalic}.ttf` are compiled into the
executable by RottenUI the same way as Monaspace, and offered as an alternative
editor font in `View > Font...`.

**Compliance notes:**

- Hack derives from DejaVu Sans Mono, itself derived from Bitstream Vera Sans
  Mono: the Hack work is under the MIT License, the Vera part stays under the
  Bitstream Vera License, and both notices must accompany copies. That is what
  `licenses/MIT-BitstreamVera-Hack.txt` is for. **Keep it in any
  redistribution**, including binary-only ones.
- The shipped files are the Nerd Fonts build (family name `Hack Nerd Font
  Mono`): a modified version already renamed by the Nerd Fonts project, with
  neither "Bitstream" nor "Vera" in the name as the Vera licence requires of
  modified versions. RottenText does not modify them further.
- The added icon glyphs come from third-party icon sets under their own
  licenses, see the Nerd Fonts repository.
- The Vera licence forbids selling the font software by itself; it allows it
  as part of a larger software package, which is the case here.

## 2. Lazarus LCL (Lazarus Component Library) — modified LGPL

| | |
|---|---|
| Upstream | <https://www.lazarus-ide.org> |
| License | LGPL **with the static-linking exception** (`COPYING.modifiedLGPL.txt` in the Lazarus tree) |

The whole UI is built on the LCL, which is statically linked into the
executable. The modified LGPL exists precisely to allow this: linking does not
force the application to become LGPL, provided the LCL itself stays under its
own license and users can relink against a modified LCL. Compatible with
RottenText's GPL-3.

## 3. SynEdit — MPL 1.1, or GPL 2 or later, at your option

| | |
|---|---|
| Upstream | Lazarus, `components/synedit` (originally SynEdit / mwEdit by Martin Waldenburg) |
| License | Mozilla Public License 1.1, **or** GNU GPL v2+ at the recipient's option |
| Copyright | Portions created by Martin Waldenburg are Copyright (C) 1998 Martin Waldenburg. Contributors listed in SynEdit's `Contributors.txt`. |

**Where it is used:** the editing core (`TSynEdit`, one instance per document),
the TextMate highlighter (`TSynTextMateSyn`, `syntextmatesyn.pas`) and the macro
recorder (`SynMacroRecorder`).

**Derivative work — `src/uWrapView.pas`:** this file is a **local fork of
`syneditwrappedview.pp`** from the same package (needed because `GetWrapColumn`
is private and non-virtual, while RottenText must wrap at a fixed column). Under
the MPL that makes it a Modified Version, so the file carries the upstream
dual MPL/GPL notice and a description of the change, as MPL 1.1 §3.1 and §3.3
require. The notice is deliberately **kept dual** (not stripped down to GPL),
so recipients keep the choice between the MPL and the GPL.

Because SynEdit offers GPL 2 **or later** as an alternative, it is compatible
with RottenText's GPL-3 as a whole.

## 4. Free Pascal RTL / FCL — modified LGPL (static-linking exception)

| | |
|---|---|
| Upstream | <https://www.freepascal.org> |
| License | LGPL with the FPC static-linking exception (`COPYING.FPC`) |

Statically linked. Units actually used include `fpjson`/`jsonparser` (settings,
session, themes, JSON tools), `base64`, `md5`, `sha1`, `blowfish`,
`LConvEncoding` and `LazUTF8` (LazUtils), plus the **Printer4Lazarus** package
(the `File > Print` path).

## 5. TRegExpr — permissive (zlib-style) or modified LGPL, at your option

| | |
|---|---|
| Upstream | Andrey V. Sorokin — <https://sorokin.engineer/> |
| Shipped as | `xregexpr.pas`, inside the Lazarus `lazedit` package |
| License | Author's Option 1 (permissive, zlib-like) **or** Option 2 (the same modified LGPL with static-linking exception as the FPC RTL) |

Pulled in transitively: it is the regex engine behind the TextMate grammar
support, so it is linked into the binary.

The author asks that products using TRegExpr acknowledge it. Doing so here:

> Partial Copyright (c) 2004 Andrey V. Sorokin, <https://sorokin.engineer/>


## 6. Colour themes

The theme files (now shipped inside the RottenUI kit, `rottenui/assets/themes/`,
and compiled into the executable) are **original JSON written for RottenText**. No code, no file
and no asset is taken from the projects below; several palettes are, however,
openly *inspired by* well-known colour schemes, and credit is due to their
authors:

- **Monokai** — Wimer Hazenberg
- **One Dark** — the Atom / GitHub theme
- **Nord** — Arctic Ice Studio
- **Gruvbox** — Pavel Pertsev
- **Solarized** — Ethan Schoonover
- **Tango** — the Tango Desktop Project

Names and trademarks remain those of their respective authors. If you are a
rights holder and object to an adaptation, open an issue and it will be renamed
or reworked.


## 7. RottenUI — GPL 3 or later

| | |
|---|---|
| Upstream | <https://github.com/clamy54/rottenUI> (git submodule `rottenui/`) |
| Copyright | Copyright (C) 2023-2026 Cyril LAMY |
| License | GNU General Public License, version 3 or any later version |

**Where it is used:** the interface kit shared by the Rotten programs, by the
same author: themes, fonts, menu bar, tab bar, dialogs and message boxes. It is
statically linked. Same licence as RottenText itself, so there is nothing to
reconcile; it is listed here because it is a separate repository, and because
it is what brings sections 1, 1b, 1c and 8 into the binary.

## 8. Tabler Icons — MIT

| | |
|---|---|
| Upstream | <https://tabler.io/icons> |
| Copyright | Copyright (c) 2020-2024 Pawel Kuna (Tabler Icons) |
| License | MIT |
| Full text | [`licenses/MIT-Tabler.txt`](licenses/MIT-Tabler.txt) |

**Where it is used:** RottenUI draws its icons (message boxes, dialogs) from
monochrome masks rendered from Tabler icons and compiled into the executable as
resources (`rottenui/src/uIcons.pas`). The MIT licence asks for its copyright
and permission notice to accompany copies: that is what
`licenses/MIT-Tabler.txt` is for.

---

## Summary for redistributors

If you redistribute RottenText (source **or** binary), you must at least:

1. Keep `licenses/OFL-1.1-Monaspace.txt`, `licenses/OFL-1.1-JetBrainsMono.txt`
   and `licenses/MIT-BitstreamVera-Hack.txt` alongside it — the binary embeds
   the Monaspace, JetBrains Mono and Hack fonts, and the OFL, the MIT License
   and the Bitstream Vera License all require their text to be distributed
   with them. The fonts stay under their own licenses; they are not relicensed
   by being embedded.
2. Keep this file and [`LICENSE`](LICENSE) (the GPL-3 terms of RottenText
   itself), and `licenses/MIT-Tabler.txt` for the embedded icons.
3. Keep the dual MPL/GPL notice at the top of `src/uWrapView.pas` if you
   redistribute the source.
4. Do not name a modified version of the fonts with a Reserved Font Name
   ("Monaspace", "Argon", "Neon", "Xenon", "Radon", "Krypton",
   "JetBrains Mono", "Bitstream", "Vera").
