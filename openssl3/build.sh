#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="openssl-3.4.1"
INSTALL_DIR="$DIR/openssl3/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
export CC="ccache ${CC:-cc}"

# Clone/update source
if [ ! -d "openssl-src/.git" ]; then
  rm -rf openssl-src
  git clone --depth 1 https://github.com/openssl/openssl.git openssl-src
fi
git -C openssl-src fetch --depth 1 origin "$VERSION"
WANT_COMMIT="$(git -C openssl-src rev-parse FETCH_HEAD)"
VERSION_FILE="$INSTALL_DIR/.version"
if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$WANT_COMMIT" ]; then
  echo "openssl already at $VERSION, skipping build."
  exit 0
fi
git -C openssl-src checkout --force FETCH_HEAD

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

echo "$WANT_COMMIT" > "$VERSION_FILE"
echo "Installed openssl to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
