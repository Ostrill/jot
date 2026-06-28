#!/bin/zsh
# Standard Jot build script.
# Uses icon.png from project root, composites it over BG_COLOR, builds everything.
set -euo pipefail

BG_COLOR="${1:-#000F18}"   # pass a hex like ./rebuild.sh "#1A1A2E" to override
APP_PATH="Jot.app"
BIN_PATH="$APP_PATH/Contents/MacOS/GlassPanel"
RES_PATH="$APP_PATH/Contents/Resources"
ICONSET="build_icon/AppIcon.iconset"

if [[ ! -f "icon.png" ]]; then
  echo "icon.png not found in project root" >&2; exit 1
fi

echo "→ compositing icon.png with background $BG_COLOR"
python3 - "$BG_COLOR" << 'PYEOF'
import sys
from PIL import Image

hex_color = sys.argv[1].lstrip("#")
r, g, b = int(hex_color[0:2],16), int(hex_color[2:4],16), int(hex_color[4:6],16)

src = Image.open("icon.png").convert("RGBA")
bg  = Image.new("RGBA", src.size, (r, g, b, 255))
result = Image.alpha_composite(bg, src)

import os; os.makedirs("build_icon/AppIcon.iconset", exist_ok=True)
for s in [16, 32, 128, 256, 512]:
    result.resize((s,    s   ), Image.LANCZOS).save(f"build_icon/AppIcon.iconset/icon_{s}x{s}.png")
    result.resize((s*2, s*2), Image.LANCZOS).save(f"build_icon/AppIcon.iconset/icon_{s}x{s}@2x.png")
result.save("build_icon/icon_composited.png")
print(f"   icon sizes generated, bg=#{hex_color.upper()}")
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

echo "✓ Done: $APP_PATH (bg=$BG_COLOR)"
