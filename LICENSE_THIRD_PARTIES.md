# Third-party licenses

RottenText is released by Cyril LAMY under the **GNU General Public License,
version 2** — full text in [`LICENSE`](LICENSE), as announced in
`Help > About RottenText`.

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

**Where it is used:** the 20 TTF files in `fonts/`
(`Monaspace{Neon,Argon,Xenon,Radon,Krypton}Frozen-{Regular,Bold,Italic,BoldItalic}.ttf`)
are compiled into the executable as RCDATA resources (see `src/uFontEmbed.pas`),
so **the shipped binary itself contains the font software**. The `fonts/`
directory is kept as the build-time source of those resources and as a runtime
fallback.

**Compliance notes:**

- The fonts are redistributed **unmodified**.
- OFL clause 2 explicitly allows the font software to be *bundled, embedded,
  redistributed and/or sold with any software*, so shipping OFL fonts inside a
  GPL-2 application is fine.
- OFL clause 5 requires the font software to remain **entirely under the OFL** —
  it is *not* relicensed to GPL-2 by being embedded. The GPL-2 covers
  RottenText's own code; the fonts stay OFL.
- The license text must travel with the fonts: that is what
  `licenses/OFL-1.1-Monaspace.txt` is for. **Keep it in any redistribution**,
  including binary-only ones.
- The **Reserved Font Names** must not be used to name a modified version of the
  fonts. RottenText ships no modified version, so nothing to do — but do not
  rename/patch the TTFs and keep calling them "Monaspace".

## 2. Lazarus LCL (Lazarus Component Library) — modified LGPL

| | |
|---|---|
| Upstream | <https://www.lazarus-ide.org> |
| License | LGPL **with the static-linking exception** (`COPYING.modifiedLGPL.txt` in the Lazarus tree) |

The whole UI is built on the LCL, which is statically linked into the
executable. The modified LGPL exists precisely to allow this: linking does not
force the application to become LGPL, provided the LCL itself stays under its
own license and users can relink against a modified LCL. Compatible with
RottenText's GPL-2.

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

Because SynEdit offers GPL 2+ as an alternative, it is compatible with
RottenText's GPL-2 as a whole.

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


## 6. Colour themes (`themes/`)

The theme files are **original JSON written for RottenText**. No code, no file
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


---

## Summary for redistributors

If you redistribute RottenText (source **or** binary), you must at least:

1. Keep `licenses/OFL-1.1-Monaspace.txt` alongside it — the binary embeds the
   Monaspace fonts, and the OFL requires its text to be distributed with them.
   The fonts stay under the OFL; they are not relicensed by being embedded.
2. Keep this file and [`LICENSE`](LICENSE) (the GPL-2 terms of RottenText
   itself).
3. Keep the dual MPL/GPL notice at the top of `src/uWrapView.pas` if you
   redistribute the source.
4. Do not name a modified version of the fonts with a Reserved Font Name
   ("Monaspace", "Argon", "Neon", "Xenon", "Radon", "Krypton").
