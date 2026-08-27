#!/usr/bin/env bash
# Builds, signs, notarizes, staples, and publishes a 10x release.
#
#   scripts/release.sh 0.2.0              build and publish
#   scripts/release.sh 0.2.0 --no-publish build only, leave dist/ on disk
#
# Requires: APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID.
# The Sparkle private key comes from SPARKLE_ED_PRIVATE_KEY_FILE if set,
# otherwise from the login keychain, which is the local-developer path.
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [--no-publish]}"
PUBLISH="${2:-publish}"
SPARKLE_VERSION="2.9.6"   # must match Package.resolved; the tools and the framework are a pair
REPO="NextStep-AI-inc/10x"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="$(git rev-list --count HEAD)"
if [ "$BUILD_NUMBER" -le 1 ]; then
  echo "error: git rev-list --count HEAD returned $BUILD_NUMBER." >&2
  echo "The checkout is shallow. Sparkle compares CFBundleVersion, so every" >&2
  echo "release would claim to be build 1. Fetch full history and retry." >&2
  exit 1
fi

DIST="$ROOT/dist"
BUILD="$ROOT/.release-build"
rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD"

echo "==> Generating the project"
ruby scripts/generate_xcodeproj.rb

echo "==> Archiving $VERSION (build $BUILD_NUMBER)"
xcodebuild archive \
  -project 10x.xcodeproj \
  -scheme 10x \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$BUILD/10x.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$BUILD/10x.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$BUILD/export"

APP="$BUILD/export/10x.app"
[ -d "$APP" ] || { echo "error: export produced no app at $APP" >&2; exit 1; }

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# The ticket is written into the bundle, so the notarized zip is stale.
# Everything downstream must sign and measure this second archive, not that one.
ZIP="$DIST/10x-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Fetching Sparkle $SPARKLE_VERSION tools"
# Keep this pinned to the version in Package.resolved. Signing an archive with tools
# from a different Sparkle release than the framework the app embeds is a silent way
# to produce an appcast the shipped app refuses.
curl -fsSL -o "$BUILD/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
mkdir -p "$BUILD/sparkle"
tar -xJf "$BUILD/sparkle.tar.xz" -C "$BUILD/sparkle"

echo "==> Generating the appcast"
GENERATE_APPCAST="$BUILD/sparkle/bin/generate_appcast"
KEY_ARGS=()
if [ -n "${SPARKLE_ED_PRIVATE_KEY_FILE:-}" ]; then
  KEY_ARGS=(--ed-key-file "$SPARKLE_ED_PRIVATE_KEY_FILE")
fi
# The +expansion guard is required: macOS ships bash 3.2, where expanding an empty
# array under `set -u` is an unbound-variable error. Without it the local-developer
# path (no SPARKLE_ED_PRIVATE_KEY_FILE, key read from the login keychain) crashes here.
"$GENERATE_APPCAST" \
  ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  "$DIST"

grep -q 'sparkle:edSignature' "$DIST/appcast.xml" || {
  echo "error: the appcast carries no EdDSA signature. Sparkle will reject it." >&2
  exit 1
}

if [ "$PUBLISH" = "--no-publish" ]; then
  echo "==> Built $ZIP and $DIST/appcast.xml. Not publishing."
  exit 0
fi

echo "==> Publishing v$VERSION"
gh release create "v$VERSION" \
  "$ZIP" "$DIST/appcast.xml" \
  --repo "$REPO" \
  --title "10x $VERSION" \
  --generate-notes
