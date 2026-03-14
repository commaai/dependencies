#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

QT_VERSION="5.15.18"
QT_TAG="v${QT_VERSION}-lts-lgpl"
INSTALL_DIR="$DIR/qt5/install"
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Install build dependencies (manylinux deps installed centrally in build.sh)
if [[ "$(uname)" == "Linux" ]]; then
  if command -v apt-get &>/dev/null; then
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

# Clean cached build artifacts (Xcode version / symlink-to-dir issues)
rm -rf "$INSTALL_DIR"

# Clone/update qtbase
if [ ! -d "qtbase-src/.git" ]; then
  rm -rf qtbase-src
  git clone --depth 1 https://code.qt.io/qt/qtbase.git qtbase-src
fi
git -C qtbase-src fetch --depth 1 origin "$QT_TAG"
git -C qtbase-src checkout --force FETCH_HEAD
git -C qtbase-src clean -fdx .

# Build qtbase
cd qtbase-src
./configure \
  -release \
  -prefix "$INSTALL_DIR" \
  -opensource -confirm-license \
  -nomake examples \
  -nomake tests \
  -no-dbus \
  -no-icu \
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

# Build qtcharts (clean stale PCH/build artifacts from cache)
cd qtcharts-src
git clean -fdx .
"$INSTALL_DIR/bin/qmake"
make -j"$NJOBS"
make install
cd "$DIR"

# Replace symlinks with copies for wheel compatibility
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

# Strip binaries and libraries
find "$INSTALL_DIR" -type f -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true
find "$INSTALL_DIR" -type f -name '*.dylib' -exec strip -x {} + 2>/dev/null || true
strip "$INSTALL_DIR/bin/moc" "$INSTALL_DIR/bin/rcc" "$INSTALL_DIR/bin/uic" 2>/dev/null || true

# Remove unnecessary files to reduce wheel size
rm -rf "$INSTALL_DIR/doc" "$INSTALL_DIR/mkspecs" "$INSTALL_DIR/lib/cmake" "$INSTALL_DIR/lib/pkgconfig"
find "$INSTALL_DIR/lib" -name '*.prl' -delete 2>/dev/null || true
find "$INSTALL_DIR/lib" -name '*.la' -delete 2>/dev/null || true

echo "Installed Qt5 to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
