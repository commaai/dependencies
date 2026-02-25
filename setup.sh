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
  brew install nasm pkg-config
elif command -v dnf &>/dev/null; then
  dnf install -y nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd \
    mesa-libGL-devel libxcb-devel xcb-util-devel xcb-util-image-devel \
    xcb-util-keysyms-devel xcb-util-renderutil-devel xcb-util-wm-devel \
    fontconfig-devel freetype-devel libX11-devel \
    libxkbcommon-devel libxkbcommon-x11-devel at-spi2-core-devel perl
elif command -v apt-get &>/dev/null; then
  run_as_root apt-get update
  run_as_root apt-get install -y nasm cmake g++ pkg-config curl \
    libgl1-mesa-dev libxcb1-dev libxcb-icccm4-dev libxcb-image0-dev \
    libxcb-keysyms1-dev libxcb-randr0-dev libxcb-render-util0-dev \
    libxcb-shape0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev \
    libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev \
    libfontconfig1-dev libfreetype-dev perl
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
