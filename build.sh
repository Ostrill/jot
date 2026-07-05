#!/bin/zsh
# Build Jot.app from source — no external dependencies.
# Uses only Apple's own toolchain (swiftc, sips, iconutil, codesign), all of
# which ship with the Xcode Command Line Tools / macOS. No Python, no Homebrew.
#
# Usage:  ./build.sh
set -euo pipefail

APP="Jot.app"
BIN="$APP/Contents/MacOS/GlassPanel"
RES="$APP/Contents/Resources"
ICON_SRC="assets/icon.png"

if [[ ! -f "$ICON_SRC" ]]; then
  echo "✗ $ICON_SRC not found" >&2
  exit 1
fi

mkdir -p "$RES" "$(dirname "$BIN")"

echo "→ generating AppIcon.icns from $ICON_SRC (native sips + iconutil)"
ICONSET="$(mktemp -d /tmp/jot_iconset.XXXXXX)/AppIcon.iconset"
mkdir -p "$ICONSET"
# size(px)  iconset name
for entry in \
  "16 16x16" "32 16x16@2x" \
  "32 32x32" "64 32x32@2x" \
  "128 128x128" "256 128x128@2x" \
  "256 256x256" "512 256x256@2x" \
  "512 512x512" "1024 512x512@2x"; do
  px="${entry%% *}"; name="${entry##* }"
  sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/icon_$name.png" >/dev/null
done
iconutil --convert icns --output "$RES/AppIcon.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

echo "→ bundling SwiftMath math font"
rm -rf "$RES/mathFonts.bundle"
cp -R SwiftMath/mathFonts.bundle "$RES/mathFonts.bundle"

echo "→ compiling (main.swift + SwiftMath)"
swiftmath_sources=(SwiftMath/**/*.swift)
xcrun swiftc main.swift "${swiftmath_sources[@]}" -o "$BIN"

echo "→ ad-hoc signing"
xattr -rc "$APP"
codesign --force --deep --sign - "$APP"
touch "$APP"

echo "✓ Done: $APP"
