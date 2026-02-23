#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" = "Darwin" ]; then
  brew install nasm pkg-config
else
  sudo apt-get update && sudo apt-get install -y nasm cmake g++ pkg-config
fi
