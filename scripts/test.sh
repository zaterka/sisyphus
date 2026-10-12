#!/usr/bin/env bash
#
# Runs the SisyphusCore test suite.
#
# SwiftPM is kept out of ~/Library: every cache, config and security path is redirected into the
# repository.
#
# Two toolchain layouts need different flags:
#   * Command Line Tools (no XCTest): swift-testing lives in "$(xcode-select -p)/Library/Developer/
#     Frameworks" and has to be pointed at explicitly, plus a workaround for a broken cross-import
#     overlay shipped in that framework.
#   * full Xcode (as on CI): everything ships inside the toolchain, so plain `swift test` is right
#     and the CLT workarounds would be noise (or worse, an extra framework search path).
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"

export CLANG_MODULE_CACHE_PATH="$PWD/.modcache/clang"
export SWIFT_MODULE_CACHE_PATH="$PWD/.modcache/swift"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH"

SWIFT_TEST_FLAGS=(
  --disable-sandbox
  --scratch-path .build
  --cache-path .spm-cache
  --config-path .spm-config
  --security-path .spm-security
)

if [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
  FW="$DEVELOPER_DIR/Library/Developer/Frameworks"

  if [ ! -d "$FW/Testing.framework" ]; then
    echo "error: Testing.framework not found at $FW" >&2
    echo "hint: install the Command Line Tools with 'xcode-select --install'" >&2
    exit 1
  fi

  # -disable-cross-import-overlays works around a packaging bug in the Command Line Tools: the
  # Testing.framework cross-import overlay (Testing.swiftcrossimport/Foundation.swiftoverlay) points
  # at _Testing_Foundation.framework, whose "Modules" symlink is dangling (there is no
  # _Testing_Foundation.swiftmodule), so every file that imports both Testing and Foundation fails
  # with "no such module '_Testing_Foundation'". Disabling overlays only drops swift-testing's
  # Foundation convenience integrations, which these tests do not use.
  swift test "${SWIFT_TEST_FLAGS[@]}" \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    "$@"
else
  echo "==> Tests with the full toolchain at $DEVELOPER_DIR"
  swift test "${SWIFT_TEST_FLAGS[@]}" "$@"
fi
