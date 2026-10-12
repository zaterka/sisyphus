#!/usr/bin/env bash
#
# Renders the logo art into the two forms that ship: docs/logo.png (the README header image) and
# Resources/AppIcon.icns (the app icon, and the DMG's volume icon).
#
# The art lives in Sources/Sisyphus/Scene/LogoArt.swift and is rendered by the binary's hidden
# `--export-logo <directory>` mode, so the image, the iconset and the code cannot drift apart. This
# script then checks every rep's pixel size with sips, packs the iconset with iconutil, round-trips
# the .icns back through iconutil to prove it really holds all ten reps, and only then copies the
# two results into the tree — a broken icon never reaches Resources/ or docs/.
#
# It builds the executable directly instead of calling build-app.sh: that script asserts
# Resources/AppIcon.icns exists, which is the file this one produces, so calling it here would be a
# bootstrap cycle.
#
# Both outputs are committed: the release workflow does not run this script, it ships what is in the
# repository.
set -euo pipefail

cd "$(dirname "$0")/.."

LOGO="docs/logo.png"
ICNS="Resources/AppIcon.icns"
WORK="build/logo"
ICONSET="$WORK/AppIcon.iconset"
ROUNDTRIP="$WORK/roundtrip.iconset"

SWIFT_FLAGS=(
  --disable-sandbox
  --scratch-path .build
  --cache-path .spm-cache
  --config-path .spm-config
  --security-path .spm-security
)

export CLANG_MODULE_CACHE_PATH="$PWD/.modcache/clang"
export SWIFT_MODULE_CACHE_PATH="$PWD/.modcache/swift"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH"

# The ten reps iconutil wants, with the pixel size each one must have.
REPS=(
  "icon_16x16.png 16 16"
  "icon_16x16@2x.png 32 32"
  "icon_32x32.png 32 32"
  "icon_32x32@2x.png 64 64"
  "icon_128x128.png 128 128"
  "icon_128x128@2x.png 256 256"
  "icon_256x256.png 256 256"
  "icon_256x256@2x.png 512 512"
  "icon_512x512.png 512 512"
  "icon_512x512@2x.png 1024 1024"
)

# A rep is an exact whole-number scale of the 64×64 or 16×16 grid, so a wrong size here means the art
# and the iconset have drifted apart: check that before packing, not after.
assert_size() { # file width height
  local file="$1" want="$2x$3" got
  got="$(sips -g pixelWidth -g pixelHeight "$file" \
    | awk -F': ' '/pixelWidth:/{w=$2} /pixelHeight:/{h=$2} END{print w"x"h}')"
  if [ "$got" != "$want" ]; then
    echo "error: $file is $got, expected $want" >&2
    exit 1
  fi
}

echo "==> Building Sisyphus (release)"
swift build -c release --product Sisyphus "${SWIFT_FLAGS[@]}"
BIN="$(swift build -c release --product Sisyphus "${SWIFT_FLAGS[@]}" --show-bin-path)/Sisyphus"
if [ ! -x "$BIN" ]; then
  echo "error: the built binary is not at $BIN" >&2
  exit 1
fi

echo "==> Rendering the logo into $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"
"$BIN" --export-logo "$WORK"

echo "==> Checking the rendered sizes"
assert_size "$WORK/logo.png" 512 512
for rep in "${REPS[@]}"; do
  # shellcheck disable=SC2086 # the entry is "name width height": splitting it is the point
  set -- $rep
  assert_size "$ICONSET/$1" "$2" "$3"
done

echo "==> Packing $ICNS"
iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"
if [ ! -f "$WORK/AppIcon.icns" ]; then
  echo "error: iconutil wrote no icns" >&2
  exit 1
fi

# Round-trip it: iconutil silently drops reps it does not like, and an .icns that cannot be read
# back is not an icon.
echo "==> Reading the icns back"
rm -rf "$ROUNDTRIP"
iconutil -c iconset "$WORK/AppIcon.icns" -o "$ROUNDTRIP"
for rep in "${REPS[@]}"; do
  # shellcheck disable=SC2086 # the entry is "name width height": splitting it is the point
  set -- $rep
  if [ ! -f "$ROUNDTRIP/$1" ]; then
    echo "error: $1 is missing from the packed icns" >&2
    exit 1
  fi
done

echo "==> Installing $LOGO and $ICNS"
mkdir -p "$(dirname "$LOGO")" "$(dirname "$ICNS")"
cp "$WORK/logo.png" "$LOGO"
cp "$WORK/AppIcon.icns" "$ICNS"

echo "==> $(du -h "$LOGO" | cut -f1) $LOGO"
echo "==> $(du -h "$ICNS" | cut -f1) $ICNS"
echo "==> Done"
