#!/usr/bin/env bash
# Builds build/NotchIsland.app (Apple Silicon only).
# Optional: SIGN_IDENTITY="Apple Development: …" ./scripts/build.sh — keeps macOS permissions across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "NotchIsland supports Apple Silicon Macs only." >&2
  exit 1
fi

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/NotchIsland"
APP=build/NotchIsland.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

TIMESTAMP=--timestamp=none
[[ "${SIGN_IDENTITY:-}" == Developer\ ID* ]] && TIMESTAMP=--timestamp
codesign --force --options runtime "$TIMESTAMP" \
  --entitlements Resources/NotchIsland.entitlements \
  --sign "${SIGN_IDENTITY:--}" "$APP"

echo "✓ $APP"
