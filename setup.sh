#!/usr/bin/env bash
set -euo pipefail

# sets up build-time dependencies (NOT runtime dependencies)

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo &>/dev/null; then
    sudo "$@"
  else
    echo "error: root privileges required for: $*" >&2
    exit 1
  fi
}

if [ "$(uname)" = "Darwin" ]; then
  brew install nasm pkg-config ccache autoconf automake libtool
elif [ "${MSYSTEM:-}" = "CLANG64" ]; then
  pacman -S --needed --noconfirm \
    "$MINGW_PACKAGE_PREFIX-toolchain" "$MINGW_PACKAGE_PREFIX-cmake" "$MINGW_PACKAGE_PREFIX-ninja" \
    "$MINGW_PACKAGE_PREFIX-pkgconf" "$MINGW_PACKAGE_PREFIX-ccache" "$MINGW_PACKAGE_PREFIX-nasm" \
    "$MINGW_PACKAGE_PREFIX-git" "$MINGW_PACKAGE_PREFIX-uv" \
    make autotools patch  # native git: MSYS2's Cygwin-style git hands git-lfs POSIX paths it mis-resolves
elif [ -n "${MSYSTEM:-}" ]; then
  echo "error: the Windows wheels are built with clang, lld and libc++ from an MSYS2 CLANG64 shell, not $MSYSTEM" >&2
  exit 1
elif command -v dnf &>/dev/null; then
  dnf install -y \
    nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd ccache autoconf automake libtool \
    libX11-devel libXcursor-devel libXrandr-devel libXinerama-devel libXi-devel \
    mesa-libGL-devel libdrm-devel mesa-libgbm-devel mesa-libEGL-devel mesa-libGLES-devel
elif command -v apt-get &>/dev/null; then
  run_as_root apt-get update
  run_as_root apt-get install -y \
    nasm cmake g++ pkg-config curl ccache autoconf automake libtool \
    libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev \
    libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev
fi

if ! command -v uv &>/dev/null; then
  command -v curl &>/dev/null || {
    echo "error: curl is required to install uv" >&2
    exit 1
  }
  UV_BIN_DIR="$HOME/.local/bin"
  mkdir -p "$UV_BIN_DIR"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$UV_BIN_DIR" sh
  export PATH="$UV_BIN_DIR:$PATH"
  command -v uv &>/dev/null || {
    echo "error: failed to install uv" >&2
    exit 1
  }
fi
