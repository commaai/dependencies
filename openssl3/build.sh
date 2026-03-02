#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.4.1"
INSTALL_DIR="$DIR/openssl3/install"
SRC_DIR="$DIR/openssl-src"
VERSION_FILE="$SRC_DIR/.version"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Download if version changed or missing
if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$VERSION" ]; then
  rm -rf "$SRC_DIR"
  TARBALL="openssl-${VERSION}.tar.gz"
  curl -fSL -o "$TARBALL" "https://github.com/openssl/openssl/releases/download/openssl-${VERSION}/${TARBALL}"
  mkdir -p "$SRC_DIR"
  tar -xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
  rm -f "$TARBALL"
  echo "$VERSION" > "$VERSION_FILE"
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
  -fPIC \
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

echo "Installed openssl to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
