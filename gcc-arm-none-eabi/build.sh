#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

TOOLCHAIN_VERSION="13.2.rel1"
TOOLCHAIN_BASE="arm-gnu-toolchain-${TOOLCHAIN_VERSION}"
GCC_VERSION="13.2.1"

INSTALL_DIR="$DIR/gcc_arm_none_eabi/toolchain"

# Idempotent: skip if already built
if [ -x "$INSTALL_DIR/bin/arm-none-eabi-gcc" ]; then
  echo "Toolchain already present, skipping download."
  exit 0
fi

# Detect current platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}-${ARCH}" in
  Linux-x86_64)   PLATFORM_SUFFIX="x86_64" ;;
  Linux-aarch64)  PLATFORM_SUFFIX="aarch64" ;;
  Darwin-arm64)   PLATFORM_SUFFIX="darwin-arm64" ;;
  *)
    echo "Unsupported platform: ${OS}-${ARCH}" >&2
    exit 1
    ;;
esac

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Download ARM's pre-built tarball (always needed for target headers/libraries)
TARBALL="${TOOLCHAIN_BASE}-${PLATFORM_SUFFIX}-arm-none-eabi.tar.xz"
URL="https://developer.arm.com/-/media/Files/downloads/gnu/${TOOLCHAIN_VERSION}/binrel/${TARBALL}"

echo "Downloading $TARBALL ..."
curl -fSL -o "$TARBALL" "$URL"

echo "Extracting ..."
python3 -c "import lzma, tarfile; tarfile.open(fileobj=lzma.open('$TARBALL')).extractall()"
EXTRACT_DIR=$(ls -d arm-gnu-toolchain-*-${PLATFORM_SUFFIX}-arm-none-eabi)

SRC="$DIR/$EXTRACT_DIR"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

if [ -f "/lib/ld-musl-${ARCH}.so.1" ]; then
  # musl: pre-built glibc binaries won't work, build host tools from source
  echo "musl detected -- building host tools from source..."

  PREFIX="$DIR/_build/prefix"
  mkdir -p "$DIR/_build"
  export PATH="$PREFIX/bin:$PATH"

  # --- binutils ---
  BINUTILS_VER="2.41"
  echo "=== Building binutils ${BINUTILS_VER} ==="
  curl -fSL -o "binutils.tar.xz" "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
  python3 -c "import lzma, tarfile; tarfile.open(fileobj=lzma.open('binutils.tar.xz')).extractall()"
  mkdir -p "$DIR/_build/binutils"
  cd "$DIR/_build/binutils"
  "$DIR/binutils-${BINUTILS_VER}/configure" \
    --target=arm-none-eabi --prefix="$PREFIX" \
    --disable-nls --disable-werror --disable-gdb --disable-sim \
    --disable-libdecnumber --disable-readline
  make -j"$NJOBS"
  make install
  cd "$DIR"

  # --- GCC (C only, no target libs -- we use the pre-built ones) ---
  GCC_SRC_VER="13.2.0"
  echo "=== Building GCC ${GCC_SRC_VER} ==="
  curl -fSL -o "gcc.tar.xz" "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_SRC_VER}/gcc-${GCC_SRC_VER}.tar.xz"
  python3 -c "import lzma, tarfile; tarfile.open(fileobj=lzma.open('gcc.tar.xz')).extractall()"
  cd "gcc-${GCC_SRC_VER}"
  ./contrib/download_prerequisites
  cd "$DIR"
  mkdir -p "$DIR/_build/gcc"
  cd "$DIR/_build/gcc"
  "$DIR/gcc-${GCC_SRC_VER}/configure" \
    --target=arm-none-eabi --prefix="$PREFIX" \
    --enable-languages=c --without-headers --with-newlib \
    --disable-nls --disable-shared --disable-threads \
    --disable-libssp --disable-libgomp --disable-libquadmath \
    --with-multilib-list=rmprofile
  make -j"$NJOBS" all-gcc
  make install-gcc
  cd "$DIR"

  BUILT_VER=$("$PREFIX/bin/arm-none-eabi-gcc" -dumpversion)

  # Install source-built host binaries
  mkdir -p "$INSTALL_DIR/bin"
  for tool in gcc objcopy size; do
    cp "$PREFIX/bin/arm-none-eabi-$tool" "$INSTALL_DIR/bin/"
  done

  LIBEXEC_SRC="$PREFIX/libexec/gcc/arm-none-eabi/$BUILT_VER"
  LIBEXEC_DST="$INSTALL_DIR/libexec/gcc/arm-none-eabi/$BUILT_VER"
  mkdir -p "$LIBEXEC_DST"
  for f in cc1 collect2 liblto_plugin.so liblto_plugin.0.so; do
    [ -f "$LIBEXEC_SRC/$f" ] && cp "$LIBEXEC_SRC/$f" "$LIBEXEC_DST/"
  done

  ARM_DST="$INSTALL_DIR/arm-none-eabi"
  mkdir -p "$ARM_DST/bin"
  for tool in as ld ld.bfd; do
    [ -f "$PREFIX/arm-none-eabi/bin/$tool" ] && cp "$PREFIX/arm-none-eabi/bin/$tool" "$ARM_DST/bin/"
  done

  LIB_GCC_DST="$INSTALL_DIR/lib/gcc/arm-none-eabi/$BUILT_VER"

  # Clean up source builds
  rm -rf "binutils-${BINUTILS_VER}" binutils.tar.xz "gcc-${GCC_SRC_VER}" gcc.tar.xz "$DIR/_build"

