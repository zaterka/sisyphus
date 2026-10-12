#!/usr/bin/env bash
#
# Builds the release executable and assembles build/Sisyphus.app.
#
# SwiftPM is kept out of ~/Library through local cache/config/security paths, and the app bundle is
# signed ad-hoc as the very last step (nothing in the bundle is touched after codesign).
#
# Environment:
#   UNIVERSAL=1     also build the other architecture and merge both slices with lipo
#   APP_VERSION=x   CFBundleShortVersionString of the assembled bundle
#   BUILD_NUMBER=n  CFBundleVersion of the assembled bundle
#
# APP_VERSION and BUILD_NUMBER only rewrite the *bundle copy* of Resources/Info.plist; the source
# plist keeps its checked-in values.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Sisyphus"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
BINARY="$CONTENTS/MacOS/$APP_NAME"
UNIVERSAL="${UNIVERSAL:-0}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

# The deployment target comes from the bundle metadata, so the two cannot drift apart. The universal
# pass needs it explicitly: without `--triple` SwiftPM would build twice for the host's macOS.
MACOS_MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
ARCHES=(arm64 x86_64)

export CLANG_MODULE_CACHE_PATH="$PWD/.modcache/clang"
export SWIFT_MODULE_CACHE_PATH="$PWD/.modcache/swift"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH"

SWIFT_FLAGS=(
  --disable-sandbox
  --scratch-path .build
  --cache-path .spm-cache
  --config-path .spm-config
  --security-path .spm-security
)

# Where SwiftPM puts the executable built for one triple. Asking SwiftPM beats guessing at .build.
bin_path_for_triple() {
  swift build -c release --product "$APP_NAME" --triple "$1" "${SWIFT_FLAGS[@]}" --show-bin-path
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$CONTENTS/Info.plist"
}

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Building $APP_NAME (release, universal: ${ARCHES[*]})"
  SLICES=()
  for arch in "${ARCHES[@]}"; do
    TRIPLE="$arch-apple-macosx$MACOS_MINIMUM"
    echo "==> Building $APP_NAME for $TRIPLE"
    swift build -c release --product "$APP_NAME" --triple "$TRIPLE" "${SWIFT_FLAGS[@]}"
    SLICE="$(bin_path_for_triple "$TRIPLE")/$APP_NAME"
    if [ ! -x "$SLICE" ]; then
      echo "error: no $arch binary at $SLICE" >&2
      exit 1
    fi
    SLICES+=("$SLICE")
  done

  echo "==> Merging slices with lipo"
  lipo -create -output "$BINARY" "${SLICES[@]}"
else
  echo "==> Building $APP_NAME (release, native)"
  swift build -c release --product "$APP_NAME" "${SWIFT_FLAGS[@]}"
  BIN="$(swift build -c release --product "$APP_NAME" "${SWIFT_FLAGS[@]}" --show-bin-path)/$APP_NAME"
  if [ ! -x "$BIN" ]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
  fi
  cp "$BIN" "$BINARY"
fi

ARCHITECTURES="$(lipo -archs "$BINARY")"
echo "==> Architectures: $ARCHITECTURES"
if [ "$UNIVERSAL" = "1" ]; then
  for arch in "${ARCHES[@]}"; do
    case " $ARCHITECTURES " in
      *" $arch "*) ;;
      *)
        echo "error: $BINARY has no $arch slice (lipo -archs: $ARCHITECTURES)" >&2
        exit 1
        ;;
    esac
  done
fi

echo "==> Assembling $APP"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Versions go in before signing, so the signature covers them.
if [ -n "$APP_VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"
fi
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
fi
echo "==> Version: $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion))"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Signature"
codesign -dv --verbose=2 "$APP" 2>&1 || true

# Read-only checks after signing: the bundle must carry the requested versions.
if [ -n "$APP_VERSION" ] && [ "$(plist_value CFBundleShortVersionString)" != "$APP_VERSION" ]; then
  echo "error: CFBundleShortVersionString is not $APP_VERSION" >&2
  exit 1
fi
if [ -n "$BUILD_NUMBER" ] && [ "$(plist_value CFBundleVersion)" != "$BUILD_NUMBER" ]; then
  echo "error: CFBundleVersion is not $BUILD_NUMBER" >&2
  exit 1
fi

echo "==> Done: $APP"
