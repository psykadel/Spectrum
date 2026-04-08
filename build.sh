#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/Spectrum.xcodeproj"
SCHEME_NAME="Spectrum"
APP_NAME="Spectrum.app"
DMG_NAME="Spectrum.dmg"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
ARTIFACTS_DIR="$ROOT_DIR/build/Artifacts"
APP_BUILD_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
APP_ARTIFACT_PATH="$ARTIFACTS_DIR/$APP_NAME"
DMG_STAGING_DIR="$ARTIFACTS_DIR/dmg-root"
DMG_PATH="$ARTIFACTS_DIR/$DMG_NAME"

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
}

install_artifact_app() {
  /bin/rm -rf "$APP_ARTIFACT_PATH"
  /usr/bin/ditto "$APP_BUILD_PATH" "$APP_ARTIFACT_PATH"
}

build_dmg() {
  /bin/rm -rf "$DMG_STAGING_DIR"
  /bin/mkdir -p "$DMG_STAGING_DIR"
  /usr/bin/ditto "$APP_ARTIFACT_PATH" "$DMG_STAGING_DIR/$APP_NAME"
  /bin/ln -s /Applications "$DMG_STAGING_DIR/Applications"
  /bin/rm -f "$DMG_PATH"

  hdiutil create \
    -volname "Spectrum" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

  /bin/rm -rf "$DMG_STAGING_DIR"
}

/bin/mkdir -p "$ARTIFACTS_DIR"
build_app
install_artifact_app
build_dmg

APP_URL="file://$APP_ARTIFACT_PATH"
DMG_URL="file://$DMG_PATH"

echo
echo "Build succeeded:"
echo "App: $APP_ARTIFACT_PATH"
echo "DMG: $DMG_PATH"
echo
echo "Links:"
echo "$APP_URL"
echo "$DMG_URL"
