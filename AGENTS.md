# AGENTS.md

Guidance for AI coding agents (and humans) working on **Jot**. Read this before
making changes — it captures the architecture and the non-obvious pitfalls that
aren't visible from the code alone.

## What Jot is

A native macOS text editor written in **Swift + AppKit**, rendered with the real
Liquid Glass material (`NSGlassEffectView`). Its headline feature is **inline LaTeX**:
text between `$$…$$` renders live via a vendored copy of
[SwiftMath](https://github.com/mgriebling/SwiftMath).

The project is deliberately flat: **no Xcode project, no storyboards, no asset
catalog**. The app is a handful of plain Swift files under `Sources/`, compiled
together with the SwiftMath sources under `SwiftMath/`.

## Repository layout

```
Sources/                   ← the application
  PanelSettings.swift      ← app-wide appearance state (UserDefaults)
  SupportViews.swift       ← window, flipped host, wrap guides, hit shield
  EditorTextView.swift     ← NSTextView subclass + math-editing host protocol
  Math.swift               ← inline LaTeX: parser, renderer, attachment, preview
  SliderMenuItemView.swift ← labelled slider inside a menu item
  GlassEditorView.swift    ← the per-window editor (glass stack + text layers)
  Document.swift           ← NSDocument + NSWindowController
  AppDelegate.swift        ← menus, app-wide appearance, Rainbow timer
  main.swift               ← entry point
SwiftMath/                 ← vendored LaTeX renderer (MIT) + Latin Modern Math font
build.sh                   ← build the app (no external deps)
make-dmg.sh                ← package Jot.app into a DMG for release
assets/icon.png            ← app icon source (1024²) + README image
Jot.app/Contents/Info.plist← the only tracked part of the app bundle
README.md / README.ru.md   ← user-facing docs (EN / RU)
```

The compiled binary, generated `.icns`, and bundled fonts inside `Jot.app` are
**git-ignored** — they are produced by `build.sh`.

## Building

```bash
./build.sh        # compile + generate icon + bundle fonts + ad-hoc sign
open Jot.app
```

`build.sh` uses **only Apple's toolchain** (`swiftc`, `sips`, `iconutil`,
`codesign`) — no Python, no Homebrew. Requirements: Xcode **Command Line Tools**
and **macOS 26 (Tahoe)** at runtime (the Liquid Glass APIs don't exist earlier).

After any change to files inside the bundle you must re-sign; `build.sh` already
runs `xattr -rc Jot.app && codesign --force --deep --sign - Jot.app`. The `xattr -rc`
is mandatory — stray extended attributes make `codesign` fail.

To read crashes/geometry, run the binary directly so its stdout reaches the shell:
`Jot.app/Contents/MacOS/GlassPanel > /tmp/log 2>&1 &` and use `NSLog`. Crash stacks
land in `~/Library/Logs/DiagnosticReports/GlassPanel-*.ips`.

> The Mach-O executable is still named **`GlassPanel`** (a legacy name;
> `CFBundleExecutable` in `Info.plist`). The product is always "Jot".

## Architecture (in `Sources/`)

- **`PanelSettings`** — single state object; serializes to `UserDefaults` under key
  `Jot.settings`; computes derived colors.
- **`GlassEditorView`** — the glass background, text layers, editor, status, wrap guides.
  Reused unchanged by every window.
- **`JotDocument` / `JotWindowController`** — one document + one window per file;
  NSDocument gives New/Open/Save, multi-window and the save-on-quit review.
- **`AppDelegate`** — menus, app-wide appearance, the rainbow timer; broadcasts
  appearance to every open editor.

## Non-obvious pitfalls (read before editing)

1. **Two-layer text system + blink timer.** Text is drawn across an editor layer and
   a backdrop layer; the insertion-point blink timer is fragile. Mutating settings the
   wrong way can freeze the caret blink or flicker text color. Prefer updating the
   view's live color over re-baking settings on every keystroke.

2. **LaTeX = one parser + a deferred reconciler.**
   - `MathSyntax` is the single escape-aware parser (`\$` = literal dollar) used for
     load, serialize, and live editing. Formula source is stored **byte-for-byte** so
     files round-trip exactly. Multi-line formulas are allowed (Enter inserts a
     newline; commit on click-away / arrow-out).
   - `reconcileMath()` makes the text storage match the parse (the caret's span stays
     raw source, others render). **It MUST run on the next runloop tick
     (`scheduleReconcile`) — mutating the text storage inside the text-change or
     selection-change notification crashes the layout manager**
     (`_fillLayoutHoleForCharacterRange`).
   - Rendering is gated by `settings.renderInlineFormulas` (Format ▸ "Render LaTeX
     Formulas").

3. **Traffic lights are positioned by AppKit.** They are lowered by giving the window
   an **empty, transparent unified toolbar** (`installTitlebarToolbar`), which grows
   the titlebar so AppKit itself lays the buttons out clear of the large corner radius.
   Do **not** use `setFrameOrigin` (moves the buttons but not their hover tracking) or
   a titlebar accessory (measured to be a no-op here).

4. **The formula preview is an in-window subview**, repositioned from `layout()` so it
   tracks the formula on resize. A separate floating child window was tried and
   reverted (it lost the liquid-glass look and drifted).

5. **Never change `CFBundleIdentifier`** (`com.jot.Jot`). It changes which
   `UserDefaults` plist macOS reads, which silently wipes the user's settings.

6. **Font limitation:** the bundled math font has no Cyrillic. Cyrillic inside math
   must use `$$\text{…}$$` (text mode has a Unicode fallback path).

## Conventions

- Keep the tree minimal — only build-essential files are tracked. Dev-only scripts and
  internal notes are git-ignored.
- The app icon is **rendered from code** (that generator lives outside the tracked
  tree); you don't need it to build — `build.sh` derives all `.icns` sizes from the
  full-bleed square art **`assets/icon-source.png`**. `assets/icon.png` is the
  macOS-rendered (rounded + shadowed) presentation icon used only in the README —
  never build from it (the system would mask it twice).
- Commit per feature/fix. This project has no automated tests; verify changes by
  building and running the app.
