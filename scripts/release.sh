#!/usr/bin/env bash
# Builds a Developer ID signed, Apple-notarized build/NotchIsland.zip.
#
# One-time setup:
#   1. Xcode → Settings → Accounts → Manage Certificates → + → "Developer ID Application"
#   2. xcrun notarytool store-credentials notchisland --apple-id <apple-id> --team-id <TEAM_ID>
#      (asks for an app-specific password from appleid.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$IDENTITY" ]]; then
  echo "No \"Developer ID Application\" certificate found in the keychain (see setup above)." >&2
  exit 1
fi
PROFILE="${NOTARY_PROFILE:-notchisland}"
APP=build/NotchIsland.app
ZIP=build/NotchIsland.zip

SIGN_IDENTITY="$IDENTITY" ./scripts/build.sh

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
echo "✓ $ZIP (signed with $IDENTITY, notarized)"
