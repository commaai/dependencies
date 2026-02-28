#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

# Idempotent: skip if already built
if [ -f "$INSTALL_DIR/lib/libraylib.a" ]; then
  echo "raylib already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Detect platform: PLATFORM_COMMA for comma devices, PLATFORM_DESKTOP otherwise
RAYLIB_PLATFORM="${RAYLIB_PLATFORM:-PLATFORM_DESKTOP}"
if [ -f /TICI ]; then
  RAYLIB_PLATFORM="PLATFORM_COMMA"
fi
export RAYLIB_PLATFORM

# Install build dependencies
if [[ "$(uname)" == "Linux" ]]; then
  if [ "$RAYLIB_PLATFORM" = "PLATFORM_COMMA" ]; then
    # comma device: needs DRM/EGL/GLES headers (usually already present on AGNOS)
    # apt may fail on devices due to read-only rootfs or package conflicts — that's OK
    if command -v apt-get &>/dev/null; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      else
        sudo apt-get update && sudo apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      fi
    fi
  else
    # desktop: needs X11/GL dev packages
    if command -v dnf &>/dev/null; then
      dnf install -y libX11-devel libXcursor-devel libXrandr-devel libXinerama-devel libXi-devel mesa-libGL-devel
    elif command -v apt-get &>/dev/null; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev
      else
        sudo apt-get update && sudo apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev
      fi
    fi
  fi
fi

# Clone and build raylib C library
RAYLIB_COMMIT="aa6ade09ac4bfb2847a356535f2d9f87e49ab089"

if [ ! -d "raylib-src" ]; then
  git clone -b master --no-tags https://github.com/commaai/raylib.git raylib-src
fi

cd raylib-src
git fetch origin "$RAYLIB_COMMIT"
git reset --hard "$RAYLIB_COMMIT"
git clean -xdff .

cd src
make -j"$NJOBS" PLATFORM="$RAYLIB_PLATFORM"

cd "$DIR"

# Install lib + headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

cp raylib-src/src/libraylib.a "$INSTALL_DIR/lib/"
cp raylib-src/src/raylib.h raylib-src/src/raymath.h raylib-src/src/rlgl.h "$INSTALL_DIR/include/"

# Download raygui header
RAYGUI_COMMIT="76b36b597edb70ffaf96f046076adc20d67e7827"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

# Clean up source
rm -rf raylib-src

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
