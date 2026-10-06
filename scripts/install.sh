#!/usr/bin/env bash
# Builds NotchIsland and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
  exit 1
fi

./scripts/build.sh
pkill -x NotchIsland 2>/dev/null || true
rm -rf /Applications/NotchIsland.app
cp -R build/NotchIsland.app /Applications/
open /Applications/NotchIsland.app
echo "✓ NotchIsland installed to /Applications"
