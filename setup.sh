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
  dnf install -y nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd
elif command -v apt-get &>/dev/null; then
  run_as_root apt-get update
  run_as_root apt-get install -y nasm cmake g++ pkg-config curl
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
