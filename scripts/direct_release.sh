#!/usr/bin/env bash
#
# Build a Developer ID-signed, notarized Ding for download outside the Mac App Store and attach it to a GitHub Release.
# Build box only (it needs the App Store Connect API key); run through `make github-release`, which sets the environment.
#
#   VERSION=1.0.77 BUILD=77 scripts/direct_release.sh
#
# Steps: archive in Release with the stamped version, export with make/ExportOptions-developer-id.plist, zip, notarize
# (notarytool with the API key, waiting for Apple's verdict), staple the ticket, re-zip, verify with Gatekeeper's own
# check, then `gh release create` (or upload over an existing release for that tag).
set -euo pipefail

: "${VERSION:?VERSION is required (1.0.<build>)}"
: "${BUILD:?BUILD is required (the commit count)}"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_FILEPATH:?}"

out=build/direct
archive="$out/Ding.xcarchive"
zip="$out/Ding-$VERSION.zip"
mkdir -p "$out"
rm -f "$zip"

echo "→ archiving Ding $VERSION (build $BUILD)"
xcodebuild archive -quiet \
  -project Ding.xcodeproj -scheme Ding -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  CURRENT_PROJECT_VERSION="$BUILD" MARKETING_VERSION="$VERSION" \
  DING_BUNDLE_ID="${BUNDLE_ID:-blue.luci.Ding}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_FILEPATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "→ exporting with Developer ID"
rm -rf "$out/export"
xcodebuild -exportArchive -quiet \
  -archivePath "$archive" -exportPath "$out/export" \
  -exportOptionsPlist make/ExportOptions-developer-id.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_FILEPATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
app="$out/export/Ding.app"
codesign --verify --deep --strict "$app"

echo "→ notarizing (Apple usually takes a few minutes)"
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --wait \
  --key "$ASC_KEY_FILEPATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
rm -f "$out/notarize.zip"

echo "→ stapling and checking"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$zip"

tag="v$VERSION"
notes="Ding $VERSION for macOS 14 or later, signed and notarized: unzip, move Ding.app to Applications and open it. This build does not update itself; the Mac App Store version does."
if gh release view "$tag" >/dev/null 2>&1; then
  echo "→ uploading to the existing release $tag"
  gh release upload "$tag" "$zip" --clobber
else
  echo "→ creating release $tag"
  gh release create "$tag" "$zip" --title "Ding $VERSION" --notes "$notes" --target "$(git rev-parse HEAD)"
fi
echo "✓ Ding $VERSION notarized and attached to release $tag"
