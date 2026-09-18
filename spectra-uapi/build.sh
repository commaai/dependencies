#!/usr/bin/env bash
set -euo pipefail

AGNOS_REPO="https://github.com/commaai/agnos-kernel-sdm845.git"
AGNOS_COMMIT="c368754c26c7b9659de187addc6cccedc6cfb0a0"
CAMERA_KT_REPO="https://github.com/qualcomm-linux/camera-driver.git"
CAMERA_KT_COMMIT="56b463cba50c1db1f2cc53ddd8790730f14bd8a8"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"
INSTALL_DIR="$DIR/spectra_uapi/install"
rm -rf "$INSTALL_DIR"

install_headers() {
  local abi="$1" repo="$2" commit="$3" headers="$4" license="$5"
  local src="$abi-src"
  if [ ! -d "$src/.git" ]; then
    git clone --depth 1 --filter=blob:none --sparse --no-checkout "$repo" "$src"
  fi
  git -C "$src" sparse-checkout set "$headers"
  git -C "$src" fetch --depth 1 origin "$commit"
  git -C "$src" checkout --force FETCH_HEAD

  mkdir -p "$INSTALL_DIR/$abi/include/media" "$INSTALL_DIR/$abi/licenses"
  cp "$src/$headers"/cam_*.h "$INSTALL_DIR/$abi/include/media/"
  cp "$src/$license" "$INSTALL_DIR/$abi/licenses/"
}

install_headers agnos "$AGNOS_REPO" "$AGNOS_COMMIT" include/uapi/media COPYING
cp agnos-src/include/uapi/media/msm_camsensor_sdk.h "$INSTALL_DIR/agnos/include/media/"

install_headers camera_kt "$CAMERA_KT_REPO" "$CAMERA_KT_COMMIT" camera_kt/include/uapi/camera/media LICENSE.txt
