#!/usr/bin/env bash
#
# Renders docs/sisyphus.gif from the real scene code.
#
# `--export-gif` is a hidden CLI mode of the app binary, so the GIF comes from the same
# SceneRenderer, sprites and state machine the panel uses. The scenario is deterministic (fixed
# 20 fps clock, no timers, no window server session), so re-running this reproduces the same file.
#
# Usage: ./scripts/make-gif.sh [output path]   (default: docs/sisyphus.gif)
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT="${1:-docs/sisyphus.gif}"
mkdir -p "$(dirname "$OUTPUT")"

./scripts/build-app.sh
./build/Sisyphus.app/Contents/MacOS/Sisyphus --export-gif "$OUTPUT"

echo "==> $(du -h "$OUTPUT" | cut -f1) $OUTPUT"
