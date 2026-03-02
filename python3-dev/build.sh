#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.12.8"
INSTALL_DIR="$DIR/python3_dev/install"
SRC_DIR="$DIR/python3-src"
VERSION_FILE="$SRC_DIR/.version"

# Download if version changed or missing
if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$VERSION" ]; then
  rm -rf "$SRC_DIR"
  TARBALL="Python-${VERSION}.tgz"
  URL="https://www.python.org/ftp/python/${VERSION}/${TARBALL}"
  echo "Downloading CPython ${VERSION} source ..."
  curl -fSL -o "$TARBALL" "$URL"
  echo "Extracting ..."
  mkdir -p "$SRC_DIR"
  tar xzf "$TARBALL" -C "$SRC_DIR" --strip-components=1
  rm -f "$TARBALL"
  echo "$VERSION" > "$VERSION_FILE"
fi

cd "$SRC_DIR"

# Run configure to generate pyconfig.h for this platform
echo "Running configure to generate pyconfig.h ..."
./configure --disable-shared --without-ensurepip > /dev/null 2>&1

cd "$DIR"

# Copy headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include"

cp -r "$SRC_DIR/Include/"* "$INSTALL_DIR/include/"
cp "$SRC_DIR/pyconfig.h" "$INSTALL_DIR/include/"

echo "Installed python3-dev headers to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
