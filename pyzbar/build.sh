#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="0.23.93"
INSTALL_DIR="$DIR/pyzbar/install"
PLATFORM="$(uname -s)"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone/update source
if [ ! -d "zbar-src/.git" ]; then
  rm -rf zbar-src
  git clone --depth 1 https://github.com/mchehab/zbar.git zbar-src
fi
git -C zbar-src fetch --depth 1 origin "$VERSION"
git -C zbar-src checkout --force FETCH_HEAD

PREFIX="$DIR/build/prefix"
rm -rf "$DIR/build"
mkdir -p "$DIR/build"

cd zbar-src
autoreconf -vfi

CONFIGURE_ARGS=(
  --prefix="$PREFIX"
  --enable-shared
  --disable-static
  --disable-video
  --without-gtk
  --without-qt
  --without-python
  --without-java
  --without-imagemagick
  --without-dbus
  --without-jpeg
  --disable-doc
  --disable-nls
)

if [ "$PLATFORM" = "Darwin" ]; then
  # macOS needs explicit iconv linkage and no X11
  CONFIGURE_ARGS+=(--without-x)
  CFLAGS="-O2 -fPIC" LDFLAGS="-liconv" ./configure "${CONFIGURE_ARGS[@]}"
else
  CFLAGS="-O2 -fPIC" ./configure "${CONFIGURE_ARGS[@]}"
fi
make clean 2>/dev/null || true
make -j"$NJOBS"
make install
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"

if [ "$PLATFORM" = "Darwin" ]; then
  cp "$PREFIX/lib/libzbar.0.dylib" "$INSTALL_DIR/lib/"
  ln -s libzbar.0.dylib "$INSTALL_DIR/lib/libzbar.dylib"
  install_name_tool -id @loader_path/libzbar.0.dylib "$INSTALL_DIR/lib/libzbar.0.dylib"
  strip -x "$INSTALL_DIR/lib/libzbar.0.dylib" 2>/dev/null || true
else
  cp -P "$PREFIX/lib/libzbar.so"* "$INSTALL_DIR/lib/"
  strip --strip-unneeded "$INSTALL_DIR/lib/libzbar.so.0."* 2>/dev/null || true
  patchelf --set-rpath '$ORIGIN' "$INSTALL_DIR/lib/libzbar.so.0."* 2>/dev/null || true
fi

echo "Installed zbar to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
