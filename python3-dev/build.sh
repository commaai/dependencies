#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.12.8"
INSTALL_DIR="$DIR/python3_dev/install"

# Idempotent: skip if already present
if [ -f "$INSTALL_DIR/include/Python.h" ]; then
  echo "python3-dev headers already present, skipping."
  exit 0
fi

TARBALL="Python-${VERSION}.tgz"
URL="https://www.python.org/ftp/python/${VERSION}/${TARBALL}"

echo "Downloading CPython ${VERSION} source ..."
curl -fSL -o "$TARBALL" "$URL"

echo "Extracting ..."
tar xzf "$TARBALL"

cd "Python-${VERSION}"

# Run configure to generate pyconfig.h for this platform
echo "Running configure to generate pyconfig.h ..."
./configure --disable-shared --without-ensurepip > /dev/null 2>&1

cd "$DIR"

# Copy headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include"

cp -r "Python-${VERSION}/Include/"* "$INSTALL_DIR/include/"
cp "Python-${VERSION}/pyconfig.h" "$INSTALL_DIR/include/"

# Clean up
rm -rf "Python-${VERSION}" "$TARBALL"

echo "Installed python3-dev headers to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
