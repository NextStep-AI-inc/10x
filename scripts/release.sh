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

# SUFeedURL points at releases/latest/download/appcast.xml, and GitHub picks Latest by
# date and semver. A prerelease tag published without --prerelease therefore becomes
# Latest and every installed 10x is offered it on its next check, correctly signed and
# notarized, with nothing looking wrong at any step. Refuse the shape outright: shipping
# a channel is a deliberate feature, not something a tag suffix should do by accident.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: '$VERSION' is not a plain X.Y.Z version." >&2
  echo "Prerelease and build-metadata tags are refused because the update feed reads" >&2
  echo "releases/latest, so publishing one would offer it to every stable install." >&2
  echo "Adding a prerelease channel means giving it its own feed, not relaxing this." >&2
  exit 1
fi
PUBLISH="${2:-publish}"
# Read from Package.resolved rather than duplicated here: signing an archive with tools
# from a different Sparkle release than the framework the app embeds is a silent way to
# produce an appcast the shipped app refuses. A literal here drifts the moment the
# package is bumped.
SPARKLE_VERSION="$(sed -n 's/.*"version" : "\([0-9][^"]*\)".*/\1/p' \
  10x.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | head -1)"
[ -n "$SPARKLE_VERSION" ] || { echo "error: could not read the Sparkle version from Package.resolved" >&2; exit 1; }
# Digest of the pinned release asset. Update alongside Package.resolved; recompute with
#   curl -fsSL <asset-url> | shasum -a 256
# A case, not an associative array: macOS ships bash 3.2, where `declare -A` does not
# exist. This script has already been bitten once by assuming bash 4 semantics.
case "$SPARKLE_VERSION" in
  2.9.6) SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192" ;;
  *)     SPARKLE_TARBALL_SHA256="" ;;
esac
if [ -z "$SPARKLE_TARBALL_SHA256" ]; then
  echo "error: no pinned digest for Sparkle $SPARKLE_VERSION." >&2
  echo "Package.resolved moved without the tools pin following it. Add the digest to" >&2
  echo "SPARKLE_TARBALL_SHA256_BY_VERSION in this script." >&2
  exit 1
fi
REPO="NextStep-AI-inc/10x"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="$(git rev-list --count HEAD)"

# A shallow clone makes the count meaningless. Ask git directly rather than inferring
# it from a low number: fetch-depth 2 sails past a `-le 1` check.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "error: the checkout is shallow, so git rev-list --count HEAD is meaningless." >&2
  echo "Sparkle compares CFBundleVersion. Fetch full history (fetch-depth: 0)." >&2
  exit 1
fi

# The count is not monotonic across branches. Releasing a lower CFBundleVersion than the
# one already advertised strands every install: Sparkle sees no upgrade and says nothing.
PUBLISHED_BUILD="$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
  | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<.*/\1/p' | head -1 || true)"
if [ -n "$PUBLISHED_BUILD" ] && [ "$BUILD_NUMBER" -le "$PUBLISHED_BUILD" ]; then
  echo "error: this build is $BUILD_NUMBER but the live feed already advertises $PUBLISHED_BUILD." >&2
  echo "Sparkle compares CFBundleVersion, so publishing this would strand every install" >&2
  echo "on the newer build with no upgrade offered and no error shown." >&2
  exit 1
fi

DIST="$ROOT/dist"
BUILD="$ROOT/.release-build"
rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD"

echo "==> Generating the project"
# The generator asserts an exact xcodeproj version, because each release ships
# different default build settings that feed every object UUID.
#
# Deliberately not bundler: the runner's system bundler is 1.17.2, which cannot run
# on Ruby 3.2+ at all (it calls String#untaint, removed in 3.2), and the lockfile
# names that same version. Installing the pinned gem and activating it with
# Kernel#gem before the script's own `require` is smaller and has no such trap.
XCODEPROJ_VERSION=1.27.0
if ! ruby -e "gem 'xcodeproj', '$XCODEPROJ_VERSION'" >/dev/null 2>&1; then
  echo "    installing xcodeproj $XCODEPROJ_VERSION"
  # Deliberately no sudo fallback: this machine holds the Developer ID key on the local
  # path, and a compromised or typosquatted gem should not be able to ask for root.
  gem install xcodeproj -v "$XCODEPROJ_VERSION" --no-document --user-install
