#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="1.0.29"
ARCHIVE="libusb-${VERSION}.tar.bz2"
URL="https://github.com/libusb/libusb/releases/download/v${VERSION}/${ARCHIVE}"
INSTALL_DIR="$DIR/libusb/install"
SRC_DIR="$DIR/libusb-src"
VERSION_FILE="$SRC_DIR/.version"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
export CC="ccache ${CC:-cc}"

if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$VERSION" ]; then
  rm -rf "$SRC_DIR"
  mkdir -p "$SRC_DIR"
  curl -fSL "$URL" | tar xj --strip-components=1 -C "$SRC_DIR"
  echo "$VERSION" > "$VERSION_FILE"
fi

PREFIX="$DIR/build/prefix"
rm -rf "$DIR/build"
mkdir -p "$DIR/build"

CONFIGURE_ARGS=(
  --prefix="$PREFIX"
  --disable-shared
  --enable-static
)

if [ "$(uname)" = "Linux" ]; then
  CONFIGURE_ARGS+=(--disable-udev)
fi

cd "$SRC_DIR"
CFLAGS="-O2 -fPIC" ./configure "${CONFIGURE_ARGS[@]}"
make -j"$NJOBS"
make install
cd "$DIR"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib/pkgconfig" "$INSTALL_DIR/include/libusb-1.0"

cp "$PREFIX/lib/libusb-1.0.a" "$INSTALL_DIR/lib/"
cp "$PREFIX/lib/pkgconfig/libusb-1.0.pc" "$INSTALL_DIR/lib/pkgconfig/"
cp "$PREFIX/include/libusb-1.0/libusb.h" "$INSTALL_DIR/include/libusb-1.0/"

echo "Installed libusb to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
