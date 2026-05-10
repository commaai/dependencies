#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
CC="ccache ${CC:-cc}"

is_linux_aarch64() {
  [[ "$(uname)" == "Linux" && ( "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ) ]]
}

# Detect platform: PLATFORM_COMMA for comma devices, PLATFORM_DESKTOP otherwise
RAYLIB_PLATFORM="${RAYLIB_PLATFORM:-PLATFORM_DESKTOP}"
if [ -f /AGNOS ] || [ -f /TICI ]; then
  RAYLIB_PLATFORM="PLATFORM_COMMA"
fi

case "$RAYLIB_PLATFORM" in
  PLATFORM_DESKTOP|PLATFORM_COMMA) ;;
  *)
    echo "Unsupported RAYLIB_PLATFORM=$RAYLIB_PLATFORM; expected PLATFORM_DESKTOP or PLATFORM_COMMA" >&2
    exit 1
    ;;
esac
export RAYLIB_PLATFORM

# Clone and build raylib C library
RAYLIB_COMMIT="dff603f4f122163900469e73d113deacd9ec9817"

if [ ! -d "raylib-src/.git" ]; then
  rm -rf raylib-src
  git clone --depth 1 -b master --no-tags https://github.com/commaai/raylib.git raylib-src
fi

cd raylib-src
git remote set-url origin https://github.com/commaai/raylib.git
git fetch --depth 1 origin "$RAYLIB_COMMIT"
git reset --hard "$RAYLIB_COMMIT"

cd "$DIR"

# Install lib + headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

cp raylib-src/src/raylib.h raylib-src/src/raymath.h raylib-src/src/rlgl.h "$INSTALL_DIR/include/"

build_raylib() {
  local platform="$1"
  local output="$2"

  cd "$DIR/raylib-src/src"
  make clean
  make -j"$NJOBS" PLATFORM="$platform" CC="${CC:-gcc}"
  cp libraylib.a "$INSTALL_DIR/lib/$output"
  cd "$DIR"
}

if is_linux_aarch64; then
  echo "Building desktop backend..."
  build_raylib PLATFORM_DESKTOP libraylib_desktop.a
  cp "$INSTALL_DIR/lib/libraylib_desktop.a" "$INSTALL_DIR/lib/libraylib.a"

  echo "Building comma backend..."
  build_raylib PLATFORM_COMMA libraylib_comma.a
else
  build_raylib "$RAYLIB_PLATFORM" libraylib.a
fi

# Download raygui header
RAYGUI_COMMIT="1e03efca48c50c5ea4b4a053d5bf04bad58d3e43"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