else
  # glibc / macOS: use pre-built host binaries directly
  mkdir -p "$INSTALL_DIR/bin"
  for tool in gcc objcopy size; do
    [ -f "$SRC/bin/arm-none-eabi-$tool" ] && cp "$SRC/bin/arm-none-eabi-$tool" "$INSTALL_DIR/bin/"
  done

  LIBEXEC_SRC="$SRC/libexec/gcc/arm-none-eabi/$GCC_VERSION"
  LIBEXEC_DST="$INSTALL_DIR/libexec/gcc/arm-none-eabi/$GCC_VERSION"
  mkdir -p "$LIBEXEC_DST"
  for f in cc1 collect2 liblto_plugin.so liblto_plugin.0.so; do
    [ -f "$LIBEXEC_SRC/$f" ] && cp "$LIBEXEC_SRC/$f" "$LIBEXEC_DST/"
  done

  ARM_DST="$INSTALL_DIR/arm-none-eabi"
  mkdir -p "$ARM_DST/bin"
  for tool in as ld ld.bfd; do
    [ -f "$SRC/arm-none-eabi/bin/$tool" ] && cp "$SRC/arm-none-eabi/bin/$tool" "$ARM_DST/bin/"
  done

  LIB_GCC_DST="$INSTALL_DIR/lib/gcc/arm-none-eabi/$GCC_VERSION"
fi

# --- Target files from pre-built tarball (ARM code, host-agnostic) ---

# Newlib C headers
mkdir -p "$ARM_DST/include"
find "$SRC/arm-none-eabi/include" -maxdepth 1 -not -name 'c++' | while read -r item; do
  [ "$item" = "$SRC/arm-none-eabi/include" ] && continue
  cp -r "$item" "$ARM_DST/include/"
done

# Compiler headers + target multilib
LIB_GCC_SRC="$SRC/lib/gcc/arm-none-eabi/$GCC_VERSION"
MULTILIB="thumb/v7e-m+dp/hard"
mkdir -p "$LIB_GCC_DST/$MULTILIB"

cp -r "$LIB_GCC_SRC/include" "$LIB_GCC_DST/"
[ -d "$LIB_GCC_SRC/include-fixed" ] && cp -r "$LIB_GCC_SRC/include-fixed" "$LIB_GCC_DST/"
cp "$LIB_GCC_SRC/$MULTILIB"/libgcc.a "$LIB_GCC_DST/$MULTILIB/"
cp "$LIB_GCC_SRC/$MULTILIB"/crt*.o "$LIB_GCC_DST/$MULTILIB/" 2>/dev/null || true

# Remove unused headers
for h in arm_neon.h arm_mve_types.h mmintrin.h ISO_Fortran_binding.h gcov.h arm_cde.h; do
  rm -f "$LIB_GCC_DST/include/$h"
done

# Strip host binaries
find "$INSTALL_DIR" -type f \( -executable -o -name '*.so' \) -exec strip {} + 2>/dev/null || true

# Clean up download artifacts
rm -rf "$EXTRACT_DIR" "$TARBALL"

echo "Installed to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
