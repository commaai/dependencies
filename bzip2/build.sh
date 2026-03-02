#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="1.0.8"
INSTALL_DIR="$DIR/bzip2/install"
SRC_DIR="$DIR/bzip2-src"
VERSION_FILE="$SRC_DIR/.version"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Download if version changed or missing
if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$VERSION" ]; then
  rm -rf "$SRC_DIR"
  curl -L "https://sourceware.org/pub/bzip2/bzip2-${VERSION}.tar.gz" -o bzip2.tar.gz
  mkdir -p "$SRC_DIR"
  tar xzf bzip2.tar.gz -C "$SRC_DIR" --strip-components=1
  rm bzip2.tar.gz
  echo "$VERSION" > "$VERSION_FILE"
fi

# Build static library with -fPIC
cd "$SRC_DIR"
make -j"$NJOBS" libbz2.a CC="${CC:-cc}" CFLAGS="-Wall -Winline -O2 -fPIC -D_FILE_OFFSET_BITS=64"
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Library
cp "$SRC_DIR/libbz2.a" "$INSTALL_DIR/lib/"

# Headers
cp "$SRC_DIR/bzlib.h" "$INSTALL_DIR/include/"

echo "Installed bzip2 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
