#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="2.16.0"
INSTALL_DIR="$DIR/cppcheck/install"

# Idempotent: skip if already built
if [ -x "$INSTALL_DIR/cppcheck" ]; then
  echo "cppcheck already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone
if [ ! -d "cppcheck-src" ]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/danmar/cppcheck.git cppcheck-src
fi

# Build
cd cppcheck-src
make MATCHCOMPILER=yes CXXFLAGS="-O2" -j"$NJOBS"
cd "$DIR"

# Install
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

cp cppcheck-src/cppcheck "$INSTALL_DIR/"
cp -r cppcheck-src/addons "$INSTALL_DIR/"
cp -r cppcheck-src/cfg "$INSTALL_DIR/"
cp -r cppcheck-src/platforms "$INSTALL_DIR/"
strip "$INSTALL_DIR/cppcheck" 2>/dev/null || true

# Clean up
rm -rf cppcheck-src

echo "Installed cppcheck to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
