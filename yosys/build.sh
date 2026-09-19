#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

YOSYS_REV="70a11c6bf0e8dd669f56c7da3587f78b405138e2" # v0.63
NEXTPNR_REV="3e53a0bf44d13c0de603dd089a323ea85d67d4ef"
INSTALL_DIR="$DIR/yosys/install"
PYTHON="${PYTHON:-python3}"
NJOBS="${NJOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}"

checkout() {
  local name="$1" rev="$2"
  if [ ! -d "$name-src/.git" ]; then
    git clone --no-checkout --depth 1 "https://github.com/YosysHQ/$name.git" "$name-src"
  fi
  git -C "$name-src" fetch --depth 1 origin "$rev"
  git -C "$name-src" checkout --force FETCH_HEAD
}

checkout yosys "$YOSYS_REV"
git -C yosys-src submodule update --init --recursive --depth 1
checkout nextpnr "$NEXTPNR_REV"

# Static Linux executables avoid runtime dependencies on the build host's libraries.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64|Linux-aarch64)
    YOSYS_CONFIG=gcc-static
    NEXTPNR_STATIC=ON
    ;;
  Darwin-arm64)
    YOSYS_CONFIG=clang
    NEXTPNR_STATIC=OFF
    export MACOSX_DEPLOYMENT_TARGET=11.0
    export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
    ;;
  *) echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

make -C yosys-src -j"$NJOBS" \
  CONFIG="$YOSYS_CONFIG" PREFIX="$INSTALL_DIR" ENABLE_CCACHE=1 \
  ENABLE_TCL=0 ENABLE_READLINE=0 ENABLE_PLUGINS=0 ENABLE_ZLIB=0

cmake -S nextpnr-src -B build/nextpnr \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DPython3_EXECUTABLE="$(command -v "$PYTHON")" \
  -DARCH=himbaechel -DHIMBAECHEL_UARCH=gowin \
  '-DHIMBAECHEL_GOWIN_DEVICES=GW5A-25A;GW5AT-60B;GW5AST-138C' \
  -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF -DUSE_IPO=OFF \
  -DSTATIC_BUILD="$NEXTPNR_STATIC" -DBoost_USE_STATIC_LIBS=ON
cmake --build build/nextpnr -j"$NJOBS"

rm -rf "$INSTALL_DIR"
make -C yosys-src install PREFIX="$INSTALL_DIR" CONFIG="$YOSYS_CONFIG" \
  ENABLE_CCACHE=1 ENABLE_TCL=0 ENABLE_READLINE=0 ENABLE_PLUGINS=0 ENABLE_ZLIB=0
cmake --install build/nextpnr --strip

# Keep the synthesis executables and their data, plus upstream license notices.
find "$INSTALL_DIR/bin" -type f ! -name yosys ! -name yosys-abc ! -name nextpnr-himbaechel -delete
rm -rf "$INSTALL_DIR/include" "$INSTALL_DIR/share/man"
mkdir -p "$INSTALL_DIR/share/licenses"
cp yosys-src/COPYING "$INSTALL_DIR/share/licenses/yosys.txt"
cp yosys-src/abc/copyright.txt "$INSTALL_DIR/share/licenses/abc.txt"
cp nextpnr-src/COPYING "$INSTALL_DIR/share/licenses/nextpnr.txt"
strip "$INSTALL_DIR/bin/yosys" "$INSTALL_DIR/bin/yosys-abc"
du -sh "$INSTALL_DIR"
