#!/usr/bin/env bash
# Downloads the prebuilt Chromium Embedded Framework into third_party/cef/dist.
set -euo pipefail

CEF_VERSION="154.0.34+g14c5a08+chromium-154.0.8037.98"
# Spotify's build omits H.264/AAC. Loopy builds the same CEF version with
# proprietary_codecs=true and ffmpeg_branding=Chrome for MP4 playback.
SHA256="a9addfce9552ae4cb7fa7e57d5aa5ecc225c77c4a347b0116cf11cd03cad65af"
BUILD_ID="$CEF_VERSION-codecs-$SHA256"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/cef"
STAMP="$DEST/dist/.version"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$BUILD_ID" ]]; then
  exit 0
fi

NAME="loopy-darwin-aarch64_minimal"
TAG="cef-${CEF_VERSION%%+*}-chromium-${CEF_VERSION##*chromium-}"
URL="https://github.com/ashwardy/loopy-cef-builds/releases/download/$TAG/$NAME.tar.bz2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading CEF ${CEF_VERSION}…"
curl -fL --progress-bar -o "$WORK/cef.tar.bz2" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/cef.tar.bz2" | cut -d' ' -f1)"
if [[ "$SHA256" != "$ACTUAL" ]]; then
  echo "Checksum mismatch: expected $SHA256, got $ACTUAL" >&2
  exit 1
fi

tar -xjf "$WORK/cef.tar.bz2" -C "$WORK"
rm -rf "$DEST/dist"
mkdir -p "$DEST"
mv "$WORK/$NAME" "$DEST/dist"
echo "$BUILD_ID" >"$STAMP"
