#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" = "Darwin" ]; then
  brew install nasm pkg-config
elif command -v apk >/dev/null; then
  apk add --no-cache nasm cmake g++ pkgconf make git perl linux-headers curl tar
else
  sudo apt-get update && sudo apt-get install -y nasm cmake g++ pkg-config
fi
