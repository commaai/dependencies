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
export RAYLIB_PLATFORM

# Install build dependencies
if [[ "$(uname)" == "Linux" ]]; then
  if is_linux_aarch64; then
    # Linux/aarch64 wheels include both desktop and comma backends.
    if command -v dnf &>/dev/null; then
      dnf install -y libX11-devel libXcursor-devel libXrandr-devel libXinerama-devel libXi-devel \
        mesa-libGL-devel libdrm-devel mesa-libgbm-devel mesa-libEGL-devel mesa-libGLES-devel
    elif command -v apt-get &>/dev/null; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev \
          libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev
      else
        sudo apt-get update && sudo apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev \
          libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev
      fi
    fi
  elif [ "$RAYLIB_PLATFORM" = "PLATFORM_COMMA" ]; then
    # comma device: needs DRM/EGL/GLES headers (usually already present on AGNOS)
    # apt may fail on devices due to read-only rootfs or package conflicts — that's OK
    if command -v apt-get &>/dev/null; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      else
        sudo apt-get update && sudo apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      fi
    fi
  elif [ "$RAYLIB_PLATFORM" = "PLATFORM_MEMORY" ]; then
    # memory platform: software renderer, no window-system dev packages needed
    true
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
  if [ "$platform" = "PLATFORM_MEMORY" ]; then
    make -j"$NJOBS" PLATFORM="$platform" CC="${CC:-gcc}" CUSTOM_CFLAGS="${CUSTOM_CFLAGS:-} -fPIC"
  else
    make -j"$NJOBS" PLATFORM="$platform" CC="${CC:-gcc}"
  fi
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

# On x86_64 Linux, also build the memory variant for CI headless rendering
if [[ "$(uname)" == "Linux" && "$(uname -m)" == "x86_64" && "$RAYLIB_PLATFORM" != "PLATFORM_MEMORY" ]]; then
  echo "Building memory variant..."
  build_raylib PLATFORM_MEMORY libraylib_memory.a
fi

# Download raygui header
RAYGUI_COMMIT="1e03efca48c50c5ea4b4a053d5bf04bad58d3e43"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
