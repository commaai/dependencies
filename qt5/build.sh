#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

QT_VERSION="5.15.2"
INSTALL_DIR="$DIR/qt5/install"

# Idempotent: skip if already built
if [ -f "$INSTALL_DIR/lib/libQt5Core.so.5" ] || [ -f "$INSTALL_DIR/lib/libQt5Core.5.dylib" ]; then
  echo "Qt5 already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PREFIX="$DIR/build/prefix"
SRC_DIR="$DIR/build/src"
mkdir -p "$SRC_DIR"

# --- Download source tarballs ---
QT_BASE_URL="https://download.qt.io/archive/qt/5.15/5.15.2/submodules"

for module in qtbase qtcharts qtserialbus; do
  tarball="${module}-everywhere-src-${QT_VERSION}.tar.xz"
  if [ ! -f "$SRC_DIR/$tarball" ]; then
    echo "Downloading $tarball..."
    curl -fSL -o "$SRC_DIR/$tarball" "$QT_BASE_URL/$tarball"
  fi
  if [ ! -d "$SRC_DIR/${module}-everywhere-src-${QT_VERSION}" ]; then
    echo "Extracting $tarball..."
    tar xf "$SRC_DIR/$tarball" -C "$SRC_DIR"
  fi
done

QTBASE_SRC="$SRC_DIR/qtbase-everywhere-src-${QT_VERSION}"
QTCHARTS_SRC="$SRC_DIR/qtcharts-everywhere-src-${QT_VERSION}"
QTSERIALBUS_SRC="$SRC_DIR/qtserialbus-everywhere-src-${QT_VERSION}"

# --- Patch Qt 5.15.2 for modern compilers (GCC 12+) ---
# Add missing #include <limits> to qglobal.h so it propagates everywhere
QGLOBAL="$QTBASE_SRC/src/corelib/global/qglobal.h"
if [ -f "$QGLOBAL" ] && ! grep -q '#include <limits>' "$QGLOBAL"; then
  sed -i.bak '1i\
#include <limits>' "$QGLOBAL"
fi

# --- Build qtbase ---
echo "Configuring qtbase..."
cd "$QTBASE_SRC"

CONFIGURE_ARGS=(
  -release -opensource -confirm-license
  -shared -prefix "$PREFIX"
  -nomake examples -nomake tests
  -no-dbus -no-icu -no-openssl -no-cups -no-glib
  -no-feature-sql -no-feature-printer -no-feature-testlib
  -qt-pcre -qt-zlib -qt-libpng -qt-libjpeg -qt-harfbuzz
)

if [ "$(uname)" = "Darwin" ]; then
  CONFIGURE_ARGS+=(-no-framework)
else
  CONFIGURE_ARGS+=(-xcb -fontconfig -system-freetype)
fi

./configure "${CONFIGURE_ARGS[@]}"

echo "Building qtbase..."
make -j"$NJOBS"
make install

# --- Build qtcharts ---
echo "Building qtcharts..."
cd "$QTCHARTS_SRC"
"$PREFIX/bin/qmake"
make -j"$NJOBS"
make install

# --- Build qtserialbus ---
echo "Building qtserialbus..."
cd "$QTSERIALBUS_SRC"
"$PREFIX/bin/qmake"
make -j"$NJOBS"
make install

cd "$DIR"

# --- Copy to package install dir ---
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,include,plugins/platforms}

# Binaries (moc, rcc)
cp "$PREFIX/bin/moc" "$INSTALL_DIR/bin/"
cp "$PREFIX/bin/rcc" "$INSTALL_DIR/bin/"

# Headers
for mod in QtCore QtGui QtWidgets QtNetwork QtConcurrent QtXml QtCharts QtSerialBus; do
  if [ -d "$PREFIX/include/$mod" ]; then
    cp -r "$PREFIX/include/$mod" "$INSTALL_DIR/include/"
  fi
done

# QtGui private headers (needed for QOpenGLWidget internals)
QTGUI_PRIVATE="$PREFIX/include/QtGui/${QT_VERSION}/QtGui"
if [ -d "$QTGUI_PRIVATE" ]; then
  mkdir -p "$INSTALL_DIR/include/QtGui/${QT_VERSION}/QtGui"
  cp -r "$QTGUI_PRIVATE/"* "$INSTALL_DIR/include/QtGui/${QT_VERSION}/QtGui/"
fi

# Shared libraries + symlinks
if [ "$(uname)" = "Darwin" ]; then
  # Copy dylibs
  for lib in "$PREFIX"/lib/libQt5*.dylib; do
    [ -f "$lib" ] && cp -a "$lib" "$INSTALL_DIR/lib/"
  done
  # Copy symlinks too
  for link in "$PREFIX"/lib/libQt5*.dylib; do
    [ -L "$link" ] && cp -a "$link" "$INSTALL_DIR/lib/"
  done

  # Platform plugin
  if [ -f "$PREFIX/plugins/platforms/libqcocoa.dylib" ]; then
    cp "$PREFIX/plugins/platforms/libqcocoa.dylib" "$INSTALL_DIR/plugins/platforms/"
  fi

  # Fix install names to use @rpath
  for dylib in "$INSTALL_DIR"/lib/libQt5*.dylib; do
    [ -L "$dylib" ] && continue
    [ ! -f "$dylib" ] && continue

    libname="$(basename "$dylib")"
    install_name_tool -id "@rpath/$libname" "$dylib" 2>/dev/null || true

    # Fix references to other Qt libs
    for dep in $(otool -L "$dylib" | grep "$PREFIX/lib/libQt5" | awk '{print $1}'); do
      depname="$(basename "$dep")"
      install_name_tool -change "$dep" "@rpath/$depname" "$dylib" 2>/dev/null || true
    done
  done

  # Fix plugin install names too
  for plugin in "$INSTALL_DIR"/plugins/platforms/*.dylib; do
    [ ! -f "$plugin" ] && continue
    for dep in $(otool -L "$plugin" | grep "$PREFIX/lib/libQt5" | awk '{print $1}'); do
      depname="$(basename "$dep")"
      install_name_tool -change "$dep" "@rpath/$depname" "$plugin" 2>/dev/null || true
    done
  done
else
  # Copy .so files and symlinks
  for lib in "$PREFIX"/lib/libQt5*.so*; do
    cp -a "$lib" "$INSTALL_DIR/lib/"
  done

  # Platform plugin
  if [ -f "$PREFIX/plugins/platforms/libqxcb.so" ]; then
    cp "$PREFIX/plugins/platforms/libqxcb.so" "$INSTALL_DIR/plugins/platforms/"
  fi

  # XCB GL integrations
  if [ -d "$PREFIX/plugins/xcbglintegrations" ]; then
    cp -r "$PREFIX/plugins/xcbglintegrations" "$INSTALL_DIR/plugins/"
  fi
fi

# Strip binaries
strip "$INSTALL_DIR/bin/moc" "$INSTALL_DIR/bin/rcc" 2>/dev/null || true

# Clean up
rm -rf "$DIR/build"

echo "Installed Qt5 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
