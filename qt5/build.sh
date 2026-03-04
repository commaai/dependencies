#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="5.15.16"
INSTALL_DIR="$DIR/qt5/install"

# Idempotent: skip if already built
if [ -x "$INSTALL_DIR/bin/qmake" ]; then
  echo "qt5 already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

MIRROR="https://download.qt.io/archive/qt/5.15/$VERSION/submodules"
QTBASE_TAR="qtbase-everywhere-opensource-src-$VERSION.tar.xz"
QTCHARTS_TAR="qtcharts-everywhere-opensource-src-$VERSION.tar.xz"

# --- Install build dependencies ---
if [[ "$(uname)" == "Linux" ]]; then
  if command -v dnf &>/dev/null; then
    dnf install -y \
      libxcb-devel xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel \
      xcb-util-renderutil-devel xcb-util-wm-devel libxkbcommon-devel libxkbcommon-x11-devel \
      fontconfig-devel freetype-devel mesa-libGL-devel mesa-libEGL-devel \
      libX11-devel libXext-devel libXrender-devel libXi-devel libxkbfile-devel \
      'perl(FindBin)' 'perl(File-Copy)'
  elif command -v apt-get &>/dev/null; then
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
      SUDO="sudo"
    fi
    $SUDO apt-get update
    $SUDO apt-get install -y \
      libxcb1-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
      libxcb-render-util0-dev libxcb-shape0-dev libxcb-shm0-dev libxcb-sync-dev \
      libxcb-xfixes0-dev libxcb-xinerama0-dev libxcb-xkb-dev libxcb-randr0-dev \
      libxkbcommon-dev libxkbcommon-x11-dev \
      libfontconfig1-dev libfreetype-dev libgl-dev libegl-dev \
      libx11-dev libx11-xcb-dev libxext-dev libxrender-dev libxi-dev \
      libatspi2.0-dev
  fi
fi

# --- Download sources ---
for tarball in "$QTBASE_TAR" "$QTCHARTS_TAR"; do
  if [ ! -f "$tarball" ]; then
    echo "Downloading $tarball ..."
    for attempt in 1 2 3; do
      if curl -fSL -o "$tarball.tmp" "$MIRROR/$tarball"; then
        mv "$tarball.tmp" "$tarball"
        break
      fi
      if [ "$attempt" -eq 3 ]; then
        echo "Failed to download $tarball after 3 attempts" >&2
        exit 1
      fi
      echo "Retrying in $((attempt * 2))s ..."
      sleep $((attempt * 2))
    done
  fi
done

# --- Extract ---
QTBASE_SRC="$DIR/qtbase-everywhere-src-$VERSION"
QTCHARTS_SRC="$DIR/qtcharts-everywhere-src-$VERSION"

if [ ! -d "$QTBASE_SRC" ]; then
  echo "Extracting $QTBASE_TAR ..."
  tar xf "$QTBASE_TAR"
fi
if [ ! -d "$QTCHARTS_SRC" ]; then
  echo "Extracting $QTCHARTS_TAR ..."
  tar xf "$QTCHARTS_TAR"
fi

# --- Build qtbase ---
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build/qtbase"

cd "$QTBASE_SRC"

CONFIGURE_ARGS=(
  -prefix "$PREFIX"
  -release
  -shared
  -opensource -confirm-license
  -nomake examples
  -nomake tests
  -no-dbus
  -system-freetype
  -fontconfig
)

if [[ "$(uname)" == "Linux" ]]; then
  CONFIGURE_ARGS+=(-opengl desktop -xcb)
elif [[ "$(uname)" == "Darwin" ]]; then
  CONFIGURE_ARGS+=(-no-framework)
fi

./configure "${CONFIGURE_ARGS[@]}"
make -j"$NJOBS"
make install
cd "$DIR"

# --- Build qtcharts ---
cd "$QTCHARTS_SRC"
"$PREFIX/bin/qmake"
make -j"$NJOBS"
make install
cd "$DIR"

# --- Assemble install directory ---
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,include,plugins,mkspecs}

# Binaries
for tool in qmake moc rcc uic; do
  cp "$PREFIX/bin/$tool" "$INSTALL_DIR/bin/"
done

# Shared libraries
if [[ "$(uname)" == "Linux" ]]; then
  for mod in Qt5Core Qt5Gui Qt5Widgets Qt5OpenGL Qt5Charts; do
    # Copy the actual shared library and symlinks
    cp -a "$PREFIX/lib/lib${mod}.so"* "$INSTALL_DIR/lib/"
  done
  # ICU or other support libs if present
  cp -a "$PREFIX/lib"/libQt5DBus.so* "$INSTALL_DIR/lib/" 2>/dev/null || true
  cp -a "$PREFIX/lib"/libQt5XcbQpa.so* "$INSTALL_DIR/lib/" 2>/dev/null || true
elif [[ "$(uname)" == "Darwin" ]]; then
  for mod in Qt5Core Qt5Gui Qt5Widgets Qt5OpenGL Qt5Charts; do
    cp -a "$PREFIX/lib/lib${mod}".*.dylib "$INSTALL_DIR/lib/"
    cp -a "$PREFIX/lib/lib${mod}.dylib" "$INSTALL_DIR/lib/"
  done
fi

# Headers
for mod in QtCore QtGui QtWidgets QtOpenGL QtCharts; do
  if [ -d "$PREFIX/include/$mod" ]; then
    cp -r "$PREFIX/include/$mod" "$INSTALL_DIR/include/"
  fi
done

# Platform plugins (needed at runtime)
if [ -d "$PREFIX/plugins/platforms" ]; then
  cp -r "$PREFIX/plugins/platforms" "$INSTALL_DIR/plugins/"
fi

# mkspecs (needed by qmake for downstream builds)
cp -r "$PREFIX/mkspecs" "$INSTALL_DIR/"

# Write qt.conf for relocatability
cat > "$INSTALL_DIR/bin/qt.conf" << 'EOF'
[Paths]
Prefix = ..
EOF

# Strip binaries
if [[ "$(uname)" == "Linux" ]]; then
  find "$INSTALL_DIR/bin" -type f -executable -exec strip {} + 2>/dev/null || true
  find "$INSTALL_DIR/lib" -name '*.so*' -type f -exec strip --strip-unneeded {} + 2>/dev/null || true
  find "$INSTALL_DIR/plugins" -name '*.so' -type f -exec strip --strip-unneeded {} + 2>/dev/null || true
elif [[ "$(uname)" == "Darwin" ]]; then
  find "$INSTALL_DIR/bin" -type f -perm +111 -exec strip -x {} + 2>/dev/null || true
  find "$INSTALL_DIR/lib" -name '*.dylib' -type f -exec strip -x {} + 2>/dev/null || true
fi

# Clean up sources and build artifacts
rm -rf "$QTBASE_SRC" "$QTCHARTS_SRC" "$DIR/build" "$QTBASE_TAR" "$QTCHARTS_TAR"

echo "Installed qt5 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
