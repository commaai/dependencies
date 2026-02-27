#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="1.0.8"
INSTALL_DIR="$DIR/bzip2/install"

# Idempotent: skip if already built
if [ -f "$INSTALL_DIR/lib/libbz2.a" ]; then
  echo "bzip2 already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Download
if [ ! -d "bzip2-src" ]; then
  curl -L "https://sourceware.org/pub/bzip2/bzip2-${VERSION}.tar.gz" -o bzip2.tar.gz
  mkdir -p bzip2-src
  tar xzf bzip2.tar.gz -C bzip2-src --strip-components=1
  rm bzip2.tar.gz
fi

# Build static library with -fPIC
cd bzip2-src
make -j"$NJOBS" libbz2.a CC="${CC:-cc}" CFLAGS="-Wall -Winline -O2 -fPIC -D_FILE_OFFSET_BITS=64"
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Library
cp bzip2-src/libbz2.a "$INSTALL_DIR/lib/"

# Headers
cp bzip2-src/bzlib.h "$INSTALL_DIR/include/"

# Clean up
rm -rf bzip2-src

echo "Installed bzip2 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
