#!/usr/bin/env bash
# Builds a release of MBGA at the version in CMakeLists.txt and publishes it
# on GitHub. Every installed copy checks the latest release's update.json,
# downloads MBGA.zip and offers to restart into it.
#
# The archive is signed with the release key, kept in your login keychain as
# "MBGA update signing key" (or given in MBGA_UPDATE_KEY). Copies only accept
# updates signed with it: back it up, and never publish it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^set(MBGA_VERSION "\(.*\)")$/\1/p' CMakeLists.txt)"
PUBLIC_KEY="$(sed -n 's/^set(MBGA_UPDATE_PUBLIC_KEY "\(.*\)")$/\1/p' CMakeLists.txt)"
TAG="v$VERSION"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or set aside your changes first: a release is built from a commit." >&2
  exit 1
fi
git fetch -q origin
if [[ -z "$(git branch -r --contains HEAD)" ]]; then
  echo "Push $(git rev-parse --short HEAD) to GitHub first." >&2
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "$TAG is out already. Raise MBGA_VERSION in CMakeLists.txt." >&2
  exit 1
fi

KEY="${MBGA_UPDATE_KEY:-$(security find-generic-password -s "MBGA update signing key" -a mbga -w)}"
if [[ "$(MBGA_UPDATE_KEY="$KEY" swift scripts/update-signing.swift public-key)" != "$PUBLIC_KEY" ]]; then
  echo "The signing key doesn't match MBGA_UPDATE_PUBLIC_KEY: installed copies would refuse this update." >&2
  exit 1
fi

scripts/build.sh --release
APP="$ROOT/build/release/out/MBGA.app"
OUT="$ROOT/build/release/assets"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "Packing ${TAG}…"
# The zip is what copies update from; the disk image is for installing:
# MBGA beside a link to Applications, to drag it onto.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$OUT/MBGA.zip"
mkdir "$OUT/dmg"
ditto "$APP" "$OUT/dmg/MBGA.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname MBGA -srcfolder "$OUT/dmg" -fs APFS -format ULFO "$OUT/MBGA.dmg"
rm -rf "$OUT/dmg"
SIGNED="$(MBGA_UPDATE_KEY="$KEY" swift scripts/update-signing.swift sign "$OUT/MBGA.zip")"
python3 - "$OUT" "$VERSION" "$REPO" "$TAG" "$SIGNED" <<'PY'
import json, os, sys
out, version, repo, tag, signed = sys.argv[1:]
sha256, signature = signed.split()
archive = os.path.join(out, "MBGA.zip")
json.dump({
    "version": version,
    "url": f"https://github.com/{repo}/releases/download/{tag}/MBGA.zip",
    "size": os.path.getsize(archive),
    "sha256": sha256,
    "signature": signature,
    "minimumSystemVersion": "15.0",
}, open(os.path.join(out, "update.json"), "w"), indent=2)
PY

PREVIOUS="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
{
  echo "## What's new"
  echo
  git log --no-merges --format='- %s' ${PREVIOUS:+"$PREVIOUS..HEAD"} | grep -v "^- Call this version of MBGA" | head -50
  echo
  echo "## Install"
  echo
  echo "MBGA runs on macOS 15 or later on Apple silicon. Copy and paste into Terminal:"
  echo
  echo '```sh'
  echo "curl -fL https://github.com/$REPO/releases/latest/download/MBGA.zip -o /tmp/MBGA.zip && ditto -x -k /tmp/MBGA.zip /Applications && open /Applications/MBGA.app"
  echo '```'
  echo
  echo "Or download MBGA.dmg below, open it and drag MBGA to Applications. MBGA isn't notarized, so the first time macOS asks: open it from System Settings ▸ Privacy & Security ▸ Open Anyway."
  echo
  echo "Once installed, MBGA updates itself."
} > "$OUT/notes.md"

gh release create "$TAG" "$OUT/MBGA.dmg" "$OUT/MBGA.zip" "$OUT/update.json" \
  --target "$(git rev-parse HEAD)" --title "MBGA $VERSION" --notes-file "$OUT/notes.md"
git fetch -q --tags origin
echo "Released $TAG: https://github.com/$REPO/releases/tag/$TAG"
