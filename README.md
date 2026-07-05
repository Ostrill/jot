<h1 align="right">
<code>🇺🇸</code>
<a href="README.ru.md">🇷🇺</a>
<br>
<div align="left">Jot</div>
</h1>

<p align="center">
  <img src="assets/icon.png" width="140" alt="Jot app icon">
</p>

<p align="center">
  A glassy, native <b>macOS</b> text editor with <b>live inline LaTeX</b> —
  built in a single Swift file on AppKit's Liquid Glass.
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%20Tahoe-000000?logo=apple&logoColor=white">
  <img alt="language" src="https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

## Overview

**Jot** is a compact, translucent scratchpad for macOS. It renders its window with
the real Liquid Glass material (`NSGlassEffectView`), so your text floats over a
frosted pane that refracts whatever is behind the window. Type math between `$$…$$`
and it renders inline, right where you're typing.

It's intentionally tiny: no Xcode project, no storyboards, no asset catalog — the
whole app is one `main.swift` plus a vendored copy of
[SwiftMath](https://github.com/mgriebling/SwiftMath) for LaTeX rendering.

## Features

- 🪟 **Liquid Glass window** — a genuine frosted-glass editor built on public AppKit APIs.
- 🧮 **Inline LaTeX** — type `$$…$$` and it renders live via SwiftMath. Auto-closing
  delimiters, multi-line formulas, and byte-for-byte source round-trip when you save.
- 🌈 **Rainbow Mode** — smoothly animates the glass tint (and the text) through the hue wheel.
- 🎛 **Appearance controls** — darkening, color strength, hue, rainbow speed, text opacity, always-on-top.
- 📐 **Word wrap + wrapped-line guides** — subtle markers show where long lines were folded.
- 💾 **Plain-text files** — open/save with an unsaved-changes indicator (`✶`).
- ⚡️ **Native & self-contained** — one Swift file, no Xcode required to build.

## Screenshots

<p align="center">
  <img src="assets/screenshot-editor.png" width="80%" alt="Jot's frosted-glass editor floating over another app">
  <br><em>The frosted-glass editor floats over whatever is behind it.</em>
</p>
<p align="center">
  <img src="assets/screenshot-formula.png" width="80%" alt="Inline LaTeX formula rendered live in Jot">
  <br><em>Type <code>$$…$$</code> and the formula renders live, right where you're editing.</em>
</p>

## Inline LaTeX — how it works

1. Make sure **Format ▸ Render LaTeX Formulas** is enabled.
2. Type `$$` — Jot auto-closes it to `$$$$` and drops your caret in the middle.
3. Type LaTeX, e.g.:

   ```latex
   $$E = mc^2$$
   $$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$
   ```

4. Move the caret out (click away or arrow past the delimiters) and the formula
   renders inline. Click back into it to edit the raw source again.

Notes:

- **Multi-line** formulas are supported (press Enter inside `$$…$$`).
- Use `\$` when you need a **literal dollar sign** in prose.
- The exact `$$…$$` source is preserved in the saved file — nothing is trimmed or reformatted.
- Cyrillic inside math needs `$$\text{…}$$` (the math font has no Cyrillic glyphs).

## Menus & shortcuts

| Action        | Shortcut |
|---------------|----------|
| Open…         | ⌘O       |
| Save          | ⌘S       |
| Save As…      | ⇧⌘S      |
| Quit Jot      | ⌘Q       |

- **Format:** Font Size (slider), Word Wrap, Wrapped Line Guides, Render LaTeX Formulas
- **Appearance:** Always on Top, Rainbow Mode, Darkening, Color Strength, Hue, Rainbow Speed, Text Opacity

## Requirements

- **macOS 26 (Tahoe) or later.** Jot is built on the Liquid Glass APIs
  (`NSGlassEffectView`), which don't exist on earlier macOS releases.
- To **build from source:** Apple **Command Line Tools** only (`swiftc`, `sips`,
  `iconutil`, `codesign`) — full Xcode is _not_ required, and there are **no
  external dependencies** (no Python, no Homebrew).

## Installation

### Option A — Download a release

1. Grab `Jot-x.y.dmg` from the [Releases](../../releases) page.
2. Open it and drag **Jot** into **Applications**.
3. Because the app isn't signed with an Apple Developer ID, macOS quarantines it.
   Clear the quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Jot.app
   ```

   (Alternatively: right-click the app ▸ Open, or approve it in
   **System Settings ▸ Privacy & Security**.)

### Option B — Build from source _(recommended)_

Building yourself avoids Gatekeeper entirely and always produces a binary for
your own Mac's architecture.

```bash
git clone https://github.com/Ostrill/jot.git
cd jot
./build.sh                 # compiles main.swift + SwiftMath, builds the icon, bundles fonts, ad-hoc signs
open Jot.app               # smoke-test
cp -R Jot.app /Applications/   # install
```

`build.sh` compiles `main.swift` together with the vendored SwiftMath sources,
generates the app icon with `sips`/`iconutil`, copies the math font bundle into
`Jot.app`, and ad-hoc signs the result — all with Apple's built-in tools.

### Building a DMG for a release

```bash
./build.sh        # build the app first
./make-dmg.sh     # produces Jot-<version>.dmg
```

## Why isn't the download signed / notarized?

Distributing a macOS app that opens with **no** Gatekeeper warning requires a paid
**Apple Developer Program** membership ($99/year) to sign with a *Developer ID*
certificate and **notarize** the build with Apple. Jot is a free hobby project, so
the releases are only **ad-hoc signed**. That's why you either run the one-line
`xattr` command above, or simply build from source. Everything works the same
afterwards — the notarization step only removes the first-launch prompt.

## Project layout

```
jot/
├── main.swift                 ← the entire app (~2000 lines)
├── SwiftMath/                 ← vendored LaTeX renderer (MIT) + math font
├── build.sh                   ← build: compile + icon + bundle fonts + sign (no external deps)
├── make-dmg.sh                ← package Jot.app into a DMG
├── assets/                    ← app icon + README screenshots
├── AGENTS.md                  ← architecture notes for contributors / AI agents
└── Jot.app/Contents/Info.plist
```

## Credits

- LaTeX rendering: [**SwiftMath**](https://github.com/mgriebling/SwiftMath) (MIT),
  vendored under `SwiftMath/`, with the Latin Modern Math font.
- Developed by **Vladimir ([Ostrill](https://github.com/Ostrill))** in collaboration
  with **Claude** (Anthropic).

## License

[MIT](LICENSE) © 2026 Vladimir (Ostrill). Bundled third-party components keep their
own licenses — see [`LICENSE`](LICENSE).
