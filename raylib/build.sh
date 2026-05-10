#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
if command -v ccache &>/dev/null; then
  CC="ccache ${CC:-cc}"
else
  CC="${CC:-cc}"
fi

is_linux_aarch64() {
  [[ "$(uname)" == "Linux" && ( "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ) ]]
}

if [ -n "${RAYLIB_PLATFORM:-}" ]; then
  echo "RAYLIB_PLATFORM is no longer supported; use RAYLIB_BACKEND=desktop or RAYLIB_BACKEND=comma" >&2
  exit 1
fi

RAYLIB_BACKEND="${RAYLIB_BACKEND:-}"
if [ -z "$RAYLIB_BACKEND" ]; then
  RAYLIB_BACKEND="desktop"
  if [ -f /AGNOS ] || [ -f /TICI ]; then
    RAYLIB_BACKEND="comma"
  fi
fi

case "$RAYLIB_BACKEND" in
  desktop|comma) ;;
  *)
    echo "Unsupported RAYLIB_BACKEND=$RAYLIB_BACKEND; expected desktop or comma" >&2
    exit 1
    ;;
esac

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

  echo "Building comma backend..."
  build_raylib PLATFORM_COMMA libraylib_comma.a
else
  if [ "$RAYLIB_BACKEND" = "comma" ]; then
    build_raylib PLATFORM_COMMA libraylib_comma.a
  else
    build_raylib PLATFORM_DESKTOP libraylib_desktop.a
  fi
fi

# Download raygui header
RAYGUI_COMMIT="1e03efca48c50c5ea4b4a053d5bf04bad58d3e43"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
