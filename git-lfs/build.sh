#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.6.1"
INSTALL_DIR="$DIR/git_lfs/bin"
VERSION_FILE="$INSTALL_DIR/.version"

# Skip if already at correct version
if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
  echo "git-lfs $VERSION already present, skipping."
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

rm -f "$FILENAME"
echo "$VERSION" > "$VERSION_FILE"

echo "Installed git-lfs to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
