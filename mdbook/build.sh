#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="0.5.2"
INSTALL_DIR="$DIR/mdbook/bin"
VERSION_FILE="$INSTALL_DIR/.version"

if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
  echo "mdbook $VERSION already present, skipping."
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}-${ARCH}" in
  Linux-x86_64)  PLATFORM="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64)  PLATFORM="aarch64-unknown-linux-musl" ;;
  Darwin-arm64)   PLATFORM="aarch64-apple-darwin" ;;
  *)
    echo "Unsupported platform: ${OS}-${ARCH}" >&2
    exit 1
    ;;
esac

FILENAME="mdbook-v${VERSION}-${PLATFORM}.tar.gz"
URL="https://github.com/rust-lang/mdBook/releases/download/v${VERSION}/${FILENAME}"

echo "Downloading $FILENAME ..."
curl -fSL -o "$FILENAME" "$URL"

echo "Extracting ..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$FILENAME" -C "$INSTALL_DIR" --strip-components=0 mdbook 2>/dev/null || tar -xzf "$FILENAME" -C "$INSTALL_DIR" --strip-components=1

chmod +x "$INSTALL_DIR/mdbook"

rm -f "$FILENAME"
echo "$VERSION" > "$VERSION_FILE"

echo "Installed mdbook to $INSTALL_DIR"
du -sh "$INSTALL_DIR"