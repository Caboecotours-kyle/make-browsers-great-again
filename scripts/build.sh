#!/usr/bin/env bash
# Builds build/cmake/out/MBGA.app. Pass --run to launch it afterwards, or
# --release to build build/release/out/MBGA.app, which updates itself from
# GitHub (scripts/release.sh publishes it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIR="$BUILD/cmake"
FLAGS=()
RUN=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    # MBGA_SIGN_IDENTITY: the identity to sign with (ad hoc if unset).
    --release)
      DIR="$BUILD/release"
      FLAGS+=(-DMBGA_UPDATES=ON "-DMBGA_SIGN_IDENTITY=${MBGA_SIGN_IDENTITY:--}")
      ;;
    *)
      echo "usage: $0 [--run] [--release]" >&2
      exit 2
      ;;
  esac
done

# Run scripts/check.sh before every commit, and leave formatting-only
# commits out of git blame.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" config core.hooksPath .githooks
  git -C "$ROOT" config blame.ignoreRevsFile .git-blame-ignore-revs
fi

"$ROOT/scripts/fetch-cef.sh"

NINJA="$(command -v ninja || true)"
if [[ -z "$NINJA" ]]; then
  NINJA="$BUILD/tools/ninja"
  if [[ ! -x "$NINJA" ]]; then
    echo "Building ninja…"
    mkdir -p "$BUILD/tools"
    rm -rf "$BUILD/tools/ninja-src"
    git clone -q --depth 1 --branch v1.13.1 https://github.com/ninja-build/ninja.git "$BUILD/tools/ninja-src"
    cmake -S "$BUILD/tools/ninja-src" -B "$BUILD/tools/ninja-build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF >/dev/null
    cmake --build "$BUILD/tools/ninja-build" -j"$(sysctl -n hw.ncpu)" >/dev/null
    cp "$BUILD/tools/ninja-build/ninja" "$NINJA"
  fi
fi

cmake -S "$ROOT" -B "$DIR" -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" -DCMAKE_BUILD_TYPE=Release ${FLAGS[@]+"${FLAGS[@]}"}
cmake --build "$DIR"

APP="$DIR/out/MBGA.app"
echo "Built $APP"
if [[ "$RUN" == 1 ]]; then
  "$APP/Contents/MacOS/MBGA"
fi
