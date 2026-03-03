#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="db00e9369a92aa74bf630a2ffb092a4b0b132c01"
INSTALL_DIR="$DIR/json11/install"
CXX="ccache ${CXX:-c++}"

if [ ! -d "$DIR/json11-src/.git" ]; then
  git clone --depth 1 https://github.com/dropbox/json11.git json11-src
fi

git -C json11-src fetch --depth 1 origin "$VERSION"
git -C json11-src checkout --force "$VERSION"

BUILD_DIR="$DIR/build"
mkdir -p "$BUILD_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include/json11"

CXX="${CXX:-c++}"
AR="${AR:-ar}"

$CXX -std=c++11 -fPIC -O2 -c "$DIR/json11-src/json11.cpp" -o "$BUILD_DIR/json11.o"
"$AR" rcs "$INSTALL_DIR/lib/libjson11.a" "$BUILD_DIR/json11.o"
cp "$DIR/json11-src/json11.hpp" "$INSTALL_DIR/include/json11/json11.hpp"

echo "Installed json11 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
