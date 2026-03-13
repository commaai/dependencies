#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

COMMIT="5cefd9847949af6df13f65027fd43af5a7513633"
INSTALL_DIR="$DIR/nanosvg/install"

# Clone/update source
if [ ! -d "nanosvg-src/.git" ]; then
  rm -rf nanosvg-src
  git clone --depth 1 https://github.com/memononen/nanosvg.git nanosvg-src
fi
git -C nanosvg-src fetch --depth 1 origin "$COMMIT"
git -C nanosvg-src checkout --force FETCH_HEAD

# Copy headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include"
cp nanosvg-src/src/nanosvg.h "$INSTALL_DIR/include/"
cp nanosvg-src/src/nanosvgrast.h "$INSTALL_DIR/include/"

echo "Installed nanosvg to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