fi
ruby -e "gem 'xcodeproj', '$XCODEPROJ_VERSION'; load 'scripts/generate_xcodeproj.rb'"

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

# Verify before extracting: the binary inside is handed --ed-key-file, i.e. the release
# signing key. Release assets are immutable, so a pinned digest is a fair guard.
ACTUAL_SHA="$(shasum -a 256 "$BUILD/sparkle.tar.xz" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$SPARKLE_TARBALL_SHA256" ]; then
  echo "error: Sparkle $SPARKLE_VERSION tarball digest mismatch." >&2
  echo "  expected $SPARKLE_TARBALL_SHA256" >&2
  echo "  actual   $ACTUAL_SHA" >&2
  echo "Refusing to run an unverified binary that is about to be given the signing key." >&2
  exit 1
fi
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

# The two traps this pipeline has actually hit were both "the appcast parses and points
# somewhere wrong", so check what it says rather than only that it exists. Each of these
# would otherwise publish an artifact that installs fine and can never be updated from.
APPCAST="$DIST/appcast.xml"

grep -q 'sparkle:edSignature' "$APPCAST" || {
  echo "error: the appcast carries no EdDSA signature. Every client would reject it." >&2
  exit 1
}

# A signature made with the wrong key parses and publishes, then is silently rejected
# by every install. This compares the key that WOULD sign against the one the shipped
# app trusts.
#
# Only meaningful on the local path. generate_keys -p reads the login keychain, but CI
# signs with SPARKLE_ED_PRIVATE_KEY_FILE, a different source entirely, so comparing the
# two there is not a weaker check, it is a wrong one: it failed a release whose
# signature was correct. Where the file is the source, the file is the authority.
if [ -n "${SPARKLE_ED_PRIVATE_KEY_FILE:-}" ]; then
  echo "    note: signing from a key file, so the keychain/plist match does not apply."
else
  PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" App/Info.plist)"
  SIGNING_KEY="$("$BUILD/sparkle/bin/generate_keys" -p 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -z "$SIGNING_KEY" ]; then
    echo "    note: no keychain signing key found, so the match is unchecked."
  elif [ "$SIGNING_KEY" != "$PUBLIC_KEY" ]; then
    echo "error: the keychain signing key does not match SUPublicEDKey in App/Info.plist." >&2
    echo "The appcast would publish cleanly and be rejected by every installed copy." >&2
    exit 1
  fi
fi

grep -q "releases/download/v$VERSION/" "$APPCAST" || {
  echo "error: enclosure does not point at releases/download/v$VERSION/." >&2
  echo "The feed is served from latest/download, so a wrong prefix downloads the" >&2
  echo "wrong artifact or nothing at all." >&2
  exit 1
}

grep -q "<sparkle:shortVersionString>$VERSION<" "$APPCAST" || {
  echo "error: appcast advertises a different version than $VERSION." >&2
  exit 1
}

# Closes the loop on the shallow-clone class: proves the CFBundleVersion override
# actually reached the built app rather than silently defaulting.
grep -q "<sparkle:version>$BUILD_NUMBER<" "$APPCAST" || {
  echo "error: appcast advertises a different build than $BUILD_NUMBER." >&2
  echo "The CURRENT_PROJECT_VERSION override did not reach the built app." >&2
  exit 1
}

if [ "$PUBLISH" = "--no-publish" ]; then
  echo "==> Built $ZIP and $DIST/appcast.xml. Not publishing."
  exit 0
fi

echo "==> Publishing v$VERSION"
# --verify-tag: without it gh creates a missing tag at the DEFAULT BRANCH head, not the
# commit that was built, so the release would ship code from somewhere else.
gh release create "v$VERSION" \
  "$ZIP" "$APPCAST" \
  --verify-tag \
  --repo "$REPO" \
  --title "10x $VERSION" \
  --generate-notes
