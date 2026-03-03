#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="6.5"
INSTALL_DIR="$DIR/ncurses/install"
VERSION_FILE="$DIR/ncurses-src/.version"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
export CC="ccache ${CC:-cc}"

# Download tarball (v6.5 tag doesn't exist on the GitHub mirror)
if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$VERSION" ]; then
  rm -rf ncurses-src
  mkdir -p ncurses-src
  curl -fSL "https://ftp.gnu.org/gnu/ncurses/ncurses-${VERSION}.tar.gz" \
    | tar xz --strip-components=1 -C ncurses-src
  echo "$VERSION" > "$VERSION_FILE"
fi

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cd ncurses-src
CFLAGS="-fPIC" ./configure \
  --prefix="$PREFIX" \
  --without-shared \
  --with-normal \
  --without-debug \
  --without-cxx \
  --without-cxx-binding \
  --without-ada \
  --without-manpages \
  --without-progs \
  --without-tests \
  --without-dlsym \
  --enable-overwrite

make -j"$NJOBS"
# Only install libs and headers; skip terminfo database (fails on macOS CI)
make install.libs install.includes
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

# Libraries (ncurses 6.x builds wide-char by default; provide as libncurses.a)
cp "$PREFIX/lib/libncursesw.a" "$INSTALL_DIR/lib/libncurses.a" 2>/dev/null \
  || cp "$PREFIX/lib/libncurses.a" "$INSTALL_DIR/lib/"

# Headers (--enable-overwrite puts them directly in include/)
cp "$PREFIX/include/ncurses.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/curses.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/ncurses_dll.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/unctrl.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/term.h" "$INSTALL_DIR/include/"
cp "$PREFIX/include/termcap.h" "$INSTALL_DIR/include/"

echo "Installed ncurses to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
