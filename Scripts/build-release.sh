#!/usr/bin/env bash
#
# Build a signed release zip for distribution.
#
#   Scripts/build-release.sh 1.0.0
#
# Signing identity (defaults to ad-hoc):
#   SIGN_IDENTITY="SafariMRU Self-Signed" Scripts/build-release.sh 1.0.0
#
# Releases are signed with a self-signed "SafariMRU Self-Signed" certificate
# when it is available (locally in the login keychain, in CI imported from the
# MACOS_CERT_P12 secret). A stable signing identity keeps the macOS
# Accessibility / Screen Recording grants across updates; ad-hoc signatures
# change identity on every build and reset them. The app is still not
# notarized, so Gatekeeper asks the user to approve it once.
#
set -euo pipefail

VERSION="${1:?usage: Scripts/build-release.sh <version>}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
OUT="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/SafariMRU.app"

echo "==> Building SafariMRU $VERSION (identity: $SIGN_IDENTITY)"
xcodebuild \
  -project "$ROOT/SafariMRU/SafariMRU.xcodeproj" \
  -scheme SafariMRU \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="" \
  build

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | sed -n '1,8p'
echo "==> Designated requirement"
codesign -d -r- "$APP" 2>&1 | tail -2

mkdir -p "$OUT"
ZIP="$OUT/SafariMRU-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Wrote $ZIP"
