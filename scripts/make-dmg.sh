#!/usr/bin/env bash
#
# Packages build/Sisyphus.app into build/Sisyphus.dmg: the app, an Applications shortcut and the
# install instructions, in a compressed read-only image.
#
# The image is verified by mounting it read-only and checking that the app binary and the
# Applications link are really there, so a broken DMG fails here instead of on a user's Mac.
# No Finder styling: that needs an AppleScript/UI session and buys nothing for a drag-install app.
#
# Run ./scripts/build-app.sh first.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Sisyphus"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"
STAGE="$BUILD_DIR/dmg"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found — run ./scripts/build-app.sh first" >&2
  exit 1
fi

echo "==> Staging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# ditto keeps the bundle's metadata (and its signature) intact; cp -R can drop extended attributes.
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install.txt" <<'TXT'
Sisyphus
========

1. Drag Sisyphus to the Applications folder in this window.
2. Open Sisyphus from your Applications folder.
3. macOS blocks the first launch, because the app is not notarised by Apple. Open
   System Settings > Privacy & Security, scroll down to the message about Sisyphus
   and click "Open Anyway". This is needed only once.
4. If macOS says the app "is damaged", run this in Terminal:

       xattr -dr com.apple.quarantine /Applications/Sisyphus.app

Requires macOS 14 or later. Works on Apple Silicon and Intel Macs.

Do not disable Gatekeeper for this app.
TXT

echo "==> Creating $DMG"
rm -f "$DMG"
# Deliberately not -quiet: it also hides the reason a failed create failed, which is the one message
# worth having on a build machine.
if ! hdiutil create \
  -volname "$APP_NAME" \
  -fs HFS+ \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"; then
  echo "error: 'hdiutil create' failed, so $DMG was not written" >&2
  exit 1
fi

echo "==> Verifying $DMG"
if ! hdiutil verify "$DMG"; then
  echo "error: 'hdiutil verify' rejected $DMG" >&2
  exit 1
fi

MOUNT="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT" -quiet || true
  rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

if ! hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT"; then
  echo "error: could not mount $DMG" >&2
  exit 1
fi

if [ ! -x "$MOUNT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
  echo "error: $APP_NAME.app/Contents/MacOS/$APP_NAME is missing from the mounted image" >&2
  exit 1
fi
if [ ! -L "$MOUNT/Applications" ]; then
  echo "error: the Applications shortcut is missing from the mounted image" >&2
  exit 1
fi
if [ ! -f "$MOUNT/Install.txt" ]; then
  echo "error: Install.txt is missing from the mounted image" >&2
  exit 1
fi

echo "==> $(du -h "$DMG" | cut -f1) $DMG"
echo "==> Done"
