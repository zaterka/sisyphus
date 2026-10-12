#!/usr/bin/env bash
#
# Packages build/Sisyphus.app into build/Sisyphus.dmg: the app, an Applications shortcut, the install
# instructions and the licence, in a compressed read-only image that carries the app icon as its
# volume icon.
#
# The image is built in two steps rather than straight to UDZO. A compressed image is read-only, so
# the volume icon has to be written into a read-write (UDRW) copy first; `hdiutil convert` then packs
# that copy into the UDZO image that ships. The icon survives that conversion because convert copies
# .VolumeIcon.icns together with the volume's HFS+ catalog attributes, and `SetFile -a C` is what
# makes the Finder draw it.
#
# The result is verified by mounting it read-only and checking that the app binary, the Applications
# link, Install.txt, the licence and the volume's custom-icon attribute are really there, so a broken
# DMG fails here instead of on a user's Mac.
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
LICENSE_FILE="LICENSE"
APP_ICON="Resources/AppIcon.icns"
# The read-write intermediate. The pid keeps the name distinct per run, so two builds on one machine
# cannot collide over it, and a stale file left by a crashed earlier run is never reused. Leftovers
# from other runs are deliberately not swept here: another build may own them right now.
RW="$BUILD_DIR/$APP_NAME-rw.$$.dmg"
# Empty until the corresponding image is mounted, then a private mountpoint directory (see below).
# The two are kept apart so that a detach that failed can still be retried by the trap, instead of
# being overwritten by the next mount.
RW_MOUNT=""
RO_MOUNT=""
# Set to 1 only once the volume's custom-icon attribute has been applied, so the verification below
# knows whether that attribute is this run's responsibility or was skipped as merely cosmetic.
VOLUME_ICON_SET=0

if [ ! -d "$APP" ]; then
  echo "error: $APP not found — run ./scripts/build-app.sh first" >&2
  exit 1
fi
if [ ! -f "$LICENSE_FILE" ]; then
  echo "error: $LICENSE_FILE not found — the full GPL text must ship inside the disk image" >&2
  exit 1
fi
# build-app.sh already puts this file in the bundle and verifies it; checked again here because this
# script reads it straight from the source tree for the volume icon.
if [ ! -f "$APP_ICON" ]; then
  echo "error: $APP_ICON is missing — run ./scripts/make-logo.sh to regenerate it" >&2
  exit 1
fi

# Everything this script creates is torn down from one trap, and the trap runs for every exit path —
# a failed hdiutil, a failed assertion, or success. A leftover read-write image in build/ is merely
# untidy, but a still-attached volume is much worse: it holds a file handle on the image, it makes the
# next `hdiutil attach` of the same image mount somewhere unexpected, and on a build machine it can
# leak into later steps. The trap therefore never fails the script, hence `|| true` on every command:
# detaching a volume that is not mounted, or removing a file that is already gone, is not an error
# here — and a failing command in an EXIT trap under `set -e` would replace this script's real exit
# status (a successful build would report 1).
cleanup() {
  # Only what was actually created is touched: an empty variable means that mount never happened.
  for mountpoint in "$RW_MOUNT" "$RO_MOUNT"; do
    if [ -n "$mountpoint" ]; then
      hdiutil detach "$mountpoint" -force -quiet || true
      rmdir "$mountpoint" 2>/dev/null || true
    fi
  done
  rm -f "$RW" || true
}
trap cleanup EXIT

echo "==> Staging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# ditto keeps the bundle's metadata (and its signature) intact; cp -R can drop extended attributes.
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
# The licence sits in the image as well as inside the app bundle, so users who inspect the download
# before installing — or who keep only the image — still get the full text the GPL asks for.
cp "$LICENSE_FILE" "$STAGE/LICENSE"
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

Sisyphus is free software, released under the GNU General Public License, version 3
or later. The full licence text is in the LICENSE file next to this one. The source
code is at https://github.com/zaterka/sisyphus
TXT

# The size passed to `hdiutil create` is the upper bound the filesystem may grow to, so it has to be
# at least the staging folder. `du -sm` rounds up to whole MB; the 20 MB of headroom covers what the
# staging folder does not contain: the HFS+ catalog and journal, the .VolumeIcon.icns written later,
# and the slack a copy needs. An image created too small fails while copying into it, not while being
# created — a much more confusing failure than an image a few MB larger than strictly needed.
STAGE_MB="$(du -sm "$STAGE" | cut -f1)"
SIZE_MB=$((STAGE_MB + 20))

echo "==> Creating the read-write image ($RW, ${SIZE_MB}m)"
# Deliberately not -quiet: it also hides the reason a failed create failed, which is the one message
# worth having on a build machine.
if ! hdiutil create \
  -volname "$APP_NAME" \
  -fs HFS+ \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  -size "${SIZE_MB}m" \
  "$RW"; then
  echo "error: 'hdiutil create' failed, so the read-write image $RW was not written" >&2
  exit 1
fi

# A private mountpoint directory instead of the default /Volumes: the volume is named after the app,
# so /Volumes would either collide with an already-mounted Sisyphus image (hdiutil would then mount as
# "/Volumes/Sisyphus 1", a path this script cannot predict) or with the app bundle's own name. An
# explicit empty directory makes the mount path deterministic and private to this run.
RW_MOUNT="$(mktemp -d)"
if ! hdiutil attach "$RW" -nobrowse -readwrite -mountpoint "$RW_MOUNT"; then
  echo "error: could not mount the read-write image $RW" >&2
  exit 1
fi

