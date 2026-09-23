#!/bin/zsh
# Sovate — release build + optional DMG packaging (plan9 §4).
#
# Usage:
#   Scripts/build_release.sh            # build Release into ./build/
#   Scripts/build_release.sh --dmg      # also produce ./build/Sovate.dmg
#   Scripts/build_release.sh --sign     # sign with Developer ID (needs signing setup in project)
#   Scripts/build_release.sh --notarize # staple notarization (requires Apple ID credentials configured)
#
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
CONFIG="Release"
DMG=false
SIGN=false
NOTARIZE=false

for arg in "$@"; do
  case "$arg" in
    --dmg) DMG=true ;;
    --sign) SIGN=true ;;
    --notarize) NOTARIZE=true; SIGN=true ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

echo "==> Building $CONFIG"
xcodebuild -project sovate.xcodeproj -scheme sovate -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR/derived" build

APP="$BUILD_DIR/derived/Build/Products/$CONFIG/sovate.app"
test -d "$APP" || { echo "app missing at $APP"; exit 1; }

if $SIGN; then
  echo "==> Signing with Developer ID"
  codesign --force --deep --sign "Developer ID Application" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

if $NOTARIZE; then
  echo "==> Notarizing (requires notarytool credentials stored: xcrun notarytool store-credentials)"
  ZIP="$BUILD_DIR/sovate.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "sovate-notary" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

if $DMG; then
  echo "==> Creating DMG"
  STAGE="$BUILD_DIR/dmg-stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -sf /Applications "$STAGE/Applications"
  rm -f "$BUILD_DIR/Sovate.dmg"
  hdiutil create -volname "Sovate" -srcfolder "$STAGE" -ov -format UDZO "$BUILD_DIR/Sovate.dmg"
fi

echo "==> Done: $APP"
