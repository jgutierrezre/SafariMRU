#!/usr/bin/env bash
#
# Build an ad-hoc signed release zip for distribution.
#
#   Scripts/build-release.sh 1.0.0
#
# The app is signed with "-" (ad-hoc) because there is no Developer ID
# certificate in this project yet. Users must approve the app once via
# Gatekeeper; see README.md.
#
set -euo pipefail

VERSION="${1:?usage: Scripts/build-release.sh <version>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
OUT="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/SafariMRU.app"

echo "==> Building SafariMRU $VERSION"
xcodebuild \
  -project "$ROOT/SafariMRU/SafariMRU.xcodeproj" \
  -scheme SafariMRU \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  build

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | sed -n '1,6p'

mkdir -p "$OUT"
ZIP="$OUT/SafariMRU-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Wrote $ZIP"
