#!/usr/bin/env bash
# upload_testflight.sh — one-shot regen → archive → export → upload to
# App Store Connect for the chosen platform.
#
# Usage:
#   scripts/upload_testflight.sh ios
#   scripts/upload_testflight.sh macos
#
# Requirements:
#   - App Store Connect API key (.p8) at
#     ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   - ASC_KEY_ID and ASC_ISSUER_ID baked in below (these are public
#     identifiers, not secrets — the .p8 file is the secret).
#   - For macOS uploads: an Apple Distribution + Mac Installer
#     Distribution ("3rd Party Mac Developer Installer") identity in
#     the keychain — the installer cert signs the .pkg. Created
#     2026-07-09 via the ASC API (expires 2027-07-10); recreate the
#     same way if it lapses. The archive/export steps authenticate to
#     ASC with the same API key as the upload step, so no Apple ID
#     needs to be signed in to Xcode.
#
# What it does:
#   1. Re-runs scripts/generate_xcodeproj.rb so CURRENT_PROJECT_VERSION
#      gets a fresh YYMMDDHHMM timestamp (ASC rejects re-uploads with
#      the same build number).
#   2. xcodebuild archive into /tmp/<scheme>.xcarchive.
#   3. xcodebuild -exportArchive with the per-platform ExportOptions
#      plist into /tmp/<scheme>-export/.
#   4. xcrun altool --upload-app to App Store Connect.
#
# Processing on ASC typically takes 10–30 min before the build shows
# up in TestFlight.

set -euo pipefail

ASC_KEY_ID="JVHQ9YC2VR"
ASC_ISSUER_ID="69a6de8d-152f-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

PLATFORM="${1:-}"
case "$PLATFORM" in
    ios|macos) ;;
    *)
        cat >&2 <<EOF
Usage: $0 ios|macos
  ios   – Archive + upload TerraCognita-iOS for iOS App Store.
  macos – Archive + upload TerraCognita-macOS for Mac App Store.
EOF
        exit 1
        ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Mirror all output to a per-platform log so callers don't need to
# `| tee` themselves (the outer pipe loses our exit code unless they
# remember `set -o pipefail`). Process substitution keeps the
# script's own exit status intact.
LOG_FILE="/tmp/upload_${PLATFORM}.log"
exec > >(tee "$LOG_FILE") 2>&1

# Final-status trap: makes success/failure unambiguous even if the
# build log scrolls past the screen.
trap 'rc=$?; if [ $rc -eq 0 ]; then echo "✓ DONE — upload submitted (log: $LOG_FILE)"; else echo "✗ FAILED (exit $rc) — see $LOG_FILE" >&2; fi' EXIT

# 1) Regenerate the project and compute the build number.
#
# The number is a fresh YYMMDDHHMM timestamp so each upload is
# strictly greater than the last (ASC rejects re-used build numbers).
# It is NOT baked into the project file — generate_xcodeproj.rb emits
# a static placeholder version, and we inject the real number at
# archive time via an xcodebuild setting override (step 2). That keeps
# the committed project file identical across uploads, so a release
# never produces project churn to commit. The regen itself is
# deterministic (stable UUIDs), so it's a no-op on a clean tree.
BUILD_NUMBER="$(date +%y%m%d%H%M)"
echo "==> [1/4] Regenerating project; build number $BUILD_NUMBER (injected at archive)…"
if [ "$PLATFORM" = "macos" ]; then
    MAC_SIGN=1 ruby scripts/generate_xcodeproj.rb
else
    ruby scripts/generate_xcodeproj.rb
fi

# 2) Archive.
if [ "$PLATFORM" = "ios" ]; then
    SCHEME="TerraCognita-iOS"
    DESTINATION="generic/platform=iOS"
    EXPORT_OPTS="$ROOT/scripts/ExportOptions-iOS.plist"
    UPLOAD_TYPE="ios"
else
    SCHEME="TerraCognita-macOS"
    DESTINATION="generic/platform=macOS"
    EXPORT_OPTS="$ROOT/scripts/ExportOptions-macOS.plist"
    UPLOAD_TYPE="macos"
fi

ARCHIVE_PATH="/tmp/${SCHEME}.xcarchive"
EXPORT_DIR="/tmp/${SCHEME}-export"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "==> [2/4] Archiving $SCHEME → $ARCHIVE_PATH …"
xcodebuild archive \
    -project TerraCognita.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    | xcbeautify --quiet 2>/dev/null || \
xcodebuild archive \
    -project TerraCognita.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# 3) Export.
echo "==> [3/4] Exporting → $EXPORT_DIR …"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

# 4) Upload.
echo "==> [4/4] Uploading to App Store Connect…"
if [ "$PLATFORM" = "ios" ]; then
    PAYLOAD="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
else
    # macOS app-store export produces a signed .pkg
    PAYLOAD="$(find "$EXPORT_DIR" -name '*.pkg' | head -1)"
fi

if [ -z "${PAYLOAD:-}" ] || [ ! -f "$PAYLOAD" ]; then
    echo "ERROR: no upload payload found under $EXPORT_DIR" >&2
    ls -la "$EXPORT_DIR" >&2 || true
    exit 1
fi

echo "    Payload: $PAYLOAD"
xcrun altool --upload-app \
    -f "$PAYLOAD" \
    -t "$UPLOAD_TYPE" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

echo ""
echo "✓ Upload submitted. Processing on ASC typically takes 10–30 min."
echo "  Check status at https://appstoreconnect.apple.com → TestFlight."
