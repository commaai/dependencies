#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="1.0.1"
INSTALL_DIR="$DIR/capnproto/install"

# Idempotent: skip if already built
if [ -x "$INSTALL_DIR/bin/capnp" ]; then
  echo "capnproto already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone
if [ ! -d "capnproto-src" ]; then
  git clone --depth 1 --branch "v${VERSION}" https://github.com/capnproto/capnproto.git capnproto-src
fi

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cmake -S capnproto-src -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DWITH_OPENSSL=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$DIR/build" -j"$NJOBS"
cmake --install "$DIR/build"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,include}

# Binaries
cp "$PREFIX/bin/capnp" "$INSTALL_DIR/bin/"
cp "$PREFIX/bin/capnpc-c++" "$INSTALL_DIR/bin/"
ln -sf capnp "$INSTALL_DIR/bin/capnpc"

# Libraries (only the ones openpilot needs)
cp "$PREFIX/lib/libcapnp.a" "$INSTALL_DIR/lib/"
cp "$PREFIX/lib/libkj.a" "$INSTALL_DIR/lib/"

# Headers
cp -r "$PREFIX/include/capnp" "$INSTALL_DIR/include/"
cp -r "$PREFIX/include/kj" "$INSTALL_DIR/include/"

# Strip binaries and libs
strip "$INSTALL_DIR/bin/capnp" "$INSTALL_DIR/bin/capnpc-c++" 2>/dev/null || true

# Strip unused kj objects from libkj.a (not needed by openpilot)
for obj in filesystem.c++.o main.c++.o test-helpers.c++.o; do
  ar d "$INSTALL_DIR/lib/libkj.a" "$obj" 2>/dev/null || true
done

# Clean up
rm -rf capnproto-src "$DIR/build"

echo "Installed capnproto to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
