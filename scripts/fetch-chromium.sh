#!/bin/bash
# Downloads the plain Chromium build the benchmarks compare against: the
# Mac arm64 snapshot at the branch point of Chromium 154, the version MBGA's
# CEF is built on. Installs into third_party/chromium/.
set -euo pipefail

POSITION=1689411 # refs/heads/main@{#1689411}, 154.0.8037.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/chromium"
DL="$ROOT/third_party/chromium-dl"
URL="https://storage.googleapis.com/chromium-browser-snapshots/Mac_Arm/$POSITION/chrome-mac.zip"

if [[ -d "$DEST/chrome-mac/Chromium.app" ]]; then
  echo "Chromium already in $DEST"
  exit 0
fi
mkdir -p "$DL"
echo "Downloading Chromium snapshot $POSITION"
curl -fSL --retry 3 -o "$DL/chrome-mac.zip" "$URL"
rm -rf "$DEST" && mkdir -p "$DEST"
ditto -x -k "$DL/chrome-mac.zip" "$DEST"
defaults read "$DEST/chrome-mac/Chromium.app/Contents/Info.plist" CFBundleShortVersionString
