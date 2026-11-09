#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-v1.0.0}"
DERIVED_DATA_PATH="$ROOT_DIR/build/release"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/notchprompt.app"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
OUTPUT_DMG="$OUTPUT_DIR/notchprompt-${VERSION}-macos.dmg"
VOLUME_NAME="Notchprompt"

echo "==> Fetching the bundled Whisper model"
zsh "$ROOT_DIR/scripts/fetch-whisper-model.sh"

echo "==> Building Release app for ${VERSION}"
xcodebuild \
  -project "$ROOT_DIR/notchprompt.xcodeproj" \
  -scheme notchprompt \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at: $APP_PATH" >&2
  exit 1
fi

# CI builds do not have Developer ID certificates; apply ad-hoc signing so
# Gatekeeper treats the bundle as internally consistent.
echo "==> Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
rm -f "$OUTPUT_DMG"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Packaging $OUTPUT_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "==> Done"
echo "$OUTPUT_DMG"
