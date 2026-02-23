#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="4.3.5"
INSTALL_DIR="$DIR/zeromq/install"

# Idempotent: skip if already built
if [ -f "$INSTALL_DIR/lib/libzmq.a" ]; then
  echo "zeromq already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone
if [ ! -d "libzmq-src" ]; then
  git clone --depth 1 --branch "v${VERSION}" https://github.com/zeromq/libzmq.git libzmq-src
fi

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cmake -S libzmq-src -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DWITH_LIBSODIUM=OFF \
  -DWITH_TLS=OFF \
  -DWITH_DOCS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_SHARED=OFF \
  -DBUILD_STATIC=ON \
  -DENABLE_DRAFTS=OFF

cmake --build "$DIR/build" -j"$NJOBS"
cmake --install "$DIR/build"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Library
cp "$PREFIX/lib/libzmq.a" "$INSTALL_DIR/lib/"

# Headers
cp "$PREFIX/include/zmq.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/zmq_utils.h" "$INSTALL_DIR/include/"

# Clean up
rm -rf libzmq-src "$DIR/build"

echo "Installed zeromq to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
