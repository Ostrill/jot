#!/bin/zsh
# Build a distributable DMG for Jot from the already-built Jot.app.
# Run ./build.sh first (this script does NOT compile).
#
# NOTE: the app is only ad-hoc signed (no Apple Developer ID / notarization),
# so users who download the DMG will hit Gatekeeper on first launch. Tell them
# to run:  xattr -dr com.apple.quarantine /Applications/Jot.app
set -euo pipefail

APP="Jot.app"
VOLNAME="Jot"

if [[ ! -d "$APP" ]]; then
  echo "✗ $APP not found — build it first:  ./build.sh" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="Jot-$VERSION.dmg"

STAGING="$(mktemp -d /tmp/jot_dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

echo "→ staging app + /Applications shortcut"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "→ creating $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "✓ Done: $DMG"
echo "  Users must remove the quarantine flag after copying to /Applications:"
echo "  xattr -dr com.apple.quarantine /Applications/Jot.app"
