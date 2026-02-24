#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.4.1"
INSTALL_DIR="$DIR/openssl3/install"

# Idempotent: skip if already built
if [ -f "$INSTALL_DIR/lib/libcrypto.a" ]; then
  echo "openssl already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Download
TARBALL="openssl-${VERSION}.tar.gz"
if [ ! -d "openssl-src" ]; then
  curl -fSL -o "$TARBALL" "https://github.com/openssl/openssl/releases/download/openssl-${VERSION}/${TARBALL}"
  mkdir -p openssl-src
  tar -xf "$TARBALL" -C openssl-src --strip-components=1
  rm -f "$TARBALL"
fi

# Configure
PREFIX="$DIR/build/prefix"
cd openssl-src

if [ "$(uname)" = "Darwin" ]; then
  TARGET="darwin64-arm64-cc"
else
  MACHINE="$(uname -m)"
  if [ "$MACHINE" = "x86_64" ]; then
    TARGET="linux-x86_64"
  elif [ "$MACHINE" = "aarch64" ]; then
    TARGET="linux-aarch64"
  else
    TARGET="linux-${MACHINE}"
  fi
fi

./Configure "$TARGET" \
  --prefix="$PREFIX" \
  --libdir=lib \
  no-shared \
  no-tests \
  no-docs \
  no-apps \
  -Os

# Build
make -j"$NJOBS"
make install_sw

cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Libraries
cp "$PREFIX/lib/libcrypto.a" "$INSTALL_DIR/lib/"
cp "$PREFIX/lib/libssl.a" "$INSTALL_DIR/lib/"

# Headers
cp -r "$PREFIX/include/openssl" "$INSTALL_DIR/include/"

# Clean up
rm -rf openssl-src "$DIR/build"

echo "Installed openssl to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
