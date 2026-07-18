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

echo "==> Bundling MediaRemote adapter (perl script + helper framework)"
# The now-playing data on macOS 15.4+ is only reachable through a system binary
# that carries the MediaRemote entitlement. We ship the perl adapter + helper
# framework and invoke them via /usr/bin/perl at runtime.
ADAPTER_SRC="Yu灵动岛/Resources/MediaRemoteAdapter"
ADAPTER_DST="dist/Yu灵动岛.app/Contents/Resources/MediaRemoteAdapter"
mkdir -p "$ADAPTER_DST"
cp "$ADAPTER_SRC/mediaremote-adapter.pl" "$ADAPTER_DST/"
cp -R "$ADAPTER_SRC/MediaRemoteAdapter.framework" "$ADAPTER_DST/"
# Re-apply the ad-hoc signature the perl DynaLoader requires.
codesign --force --deep --sign - "$ADAPTER_DST/MediaRemoteAdapter.framework"

echo "==> Ad-hoc signing (enables dlopen of private MediaRemote framework)"
codesign --force --deep \
  --sign - \
  --entitlements YuLingDongDao/Entitlements.plist \
  "dist/Yu灵动岛.app"

codesign --verify --verbose "dist/Yu灵动岛.app"

echo "==> Done: dist/Yu灵动岛.app"
