#!/bin/sh
# Builds a universal (Apple silicon + Intel) build/ScrollFlip.app, signed with your Apple
# Development certificate if you have one (so Accessibility permission survives rebuilds),
# otherwise ad-hoc.
set -eu
cd "$(dirname "$0")"
APP=build/ScrollFlip.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13" -o "build/ScrollFlip-$arch" ScrollFlip.swift
done
lipo -create build/ScrollFlip-arm64 build/ScrollFlip-x86_64 -output "$APP/Contents/MacOS/ScrollFlip"
rm build/ScrollFlip-arm64 build/ScrollFlip-x86_64
cp Info.plist "$APP/Contents/Info.plist"
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" --identifier local.scrollflip "$APP"
echo "Built $APP"
