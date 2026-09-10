#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="2.21.0"
INSTALL_DIR="$DIR/cppcheck/install"
EXE=""
MAKE_ARGS=()
# static libc++ so the binary runs outside an MSYS2 shell (no libc++.dll on PATH)
case "$(uname -s)" in MINGW*|MSYS*) EXE=".exe"; MAKE_ARGS+=(LDOPTS=-static) ;; esac

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
export CXX="ccache ${CXX:-c++}"

# Clone/update source
if [ ! -d "cppcheck-src/.git" ]; then
  rm -rf cppcheck-src
  git clone --depth 1 https://github.com/danmar/cppcheck.git cppcheck-src
fi
git -C cppcheck-src fetch --depth 1 origin "$VERSION"
git -C cppcheck-src checkout --force FETCH_HEAD

# Build
cd cppcheck-src
make MATCHCOMPILER=yes CXXFLAGS="-O2" "${MAKE_ARGS[@]}" -j"$NJOBS"
cd "$DIR"

# Install
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

cp "cppcheck-src/cppcheck$EXE" "$INSTALL_DIR/"
cp -r cppcheck-src/addons "$INSTALL_DIR/"
cp -r cppcheck-src/cfg "$INSTALL_DIR/"
cp -r cppcheck-src/platforms "$INSTALL_DIR/"
strip "$INSTALL_DIR/cppcheck$EXE" 2>/dev/null || true

echo "Installed cppcheck to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
