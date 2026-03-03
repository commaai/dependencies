#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.4.0"
INSTALL_DIR="$DIR/eigen/install"

# Clone/update source
if [ ! -d "eigen-src/.git" ]; then
  rm -rf eigen-src
  git clone --depth 1 https://gitlab.com/libeigen/eigen.git eigen-src
fi
git -C eigen-src fetch --depth 1 origin "$VERSION"
git -C eigen-src checkout --force FETCH_HEAD

# Copy headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/eigen3"
cp -r eigen-src/Eigen "$INSTALL_DIR/eigen3/"
cp -r eigen-src/unsupported "$INSTALL_DIR/eigen3/"

echo "Installed eigen to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
