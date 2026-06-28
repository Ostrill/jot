#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/icon.icns" >&2
  exit 1
fi

ICON_PATH="$1"
APP_PATH="Jot.app"
BIN_PATH="$APP_PATH/Contents/MacOS/GlassPanel"
RES_PATH="$APP_PATH/Contents/Resources"
TMP_DIR="$(mktemp -d /tmp/jot_icon.XXXXXX)"

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Icon file not found: $ICON_PATH" >&2
  exit 1
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$RES_PATH"
mkdir -p "$(dirname "$BIN_PATH")"
iconutil --convert iconset --output "$TMP_DIR/AppIcon.iconset" "$ICON_PATH"
iconutil --convert icns --output "$TMP_DIR/AppIcon.icns" "$TMP_DIR/AppIcon.iconset"
cp -f "$TMP_DIR/AppIcon.icns" "$RES_PATH/AppIcon.icns"
cp -f "$TMP_DIR/AppIcon.icns" "$RES_PATH/icon.icns"
xcrun swiftc main.swift -o "$BIN_PATH"
xattr -rc "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
touch "$APP_PATH"

echo "Rebuilt $APP_PATH with icon: $ICON_PATH"
