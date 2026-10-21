#!/usr/bin/env bash
# Builds build/out/MBGA.app. Pass --run to launch it afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"

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

cmake -S "$ROOT" -B "$BUILD/cmake" -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD/cmake"

APP="$BUILD/cmake/out/MBGA.app"
echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
  "$APP/Contents/MacOS/MBGA"
fi
