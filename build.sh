#!/bin/sh
# Builds a universal (Apple silicon + Intel) dist/Backspin.app.
#
# The version is BACKSPIN_VERSION (releases set it from the tag), otherwise the latest tag.
# Signs with BACKSPIN_SIGN_IDENTITY if set, using the hardened runtime and a secure timestamp
# as notarization requires (see scripts/release.sh). Otherwise signs with your Apple Development
# certificate if you have one (so Accessibility permission survives rebuilds), or ad-hoc.
set -eu
cd "$(dirname "$0")"
VERSION="${BACKSPIN_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
APP=dist/Backspin.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
    swift build -c release --arch "$arch"
    cp "$(swift build -c release --arch "$arch" --show-bin-path)/Backspin" "dist/Backspin-$arch"
done
lipo -create dist/Backspin-arm64 dist/Backspin-x86_64 -output "$APP/Contents/MacOS/Backspin"
rm dist/Backspin-arm64 dist/Backspin-x86_64
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" \
    -c "Add :CFBundleVersion string $VERSION" "$APP/Contents/Info.plist"
if [ -n "${BACKSPIN_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$BACKSPIN_SIGN_IDENTITY" "$APP"
else
    IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
    codesign --force --sign "${IDENTITY:--}" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP $VERSION"
