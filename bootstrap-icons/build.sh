#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

COMMIT="d5aa187483a1b0b186f87adcfa8576350d970d98"
INSTALL_DIR="$DIR/bootstrap_icons/install"

if [ ! -d "icons-src/.git" ]; then
  rm -rf icons-src
  git clone --depth 1 https://github.com/twbs/icons.git icons-src
fi
git -C icons-src fetch --depth 1 origin "$COMMIT"
git -C icons-src checkout --force FETCH_HEAD

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp icons-src/bootstrap-icons.svg "$INSTALL_DIR/"

python3 - <<'PY'
from fontTools.ttLib import TTFont

font = TTFont("icons-src/font/fonts/bootstrap-icons.woff")
font.flavor = None
font.save("bootstrap_icons/install/bootstrap-icons.ttf")
PY

echo "Installed bootstrap-icons to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
