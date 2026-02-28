#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

COMMIT="bdf5e5144cb993626a343c547b72db0b848ad59b"
INSTALL_DIR="$DIR/raylib_python_cffi/install"

# Idempotent: skip if already built
if [ -d "$INSTALL_DIR/raylib" ]; then
  echo "raylib-python-cffi already present, skipping build."
  exit 0
fi

PYTHON="${PYTHON_EXECUTABLE:-python3}"
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone at specific commit with submodules (raylib-c, raygui, physac)
# Note: raylib-c's GLFW is bundled in-tree, no sub-submodule needed
SRC="$DIR/raylib-python-cffi-src"
if [ ! -d "$SRC" ]; then
  git clone https://github.com/electronstudio/raylib-python-cffi.git "$SRC"
  cd "$SRC"
  git checkout "$COMMIT"
  git submodule update --init --recursive
  cd "$DIR"
fi

# Build raylib C static library via its Makefile (same approach as openpilot)
RAYLIB_INSTALL="$DIR/build/raylib"
mkdir -p "$RAYLIB_INSTALL"
make -j"$NJOBS" -C "$SRC/raylib-c/src" \
  PLATFORM=PLATFORM_DESKTOP \
  RAYLIB_RELEASE_PATH="$RAYLIB_INSTALL"

# Set env vars for the CFFI builder (raylib/build.py reads these)
export RAYLIB_LINK_ARGS="$RAYLIB_INSTALL/libraylib.a"
export RAYLIB_INCLUDE_PATH="$SRC/raylib-c/src"
export RAYGUI_INCLUDE_PATH="$SRC/raygui/src"
export PHYSAC_INCLUDE_PATH="$SRC/physac/src"
export GLFW_INCLUDE_PATH="$SRC/raylib-c/src/external/glfw/include"

# Build into a temporary prefix using pip
PREFIX="$DIR/build/prefix"
mkdir -p "$PREFIX"
"$PYTHON" -m pip install \
  --prefix="$PREFIX" \
  --no-deps \
  --no-build-isolation \
  "$SRC/"

# Locate installed site-packages
SITE_PKG=$("$PYTHON" -c "
import sysconfig
prefix='$PREFIX'
p = sysconfig.get_path('platlib', vars={'platbase': prefix, 'base': prefix})
print(p)
")

# Copy artifacts to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$SITE_PKG/raylib" "$INSTALL_DIR/"
cp -r "$SITE_PKG/pyray" "$INSTALL_DIR/"
find "$SITE_PKG" -name "_raylib_cffi*.so" -exec cp {} "$INSTALL_DIR/" \;

# Clean up
rm -rf "$SRC" "$DIR/build"

echo "Installed raylib-python-cffi to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
