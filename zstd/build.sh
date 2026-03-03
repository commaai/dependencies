#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="1.5.6"
INSTALL_DIR="$DIR/zstd/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone/update source
if [ ! -d "zstd-src/.git" ]; then
  rm -rf zstd-src
  git clone --depth 1 https://github.com/facebook/zstd.git zstd-src
fi
git -C zstd-src fetch --depth 1 origin "v${VERSION}"
git -C zstd-src checkout --force FETCH_HEAD

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cmake -S zstd-src/build/cmake -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DZSTD_BUILD_PROGRAMS=OFF \
  -DZSTD_BUILD_TESTS=OFF \
  -DZSTD_BUILD_CONTRIB=OFF \
  -DZSTD_BUILD_SHARED=OFF \
  -DZSTD_BUILD_STATIC=ON

cmake --build "$DIR/build" -j"$NJOBS"
cmake --install "$DIR/build"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Library
cp "$PREFIX/lib/libzstd.a" "$INSTALL_DIR/lib/"

# Headers
cp "$PREFIX/include/zstd.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/zstd_errors.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/zdict.h" "$INSTALL_DIR/include/"

echo "Installed zstd to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
