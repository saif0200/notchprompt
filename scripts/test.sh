#!/bin/zsh
# Compiles the UI-free sources with the checks in scripts/selftest and runs them.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
xcrun swiftc -swift-version 5 -Onone -o "$out/selftest" \
  notchprompt/IslandGeometry.swift \
  notchprompt/ScrollEngine.swift \
  notchprompt/ScriptDocument.swift \
  notchprompt/ScriptAlignmentEngine.swift \
  notchprompt/StringSimilarity.swift \
  notchprompt/ScreenSelection.swift \
  notchprompt/ScreenSelectionSelfTests.swift \
  notchprompt/ScriptTextDecoding.swift \
  scripts/selftest/main.swift
"$out/selftest"
