#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

COMMIT="bdf5e5144cb993626a343c547b72db0b848ad59b"
VERSION="5.5.0.4"
INSTALL_DIR="$DIR/raylib_python_cffi/install"

# Idempotent: skip if already built
if [ -d "$INSTALL_DIR/raylib" ]; then
  echo "raylib-python-cffi already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone at specific commit (must init submodules for raylib C source)
if [ ! -d "raylib-python-cffi-src" ]; then
  git clone https://github.com/electronstudio/raylib-python-cffi.git raylib-python-cffi-src
  cd raylib-python-cffi-src
  git checkout "$COMMIT"
  git submodule update --init --recursive
  cd "$DIR"
fi

# Build into a temporary prefix using pip
PREFIX="$DIR/build/prefix"
mkdir -p "$PREFIX"
MAKEFLAGS="-j${NJOBS}" python3 -m pip install \
  --prefix="$PREFIX" \
  --no-deps \
  "./raylib-python-cffi-src/"

# Locate installed site-packages
SITE_PKG=$(python3 -c "
import sysconfig, os
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
rm -rf raylib-python-cffi-src "$DIR/build"

echo "Installed raylib-python-cffi to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
