#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

TOOLCHAIN_VERSION="13.2.rel1"
TOOLCHAIN_BASE="arm-gnu-toolchain-${TOOLCHAIN_VERSION}"
GCC_VERSION="13.2.1"

INSTALL_DIR="$DIR/gcc_arm_none_eabi/toolchain"
VERSION_FILE="$INSTALL_DIR/.version"

# Skip if already at correct version
if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$TOOLCHAIN_VERSION" ]; then
  echo "Toolchain $TOOLCHAIN_VERSION already present, skipping."
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

TARBALL="${TOOLCHAIN_BASE}-${PLATFORM_SUFFIX}-arm-none-eabi.tar.xz"
URL="https://developer.arm.com/-/media/Files/downloads/gnu/${TOOLCHAIN_VERSION}/binrel/${TARBALL}"

# Download
echo "Downloading $TARBALL ..."
curl -fSL -o "$TARBALL" "$URL"

# Extract (use Python's lzma to avoid requiring xz-utils on the host)
echo "Extracting ..."
python3 -c "import lzma, tarfile; tarfile.open(fileobj=lzma.open('$TARBALL')).extractall()"
EXTRACT_DIR=$(ls -d arm-gnu-toolchain-*-${PLATFORM_SUFFIX}-arm-none-eabi)

SRC="$DIR/$EXTRACT_DIR"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# --- bin: only the tools directly used by SConscript ---
mkdir -p "$INSTALL_DIR/bin"
for tool in gcc objcopy size; do
  if [ -f "$SRC/bin/arm-none-eabi-$tool" ]; then
    cp "$SRC/bin/arm-none-eabi-$tool" "$INSTALL_DIR/bin/"
  fi
done

# --- libexec: cc1 and collect2 (needed by gcc driver) ---
LIBEXEC_SRC="$SRC/libexec/gcc/arm-none-eabi/$GCC_VERSION"
LIBEXEC_DST="$INSTALL_DIR/libexec/gcc/arm-none-eabi/$GCC_VERSION"
mkdir -p "$LIBEXEC_DST"
for f in cc1 collect2 liblto_plugin.so liblto_plugin.0.so; do
  if [ -f "$LIBEXEC_SRC/$f" ]; then
    cp "$LIBEXEC_SRC/$f" "$LIBEXEC_DST/"
  fi
done

# --- arm-none-eabi/bin: only tools gcc calls internally ---
ARM_SRC="$SRC/arm-none-eabi"
ARM_DST="$INSTALL_DIR/arm-none-eabi"
mkdir -p "$ARM_DST/bin"
for tool in as ld ld.bfd; do
  if [ -f "$ARM_SRC/bin/$tool" ]; then
    cp "$ARM_SRC/bin/$tool" "$ARM_DST/bin/"
  fi
done

# --- newlib C headers (needed for #include_next from GCC's stdint.h etc.) ---
mkdir -p "$ARM_DST/include"
find "$ARM_SRC/include" -maxdepth 1 -not -name 'c++' | while read -r item; do
  [ "$item" = "$ARM_SRC/include" ] && continue
  cp -r "$item" "$ARM_DST/include/"
done

# --- lib/gcc: compiler support (only the multilib we use) ---
LIB_GCC_SRC="$SRC/lib/gcc/arm-none-eabi/$GCC_VERSION"
LIB_GCC_DST="$INSTALL_DIR/lib/gcc/arm-none-eabi/$GCC_VERSION"
MULTILIB="thumb/v7e-m+dp/hard"
mkdir -p "$LIB_GCC_DST/$MULTILIB"

# compiler-provided headers
cp -r "$LIB_GCC_SRC/include" "$LIB_GCC_DST/"
if [ -d "$LIB_GCC_SRC/include-fixed" ]; then
  cp -r "$LIB_GCC_SRC/include-fixed" "$LIB_GCC_DST/"
fi

# target multilib: only thumb/v7e-m+dp/hard (cortex-m7 hard-float)
cp "$LIB_GCC_SRC/$MULTILIB"/libgcc.a "$LIB_GCC_DST/$MULTILIB/"
cp "$LIB_GCC_SRC/$MULTILIB"/crt*.o "$LIB_GCC_DST/$MULTILIB/" 2>/dev/null || true

# --- remove unused headers ---
rm -f "$LIB_GCC_DST/include/arm_neon.h"
rm -f "$LIB_GCC_DST/include/arm_mve_types.h"
rm -f "$LIB_GCC_DST/include/mmintrin.h"
rm -f "$LIB_GCC_DST/include/ISO_Fortran_binding.h"
rm -f "$LIB_GCC_DST/include/gcov.h"
rm -f "$LIB_GCC_DST/include/arm_cde.h"

# --- strip host binaries ---
find "$INSTALL_DIR" -type f \( -executable -o -name '*.so' \) -exec strip {} + 2>/dev/null || true

# --- clean up download artifacts ---
rm -rf "$EXTRACT_DIR"
rm -f "$TARBALL"
echo "$TOOLCHAIN_VERSION" > "$VERSION_FILE"

echo "Installed to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
