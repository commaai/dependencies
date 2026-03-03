#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="v3.12.8"
INSTALL_DIR="$DIR/python3_dev/install"

# Clone/update source
if [ ! -d "python3-src/.git" ]; then
  rm -rf python3-src
  git clone --depth 1 https://github.com/python/cpython.git python3-src
fi
git -C python3-src fetch --depth 1 origin "$VERSION"
git -C python3-src checkout --force FETCH_HEAD

cd python3-src

# Run configure to generate pyconfig.h for this platform
echo "Running configure to generate pyconfig.h ..."
./configure --disable-shared --without-ensurepip > /dev/null 2>&1

cd "$DIR"

# Copy headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include"

cp -r python3-src/Include/* "$INSTALL_DIR/include/"
cp python3-src/pyconfig.h "$INSTALL_DIR/include/"

echo "Installed python3-dev headers to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
