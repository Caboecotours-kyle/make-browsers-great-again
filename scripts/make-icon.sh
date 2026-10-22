#!/usr/bin/env bash
# Renders assets/icon.svg into the layer of shell/resources/AppIcon.icon, the
# Icon Composer document the build compiles into the app icon. The SVG uses
# filters that only browsers draw faithfully, so it is rasterized with
# headless Chrome. Run it after editing the SVG and commit the PNG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/assets/icon.svg"
OUT="$ROOT/shell/resources/AppIcon.icon/Assets/art.png"

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  [[ -x "$c" ]] && CHROME="$c" && break
done
[[ -n "$CHROME" ]] || { echo "Needs Google Chrome or Chromium in /Applications" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# macOS cuts the icon shape itself, so the art is drawn edge to edge: the
# tile is scaled up from Apple's 824 pt grid to the full 1024 canvas and its
# shape, edge and shadow are dropped.
{
  cat <<'HTML'
<html><head><style>
  body { margin: 0; }
  svg { display: block; width: 1024px; height: 1024px; }
  #art { transform: translate(512px, 512px) scale(1.2427) translate(-512px, -512px); }
  #tile-shadow { filter: none; }
  #tile-body { d: path("M-100 -100H1124V1124H-100Z"); }
  #tile-fx { clip-path: none; }
  #tile-edge { display: none; }
</style></head><body>
HTML
  cat "$SVG"
  echo '</body></html>'
} > "$WORK/icon.html"

"$CHROME" --headless --disable-gpu --hide-scrollbars --no-first-run \
  --user-data-dir="$WORK/profile" --window-size=1024,1024 \
  --screenshot="$OUT" "file://$WORK/icon.html" >/dev/null 2>&1
echo "Wrote $OUT"
