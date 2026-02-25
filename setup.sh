#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" = "Darwin" ]; then
  brew install nasm pkg-config
elif command -v dnf &>/dev/null; then
  dnf install -y nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd
elif command -v apt-get &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y nasm cmake g++ pkg-config
fi
