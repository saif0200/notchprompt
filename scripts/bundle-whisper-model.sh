#!/bin/zsh
# Xcode build phase: copies the Whisper model into the app. Release builds fail
# without it so an app can never ship missing its speech model.
set -euo pipefail

source_dir="$SRCROOT/Models/whisper"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WhisperModel"

if [[ ! -f "$source_dir/openai_whisper-base/config.json" ]]; then
  message="Whisper model missing. Run: zsh scripts/fetch-whisper-model.sh"
  if [[ "$CONFIGURATION" == "Release" ]]; then
    echo "error: $message"
    exit 1
  fi
  echo "warning: $message"
  exit 0
fi

mkdir -p "$destination"
rsync -a --delete "$source_dir/" "$destination/"
