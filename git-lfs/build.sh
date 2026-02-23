#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.6.1"
INSTALL_DIR="$DIR/git_lfs/bin"

# Idempotent: skip if already present
if [ -x "$INSTALL_DIR/git-lfs" ]; then
  echo "git-lfs already present, skipping download."
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}-${ARCH}" in
  Linux-x86_64)   PLATFORM="linux-amd64"  ; EXT="tar.gz" ;;
  Linux-aarch64)  PLATFORM="linux-arm64"   ; EXT="tar.gz" ;;
  Darwin-arm64)   PLATFORM="darwin-arm64"  ; EXT="zip" ;;
  *)
    echo "Unsupported platform: ${OS}-${ARCH}" >&2
    exit 1
    ;;
esac

FILENAME="git-lfs-${PLATFORM}-v${VERSION}.${EXT}"
URL="https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}/${FILENAME}"

echo "Downloading $FILENAME ..."
curl -fSL -o "$FILENAME" "$URL"

echo "Extracting ..."
mkdir -p "$INSTALL_DIR"
if [ "$EXT" = "zip" ]; then
  python3 -c "
import zipfile, sys
with zipfile.ZipFile('$FILENAME') as zf:
  for info in zf.infolist():
    if info.filename.endswith('/git-lfs'):
      with open('$INSTALL_DIR/git-lfs', 'wb') as f:
        f.write(zf.read(info))
      break
"
else
  tar --strip-components=1 -xzf "$FILENAME" -C "$INSTALL_DIR" --wildcards '*/git-lfs'
fi

chmod +x "$INSTALL_DIR/git-lfs"
strip "$INSTALL_DIR/git-lfs" 2>/dev/null || true

rm -f "$FILENAME"

echo "Installed git-lfs to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
