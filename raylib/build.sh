#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
CC="ccache ${CC:-cc}"

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
  elif [ "$RAYLIB_PLATFORM" = "PLATFORM_OFFSCREEN" ]; then
    # offscreen (CI): needs EGL/GL dev packages (no X11)
    if command -v apt-get &>/dev/null; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libegl-dev libgl-dev
      else
        sudo apt-get update && sudo apt-get install -y libegl-dev libgl-dev
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
RAYLIB_COMMIT="d9d7cc1353ec0f73c97e84ddf0973983d1ee25e2"

if [ ! -d "raylib-src/.git" ]; then
  rm -rf raylib-src
  git clone --depth 1 -b platform-offscreen --no-tags https://github.com/commaai/raylib.git raylib-src
fi

cd raylib-src
git fetch --depth 1 origin "$RAYLIB_COMMIT"
git reset --hard "$RAYLIB_COMMIT"

cd src
make clean
make -j"$NJOBS" PLATFORM="$RAYLIB_PLATFORM" CC="${CC:-gcc}"

cd "$DIR"

# Install lib + headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

cp raylib-src/src/libraylib.a "$INSTALL_DIR/lib/"
cp raylib-src/src/raylib.h raylib-src/src/raymath.h raylib-src/src/rlgl.h "$INSTALL_DIR/include/"

# On x86_64 Linux, also build the offscreen variant for CI headless rendering
if [[ "$(uname)" == "Linux" && "$(uname -m)" == "x86_64" && "$RAYLIB_PLATFORM" != "PLATFORM_OFFSCREEN" ]]; then
  echo "Building offscreen variant..."

  # Install EGL/GL dev packages needed for offscreen build + bundling
  if command -v dnf &>/dev/null; then
    dnf install -y mesa-libEGL-devel mesa-libGL-devel libglvnd-opengl libglvnd-core-devel 2>/dev/null || true
  elif command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y libegl-dev libgl-dev
    else
      sudo apt-get update && sudo apt-get install -y libegl-dev libgl-dev
    fi
  fi

  cd raylib-src/src
  make clean
  make -j"$NJOBS" PLATFORM=PLATFORM_OFFSCREEN CC="${CC:-gcc}"
  cp libraylib.a "$INSTALL_DIR/lib/libraylib_offscreen.a"
  cd "$DIR"

  # Bundle GLVND dispatchers so offscreen rendering works without extra system packages
  MESA_DIR="$INSTALL_DIR/lib/mesa"
  mkdir -p "$MESA_DIR"
  ldconfig 2>/dev/null || true
  for lib in libEGL.so.1 libOpenGL.so.0 libGLdispatch.so.0; do
    src="$(ldconfig -p 2>/dev/null | grep "$lib" | grep -E 'x86.64|libc6,' | awk '{print $NF}' | head -1)"
    if [ -n "$src" ] && [ -f "$src" ]; then
      cp -L "$src" "$MESA_DIR/"
      # Create unversioned symlink for the linker
      base="${lib%%.so.*}"
      ln -sf "$lib" "$MESA_DIR/${base}.so"
    fi
  done
fi

# Download raygui header
RAYGUI_COMMIT="76b36b597edb70ffaf96f046076adc20d67e7827"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
