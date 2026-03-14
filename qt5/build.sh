#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

QT_VERSION="5.15.18"
QT_TAG="v${QT_VERSION}-lts-lgpl"
INSTALL_DIR="$DIR/qt5/install"
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Install build dependencies
if [[ "$(uname)" == "Linux" ]]; then
  if command -v dnf &>/dev/null; then
    dnf install -y \
      mesa-libGL-devel \
      fontconfig-devel \
      freetype-devel \
      libxcb-devel \
      xcb-util-devel \
      xcb-util-image-devel \
      xcb-util-keysyms-devel \
      xcb-util-renderutil-devel \
      xcb-util-wm-devel \
      libxkbcommon-devel \
      libxkbcommon-x11-devel \
      libX11-devel \
      perl-IPC-Cmd
  elif command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y \
        libgl-dev \
        libfontconfig1-dev libfreetype-dev \
        libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev \
        libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev \
        libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev \
        libxcb-randr0-dev libxcb-render-util0-dev \
        libxcb-xinerama0-dev libxcb-xkb-dev \
        libxkbcommon-dev libxkbcommon-x11-dev \
        libx11-xcb-dev
    else
      sudo apt-get update && sudo apt-get install -y \
        libgl-dev \
        libfontconfig1-dev libfreetype-dev \
        libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev \
        libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev \
        libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev \
        libxcb-randr0-dev libxcb-render-util0-dev \
        libxcb-xinerama0-dev libxcb-xkb-dev \
        libxkbcommon-dev libxkbcommon-x11-dev \
        libx11-xcb-dev
    fi
  fi
fi

# Clone/update qtbase
if [ ! -d "qtbase-src/.git" ]; then
  rm -rf qtbase-src
  git clone --depth 1 https://code.qt.io/qt/qtbase.git qtbase-src
fi
git -C qtbase-src fetch --depth 1 origin "$QT_TAG"
git -C qtbase-src checkout --force FETCH_HEAD

# Build qtbase (disable modules cabana doesn't need)
cd qtbase-src
./configure \
  -release \
  -prefix "$INSTALL_DIR" \
  -opensource -confirm-license \
  -nomake examples \
  -nomake tests \
  -no-dbus \
  -no-icu \
  -no-feature-concurrent \
  -no-feature-network \
  -no-feature-sql \
  -no-feature-testlib \
  -no-feature-xml \
  -opengl desktop
make -j"$NJOBS"
make install
cd "$DIR"

# Clone/update qtcharts
if [ ! -d "qtcharts-src/.git" ]; then
  rm -rf qtcharts-src
  git clone --depth 1 https://code.qt.io/qt/qtcharts.git qtcharts-src
fi
git -C qtcharts-src fetch --depth 1 origin "$QT_TAG"
git -C qtcharts-src checkout --force FETCH_HEAD

# Build qtcharts
cd qtcharts-src
"$INSTALL_DIR/bin/qmake"
make -j"$NJOBS"
make install
cd "$DIR"

# Keep only what cabana needs
KEEP_LIBS="Qt5Core Qt5Gui Qt5Widgets Qt5Charts Qt5OpenGL Qt5XcbQpa Qt5EglFSDeviceIntegration Qt5EglFsKmsSupport"
KEEP_BINS="moc rcc uic"

# Remove unnecessary binaries (qmake is 28MB, only needed for qtcharts build above)
for f in "$INSTALL_DIR/bin/"*; do
  name="$(basename "$f")"
  keep=false
  for b in $KEEP_BINS; do [ "$name" = "$b" ] && keep=true; done
  $keep || rm -f "$f"
done

# Remove unnecessary libs
if [[ "$(uname)" == "Linux" ]]; then
  for f in "$INSTALL_DIR/lib/"lib*.so; do
    name="$(basename "$f" .so)"
    name="${name#lib}"
    keep=false
    for lib in $KEEP_LIBS; do [ "$name" = "$lib" ] && keep=true; done
    if ! $keep; then
      rm -f "$INSTALL_DIR/lib/lib${name}".so*
    fi
  done
fi

# Remove unnecessary include dirs
if [[ "$(uname)" == "Linux" ]]; then
  KEEP_INCLUDES="QtCore QtGui QtWidgets QtCharts QtOpenGL"
  for d in "$INSTALL_DIR/include/"*/; do
    name="$(basename "$d")"
    keep=false
    for inc in $KEEP_INCLUDES; do [ "$name" = "$inc" ] && keep=true; done
    $keep || rm -rf "$d"
  done
fi

# Remove static libs, build artifacts
rm -rf "$INSTALL_DIR/doc" "$INSTALL_DIR/mkspecs" "$INSTALL_DIR/lib/cmake" "$INSTALL_DIR/lib/pkgconfig"
find "$INSTALL_DIR/lib" -name '*.a' -delete 2>/dev/null || true
find "$INSTALL_DIR/lib" -name '*.prl' -delete 2>/dev/null || true
find "$INSTALL_DIR/lib" -name '*.la' -delete 2>/dev/null || true

# Replace symlinks with copies for wheel compatibility (wheels can't store symlinks)
find "$INSTALL_DIR" -type l | while read -r link; do
  target="$(readlink -f "$link")"
  if [ -f "$target" ]; then
    rm "$link"
    cp "$target" "$link"
  elif [ -d "$target" ]; then
    rm "$link"
    cp -r "$target" "$link"
  fi
done

# Deduplicate versioned shared libs: keep only .so and .so.5 (SONAME)
# After symlink resolution above, all four copies (.so, .so.5, .so.5.15, .so.5.15.18) are real files
find "$INSTALL_DIR/lib" -maxdepth 1 -name 'lib*.so.5.15.18' -delete 2>/dev/null || true
find "$INSTALL_DIR/lib" -maxdepth 1 -name 'lib*.so.5.15' -delete 2>/dev/null || true

# Strip binaries and libraries
find "$INSTALL_DIR" -type f -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true
find "$INSTALL_DIR" -type f -name '*.dylib' -exec strip -x {} + 2>/dev/null || true
find "$INSTALL_DIR/bin" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true

echo "Installed Qt5 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
