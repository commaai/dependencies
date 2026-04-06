#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="20.1.4"
INSTALL_DIR="$DIR/llvm/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Clone/update source
if [ ! -d "llvm-src/.git" ]; then
  rm -rf llvm-src
  git clone --depth 1 https://github.com/llvm/llvm-project.git llvm-src
fi
git -C llvm-src fetch --depth 1 origin "llvmorg-${VERSION}"
git -C llvm-src checkout --force FETCH_HEAD

# Build
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

cmake -S llvm-src/llvm -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC" \
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
  -DLLVM_BUILD_LLVM_DYLIB=ON \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF

# only build the shared library target (lives in tools/llvm-shlib)
cmake --build "$DIR/build" --target LLVM -j"$NJOBS"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"

UNAME="$(uname)"
if [ "$UNAME" = "Darwin" ]; then
  cp -P "$DIR/build/lib"/libLLVM*.dylib "$INSTALL_DIR/lib/"
  strip -x "$INSTALL_DIR/lib"/libLLVM*.dylib 2>/dev/null || true
else
  cp -P "$DIR/build/lib"/libLLVM*.so* "$INSTALL_DIR/lib/"
  strip "$INSTALL_DIR/lib"/libLLVM*.so* 2>/dev/null || true
fi

echo "Installed llvm to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
