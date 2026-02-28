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
SRC="$DIR/raylib-python-cffi-src"
if [ ! -d "$SRC" ]; then
  git clone https://github.com/electronstudio/raylib-python-cffi.git "$SRC"
  cd "$SRC"
  git checkout "$COMMIT"
  git submodule update --init --recursive
  cd "$DIR"
fi

# Build raylib C library from source
RAYLIB_INSTALL="$DIR/build/raylib-install"
cmake -S "$SRC/raylib-c" -B "$DIR/build/raylib-c" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_EXAMPLES=OFF \
  -DGLFW_BUILD_WAYLAND=OFF \
  -DCMAKE_INSTALL_PREFIX="$RAYLIB_INSTALL" \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "$DIR/build/raylib-c" -j"$NJOBS"
cmake --install "$DIR/build/raylib-c"

# Set env vars for the CFFI builder (raylib/build.py reads these)
export RAYLIB_LINK_ARGS="$RAYLIB_INSTALL/lib/libraylib.a"
export RAYLIB_INCLUDE_PATH="$RAYLIB_INSTALL/include"
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
