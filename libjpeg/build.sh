#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.1.0"
INSTALL_DIR="$DIR/libjpeg/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone/update source
if [ ! -d "libjpeg-turbo-src/.git" ]; then
  rm -rf libjpeg-turbo-src
  git clone --depth 1 https://github.com/libjpeg-turbo/libjpeg-turbo.git libjpeg-turbo-src
fi
git -C libjpeg-turbo-src fetch --depth 1 origin "${VERSION}"
git -C libjpeg-turbo-src checkout --force FETCH_HEAD

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cmake -S libjpeg-turbo-src -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DENABLE_SHARED=OFF \
  -DENABLE_STATIC=ON \
  -DWITH_TURBOJPEG=OFF

cmake --build "$DIR/build" -j"$NJOBS"
cmake --install "$DIR/build"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Library
cp "$PREFIX/lib/libjpeg.a" "$INSTALL_DIR/lib/"

# Headers
cp "$PREFIX/include/jpeglib.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/jconfig.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/jerror.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/jmorecfg.h" "$INSTALL_DIR/include/"

echo "Installed libjpeg to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
