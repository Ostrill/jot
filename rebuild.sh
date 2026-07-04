#!/bin/zsh
# Standard Jot build script.
# Uses the STATIC transparent icon.png from project root (no background composite) and
# builds everything. (The old dynamic bg-tinting was removed with the reefAccent icon.)
set -euo pipefail

APP_PATH="Jot.app"
BIN_PATH="$APP_PATH/Contents/MacOS/GlassPanel"
RES_PATH="$APP_PATH/Contents/Resources"
ICONSET="build_icon/AppIcon.iconset"

if [[ ! -f "icon.png" ]]; then
  echo "icon.png not found in project root" >&2; exit 1
fi

echo "→ generating icon sizes from icon.png (static, transparent)"
python3 - << 'PYEOF'
from PIL import Image
import os

result = Image.open("icon.png").convert("RGBA")   # already a finished transparent icon

os.makedirs("build_icon/AppIcon.iconset", exist_ok=True)
for s in [16, 32, 128, 256, 512]:
    result.resize((s,    s   ), Image.LANCZOS).save(f"build_icon/AppIcon.iconset/icon_{s}x{s}.png")
    result.resize((s*2, s*2), Image.LANCZOS).save(f"build_icon/AppIcon.iconset/icon_{s}x{s}@2x.png")
result.save("build_icon/icon_composited.png")
print("   icon sizes generated (transparent, no bg composite)")
PYEOF

echo "→ creating AppIcon.icns"
mkdir -p "$RES_PATH"
iconutil --convert icns --output "$RES_PATH/AppIcon.icns" "$ICONSET"
cp -f "$RES_PATH/AppIcon.icns" "$RES_PATH/icon.icns"
cp -f icon.png "$RES_PATH/BaseIcon.png"

echo "→ bundling SwiftMath fonts"
rm -rf "$RES_PATH/mathFonts.bundle"
cp -R SwiftMath/mathFonts.bundle "$RES_PATH/mathFonts.bundle"

echo "→ compiling binary"
mkdir -p "$(dirname "$BIN_PATH")"
swiftmath_sources=(SwiftMath/**/*.swift)
xcrun swiftc main.swift "${swiftmath_sources[@]}" -o "$BIN_PATH"

echo "→ signing"
xattr -rc "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
touch "$APP_PATH"

echo "✓ Done: $APP_PATH (static icon)"
