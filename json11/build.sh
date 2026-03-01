#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="db00e9369a92aa74bf630a2ffb092a4b0b132c01"
INSTALL_DIR="$DIR/json11/install"
VERSION_FILE="$INSTALL_DIR/VERSION"

# Idempotent: skip if already built at this source revision.
if [ -f "$INSTALL_DIR/lib/libjson11.a" ] && [ -f "$INSTALL_DIR/include/json11/json11.hpp" ] && \
  [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
  echo "json11 already present, skipping build."
  exit 0
fi

if [ ! -d "$DIR/json11-src/.git" ]; then
  git clone https://github.com/dropbox/json11.git json11-src
fi

git -C json11-src fetch --force origin
git -C json11-src checkout --force "$VERSION"

BUILD_DIR="$DIR/build"
rm -rf "$BUILD_DIR" "$INSTALL_DIR"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR/lib" "$INSTALL_DIR/include/json11"

CXX="${CXX:-c++}"
AR="${AR:-ar}"

"$CXX" -std=c++11 -fPIC -O2 -c "$DIR/json11-src/json11.cpp" -o "$BUILD_DIR/json11.o"
"$AR" rcs "$INSTALL_DIR/lib/libjson11.a" "$BUILD_DIR/json11.o"
cp "$DIR/json11-src/json11.hpp" "$INSTALL_DIR/include/json11/json11.hpp"
echo "$VERSION" > "$VERSION_FILE"

# Keep workspace small and deterministic across builds.
rm -rf "$DIR/json11-src" "$BUILD_DIR"

echo "Installed json11 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
