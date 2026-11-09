#!/bin/zsh
# Builds Release, signs it with your Apple Development identity and installs to
# /Applications. A stable signature keeps the microphone permission between builds.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
team="${NOTCHPROMPT_TEAM:?Set NOTCHPROMPT_TEAM to your Apple Developer team ID}"
zsh scripts/fetch-whisper-model.sh
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

xcodebuild -project notchprompt.xcodeproj -scheme notchprompt -configuration Release \
  -derivedDataPath "$out" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$team" \
  build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'

pkill -x notchprompt || true
rm -rf /Applications/notchprompt.app
cp -R "$out/Build/Products/Release/notchprompt.app" /Applications/notchprompt.app
codesign --verify --deep --strict /Applications/notchprompt.app
open /Applications/notchprompt.app
echo "Installed /Applications/notchprompt.app"
