#!/bin/bash
# Builds a Developer ID signed, notarized and stapled dist/Backspin-VERSION.zip.
# Notary credentials: NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID (an App Store
# Connect API key), or else the notarytool keychain profile NOTARY_PROFILE (default "backspin-notary").
set -euo pipefail
cd "$(dirname "$0")/.."
export BACKSPIN_SIGN_IDENTITY="${BACKSPIN_SIGN_IDENTITY:-Developer ID Application}"
./build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Backspin.app/Contents/Info.plist)"

if [ -n "${NOTARY_KEY_ID:-}" ]; then
  CREDENTIALS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  CREDENTIALS=(--keychain-profile "${NOTARY_PROFILE:-backspin-notary}")
fi
ditto -c -k --sequesterRsrc --keepParent dist/Backspin.app dist/Backspin.zip
RESULT="$(xcrun notarytool submit dist/Backspin.zip "${CREDENTIALS[@]}" --wait --output-format json)"
ID="$(plutil -extract id raw -o - - <<<"$RESULT")"
if [ "$(plutil -extract status raw -o - - <<<"$RESULT")" != "Accepted" ]; then
  xcrun notarytool log "$ID" "${CREDENTIALS[@]}" >&2
  exit 1
fi

xcrun stapler staple dist/Backspin.app
spctl --assess --type execute --verbose=2 dist/Backspin.app
ZIP="dist/Backspin-$VERSION.zip"
rm dist/Backspin.zip
ditto -c -k --sequesterRsrc --keepParent dist/Backspin.app "$ZIP"
printf 'Notarized: %s\nsha256: %s\n' "$ZIP" "$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
