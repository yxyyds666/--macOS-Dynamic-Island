#!/bin/bash
# Builds Yu灵动岛 in Release and packages a signed .app into ./dist
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Release)"
xcodebuild \
  -project YuLingDongDao.xcodeproj \
  -scheme YuLingDongDao \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build

APP="build/DerivedData/Build/Products/Release/Yu灵动岛.app"

echo "==> Packaging into dist/"
rm -rf dist
mkdir -p dist
cp -R "$APP" dist/

echo "==> Checking bundled MediaRemote adapter"
ADAPTER_DST="dist/Yu灵动岛.app/Contents/Resources/MediaRemoteAdapter"
test -f "$ADAPTER_DST/mediaremote-adapter.pl"
test -d "$ADAPTER_DST/MediaRemoteAdapter.framework"

echo "==> Ad-hoc signing (enables dlopen of private MediaRemote framework)"
codesign --force --deep \
  --sign - \
  --entitlements YuLingDongDao/Entitlements.plist \
  "dist/Yu灵动岛.app"

codesign --verify --verbose "dist/Yu灵动岛.app"

echo "==> Done: dist/Yu灵动岛.app"