# The icon is set here, on the read-write image, because a compressed image cannot be modified:
# `hdiutil convert` carries .VolumeIcon.icns and the volume's catalog attributes into the UDZO image.
cp "$APP_ICON" "$RW_MOUNT/.VolumeIcon.icns"
# -c icnC gives the file the type and creator HFS+ expects of an icon; -a C marks the *volume* as
# having a custom icon, which is the flag the Finder actually reads. Without either one the mounted
# image shows a plain white disk.
if command -v SetFile >/dev/null 2>&1; then
  echo "==> Setting the volume icon"
  SetFile -c icnC "$RW_MOUNT/.VolumeIcon.icns"
  SetFile -a C "$RW_MOUNT"
  VOLUME_ICON_SET=1
else
  # SetFile ships with the Xcode command line tools. On a developer machine a plain-volume image is
  # cosmetic; on a build machine it means the shipped release artifact silently lost its icon, so fail
  # there instead of publishing it. The verification below only demands the attribute when it was set.
  if [ -n "${CI:-}" ]; then
    echo "error: SetFile is not available on this build machine, so the volume icon cannot be set" >&2
    exit 1
  fi
  echo "warning: SetFile not found — skipping the volume icon" >&2
fi
# The icon and the catalog change live in the mounted filesystem's own cache until it is flushed, and
# a detach immediately after the writes can drop them.
sync

# Detaching can fail right after those writes: Spotlight and Finder hold the freshly written volume
# for a moment, while -force on a volume that is genuinely busy risks losing the very icon just
# written. So retry, but a bounded number of times — a volume that stays busy must not hang a release
# build — and only then force.
echo "==> Detaching the read-write image"
DETACHED=0
for _ in 1 2 3 4 5; do
  # -quiet on the attempts: five "resource busy" messages would be noise. The forced attempt below
  # deliberately keeps its output, because if that one fails the reason is worth having before the
  # convert against a still-mounted image fails on top of it.
  if hdiutil detach "$RW_MOUNT" -quiet; then
    DETACHED=1
    break
  fi
  sleep 1
done
if [ "$DETACHED" -ne 1 ]; then
  echo "==> Volume still busy; detaching with -force"
  if hdiutil detach "$RW_MOUNT" -force; then
    DETACHED=1
  fi
fi
# The mountpoint is forgotten only once the volume is really gone: if even the forced detach failed,
# the trap gets another chance to unmount it, and the verification below must not reuse its directory.
if [ "$DETACHED" -eq 1 ]; then
  rmdir "$RW_MOUNT" 2>/dev/null || true
  RW_MOUNT=""
fi

echo "==> Creating $DMG"
rm -f "$DMG"
# UDZO is the compressed read-only format Apple's own tools ship, so the download stays small and the
# user cannot accidentally modify the image. Deliberately not -quiet, for the same reason as create.
if ! hdiutil convert "$RW" -format UDZO -o "$DMG"; then
  echo "error: 'hdiutil convert' failed, so $DMG was not written" >&2
  exit 1
fi
# A convert that reported success but produced nothing would otherwise surface as a confusing `du`
# complaint on the last line, or as a missing file on the release page.
if [ ! -f "$DMG" ]; then
  echo "error: 'hdiutil convert' reported success but wrote no $DMG" >&2
  exit 1
fi

echo "==> Verifying $DMG"
if ! hdiutil verify "$DMG"; then
  echo "error: 'hdiutil verify' rejected $DMG" >&2
  exit 1
fi

RO_MOUNT="$(mktemp -d)"
if ! hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$RO_MOUNT"; then
  echo "error: could not mount $DMG" >&2
  exit 1
fi

if [ ! -x "$RO_MOUNT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
  echo "error: $APP_NAME.app/Contents/MacOS/$APP_NAME is missing from the mounted image" >&2
  exit 1
fi
if [ ! -L "$RO_MOUNT/Applications" ]; then
  echo "error: the Applications shortcut is missing from the mounted image" >&2
  exit 1
fi
if [ ! -f "$RO_MOUNT/Install.txt" ]; then
  echo "error: Install.txt is missing from the mounted image" >&2
  exit 1
fi
if [ ! -f "$RO_MOUNT/LICENSE" ]; then
  echo "error: the licence (LICENSE) is missing from the mounted image" >&2
  exit 1
fi
if [ ! -f "$RO_MOUNT/.VolumeIcon.icns" ]; then
  echo "error: the volume icon (.VolumeIcon.icns) is missing from the mounted image" >&2
  exit 1
fi
# The icon file alone is not enough: the Finder draws it only when the volume carries the "has custom
# icon" attribute, and that attribute lives in the volume's catalog rather than in the file, so it can
# only be read back through GetFileInfo. `GetFileInfo -a` prints the whole attribute alphabet with the
# set ones uppercased ("avbstClinmedz" once custom icon is set), hence the deliberate match on an
# uppercase C. Only checked when this run actually set the attribute — CI already fails hard when
# SetFile is missing, so a skipped icon is a developer machine's cosmetic choice, not a broken release.
if [ "$VOLUME_ICON_SET" = "1" ]; then
  # `|| true` because a GetFileInfo that cannot read the volume at all is one of the failures this
  # check exists to catch; the empty result then fails the case below with a readable message.
  VOLUME_ATTRS="$(GetFileInfo -a "$RO_MOUNT" || true)"
  case "$VOLUME_ATTRS" in
    *C*) ;;
    *)
      echo "error: the mounted volume lost its custom-icon attribute (GetFileInfo -a: $VOLUME_ATTRS)" >&2
      exit 1
      ;;
  esac
fi

echo "==> $(du -h "$DMG" | cut -f1) $DMG"
echo "==> Done"
