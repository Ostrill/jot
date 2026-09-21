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

1. **Two-layer text system.** Text is drawn twice: a near-opaque *backdrop* layer and
   the translucent editor glyphs on top. Both are layout managers over **one shared
   `NSTextStorage`**, so the backdrop mirrors edits for free. Its colour and the
   legibility halo are forced at draw time by `BackdropLayoutManager.showCGGlyphs`; the
   halo lives there and **only** there, because a shadow under a translucent glyph shows
   through and dims it.
   **The backdrop must stay a plain NSView, never a second NSTextView.** A second text
   view over the same storage brings its own selection/responder/undo machinery and
   silently **breaks ⌘Z in the editor** — it was shipped broken for a few commits before
   a harness test caught it.
   The insertion-point blink timer is fragile: mutating settings the wrong way can
   freeze the caret blink or flicker text colour. Prefer updating the view's live
   colour over re-baking settings on every keystroke.

2. **Anything per-keystroke must stay O(edit), not O(document).** Three separate
   full-document passes used to run on every character typed, and each was ~100× more
   expensive than the edit itself. In particular:
   - **Assigning `NSTextContainer.size` invalidates the layout of the whole document.**
     Write it only when it actually changes (`syncEditorLayout`), or the following
     `ensureLayout` re-lays out the entire file.
   - Rewriting an attribute over the whole storage (the old math highlight) invalidates
     the whole layout with it — repaint only the range whose colour changes.
   - `MathSyntax.completeSpans` walks the document; parse once per reconcile and pass
     the result around.
   - **Never measure with `usedRect(for:)`.** It is updated *during* the layout pass the
     same call triggers, so the first call after a large change returns a stale value
     (18 pt for a 2000-line document) and only a second, identical call is right. Use
     `boundingRect(forGlyphRange:in:)` plus the extra line fragment, as
     `measuredTextHeight()` does.
   - Above ~40k characters the exact height is **not** measured while typing, opening or
     resizing (`syncEditorLayout(deferHeightInLargeDocuments:)`): the content is grown to
     cover the viewport and the caret's line, and the exact measurement runs 100 ms after
     things settle. Asking for it inline is what made a big document stutter.

   There is a local harness for all of this under `devtools/` (git-ignored):
   `devtools/run.sh render|roundtrip|edit|bench|open`, plus a pixel-diff tool, and
   `BUILD_FROM=<git-ref>` to build the same harness from an older revision for
   before/after comparison. Screen capture is unavailable to agents here, so this is how
   a change is proven not to alter rendering.

3. **LaTeX = one parser + a deferred reconciler.**
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

4. **Traffic lights are positioned by AppKit.** They are lowered by giving the window
   an **empty, transparent unified toolbar** (`installTitlebarToolbar`), which grows
   the titlebar so AppKit itself lays the buttons out clear of the large corner radius.
   Do **not** use `setFrameOrigin` (moves the buttons but not their hover tracking) or
   a titlebar accessory (measured to be a no-op here).

5. **The formula preview is an in-window subview**, repositioned from `layout()` so it
   tracks the formula on resize. A separate floating child window was tried and
   reverted (it lost the liquid-glass look and drifted).

6. **Never change `CFBundleIdentifier`** (`com.jot.Jot`). It changes which
   `UserDefaults` plist macOS reads, which silently wipes the user's settings.

7. **Font limitation:** the bundled math font has no Cyrillic. Cyrillic inside math
   must use `$$\text{…}$$` (text mode has a Unicode fallback path).

8. **Window collection behaviour must stay `.managed`.** The window is a normal
   document window (`[.managed, .fullScreenPrimary]`). It was once created with
   `[.fullScreenAuxiliary, .moveToActiveSpace]` — those are mutually exclusive with
   `.managed`, which left the window outside normal Spaces/Mission Control handling
   (the Dock icon could not switch Spaces to it).

9. **The window is rendered twice by the system, and the second way is unforgiving.**
   Besides the live composite, macOS re-renders the window from a *static snapshot*
   (Mission Control's desktop thumbnails, the window switcher, screenshots, the
   minimise animation). In that path `NSGlassEffectView` collapses to a flat plate and
   **its `contentView` is not drawn at all** — which is why the app's content is a
   sibling on top of the glass, not inside it. Decorative overlays are risky there too:
   a sheen gradient at 0.01 opacity came out at full strength (diagonal stripes across
   the window) and a 0.05-alpha border layer flickered along the corners during the
   transition; both were deleted. What remains — the window looking dark in the
   thumbnail strip — is **not** fixable from the app: window alpha, glass style, dim
   opacity and hiding the glass view on resign-key were all measured to have no effect
   (the notification does arrive ~180 ms before the redraw), so the system is drawing
   from a snapshot cached while the window was still active. Don't re-litigate this.

10. **Appearance values with no UI are constants**, in `PanelSettings.Fixed` — not
   stored settings that get overwritten at launch. Only what the user can change is
   persisted, and each default literal exists once (the property default doubles as
   the load fallback).

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
