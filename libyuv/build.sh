#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="6067afde563c3946eebd94f146b3824ab7a97a9c"
INSTALL_DIR="$DIR/libyuv/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

if [ ! -d "libyuv-src/.git" ]; then
  git clone --depth 1 https://chromium.googlesource.com/libyuv/libyuv libyuv-src
fi

git -C libyuv-src fetch --depth 1 origin "$VERSION"
git -C libyuv-src checkout --force "$VERSION"

BUILD_DIR="$DIR/build"
mkdir -p "$BUILD_DIR"

cmake -S "$DIR/libyuv-src" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC"

cmake --build "$BUILD_DIR" -j"$NJOBS"

LIBYUV_STATIC="$(find "$BUILD_DIR" -name "libyuv.a" -type f | head -n 1)"
if [ -z "$LIBYUV_STATIC" ]; then
  echo "libyuv.a not found in build output" >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}
cp "$LIBYUV_STATIC" "$INSTALL_DIR/lib/libyuv.a"
cp -r "$DIR/libyuv-src/include/." "$INSTALL_DIR/include/"

echo "Installed libyuv to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
