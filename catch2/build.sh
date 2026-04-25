#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="v2.13.10"
INSTALL_DIR="$DIR/catch2/install"

if [ ! -d "catch2-src/.git" ]; then
  rm -rf catch2-src
  git clone --depth 1 https://github.com/catchorg/Catch2.git catch2-src
fi
git -C catch2-src fetch --depth 1 origin "$VERSION"
git -C catch2-src checkout --force FETCH_HEAD

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include"
cp -r catch2-src/single_include/catch2 "$INSTALL_DIR/include/"

echo "Installed catch2 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
