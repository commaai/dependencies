#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
if command -v ccache &>/dev/null; then
  CC="ccache ${CC:-cc}"
else
  CC="${CC:-cc}"
fi

is_linux_aarch64() {
  [[ "$(uname)" == "Linux" && ( "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ) ]]
}

if [ -n "${RAYLIB_PLATFORM:-}" ]; then
  echo "RAYLIB_PLATFORM is no longer supported; use RAYLIB_BACKEND=desktop or RAYLIB_BACKEND=comma" >&2
  exit 1
fi

# An explicit RAYLIB_BACKEND builds only that backend; otherwise all of the
# host's backends are built (matches host_backends() in raylib/_backend.py)
RAYLIB_BACKEND="${RAYLIB_BACKEND:-}"
case "$RAYLIB_BACKEND" in
  ""|desktop|comma|headless) ;;
  *)
    echo "Unsupported RAYLIB_BACKEND=$RAYLIB_BACKEND; expected desktop, comma or headless" >&2
    exit 1
    ;;
esac

# Clone and build raylib C library
RAYLIB_COMMIT="caa64e15ac20a47804a8048029c921ac091fef12"
MESA_VERSION="26.2.1"
LLVM_VERSION="22.1.8"

if [ ! -d "raylib-src/.git" ]; then
  rm -rf raylib-src
  git clone --depth 1 -b master --no-tags https://github.com/commaai/raylib.git raylib-src
fi

cd raylib-src
git remote set-url origin https://github.com/commaai/raylib.git
if ! git cat-file -e "$RAYLIB_COMMIT" 2>/dev/null; then
  git fetch --depth 1 origin "$RAYLIB_COMMIT"
fi
git reset --hard "$RAYLIB_COMMIT"

cd "$DIR"

# Install lib + headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

cp raylib-src/src/raylib.h raylib-src/src/raymath.h raylib-src/src/rlgl.h "$INSTALL_DIR/include/"

build_raylib() {
  local platform="$1"
  local output="$2"

  cd "$DIR/raylib-src/src"
  make clean
  make -j"$NJOBS" PLATFORM="$platform" CC="${CC:-gcc}"
  cp libraylib.a "$INSTALL_DIR/lib/$output"
  cd "$DIR"
}

# a re-checkout of an already pinned tree rewrites mtimes and rebuilds everything
checkout_tag() {  # <dir> <tag>
  [ "$(git -C "$1" describe --tags --exact-match 2>/dev/null)" = "$2" ] && return
  git -C "$1" fetch --depth 1 origin tag "$2"
  git -C "$1" checkout -q --force "$2"
}

backend_platform() {
  case "$1" in
    desktop) echo PLATFORM_DESKTOP ;;
    comma) echo PLATFORM_COMMA ;;
    headless) echo PLATFORM_HEADLESS ;;
  esac
}

if [ -n "$RAYLIB_BACKEND" ]; then
  BACKENDS="$RAYLIB_BACKEND"
elif [ "$(uname)" == "Linux" ]; then
  BACKENDS="desktop headless"
  if is_linux_aarch64; then
    BACKENDS="$BACKENDS comma"
  fi
else
  BACKENDS="desktop"
fi

for backend in $BACKENDS; do
  echo "Building $backend backend..."
  build_raylib "$(backend_platform "$backend")" "libraylib_${backend}.a"
done

if [ "$(uname)" == "Linux" ] && [[ " $BACKENDS " == *" headless "* ]]; then
  [ -d llvm-src/.git ] || git clone --depth 1 --filter=blob:none --sparse -b "llvmorg-$LLVM_VERSION" https://github.com/llvm/llvm-project.git llvm-src
  git -C llvm-src sparse-checkout set llvm cmake third-party
  checkout_tag llvm-src "llvmorg-$LLVM_VERSION"
  cmake -S llvm-src/llvm -B llvm-src/build -G Ninja -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_INSTALL_PREFIX="$DIR/llvm-src/prefix" \
    -DLLVM_TARGETS_TO_BUILD=Native -DLLVM_BUILD_TOOLS=OFF -DLLVM_TOOL_LLVM_CONFIG_BUILD=ON -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_FFI=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" -DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections" >/dev/null
  ninja -C llvm-src/build install llvm-config >/dev/null
  cp llvm-src/build/bin/llvm-config llvm-src/prefix/bin/

  [ -d mesa-src/.git ] || git clone --depth 1 -b "mesa-$MESA_VERSION" https://gitlab.freedesktop.org/mesa/mesa.git mesa-src
  checkout_tag mesa-src "mesa-$MESA_VERSION"
  PATH="$DIR/llvm-src/prefix/bin:$PATH" meson setup mesa-src mesa-src/build --reconfigure --prefix="$DIR/mesa-src/build/prefix" --libdir=lib \
    -Db_ndebug=true -Dcpp_rtti=false -Dc_link_args=-Wl,--gc-sections -Dcpp_link_args=-Wl,--gc-sections \
    -Dplatforms= -Degl=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=false -Dglx=disabled \
    -Dgbm=disabled -Dglvnd=disabled -Dgallium-drivers=llvmpipe -Dvulkan-drivers= -Dshared-llvm=disabled \
    -Dlibunwind=disabled -Dzstd=disabled -Dvalgrind=disabled -Dbuild-tests=false \
    -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled
  ninja -C mesa-src/build install >/dev/null
  cp mesa-src/build/prefix/lib/{libEGL.so.1,libGLESv2.so.2,libgallium-$MESA_VERSION.so} "$INSTALL_DIR/lib/"
  cp -L "$(cc -print-file-name=libdrm.so.2)" "$INSTALL_DIR/lib/"
  patchelf --set-rpath '$ORIGIN' "$INSTALL_DIR"/lib/{libEGL.so.1,libGLESv2.so.2,libgallium-$MESA_VERSION.so}
  strip "$INSTALL_DIR"/lib/*.so*
fi

# Download raygui header
RAYGUI_COMMIT="1e03efca48c50c5ea4b4a053d5bf04bad58d3e43"
curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
