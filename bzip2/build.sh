#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="bzip2-1.0.8"
INSTALL_DIR="$DIR/bzip2/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
CC="ccache ${CC:-cc}"

# Clone/update source
if [ ! -d "bzip2-src/.git" ]; then
  rm -rf bzip2-src
  git clone --depth 1 https://gitlab.com/bzip2/bzip2.git bzip2-src
fi
git -C bzip2-src fetch --depth 1 origin "$VERSION"
git -C bzip2-src checkout --force FETCH_HEAD

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

echo "Installed bzip2 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
