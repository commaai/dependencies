#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

if ! command -v uvx >/dev/null 2>&1; then
  UV_BIN_DIR="$HOME/.local/bin"
  mkdir -p "$UV_BIN_DIR"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$UV_BIN_DIR" sh
  export PATH="$UV_BIN_DIR:$PATH"
fi

shopt -s nullglob
wheels=(dist/*.whl)
shopt -u nullglob

if [[ ${#wheels[@]} -eq 0 ]]; then
  echo "no wheels in dist/" >&2
  exit 1
fi

echo "Publishing ${#wheels[@]} wheel(s) to PyPI:"
printf '  %s\n' "${wheels[@]}"

uvx twine upload --skip-existing "${wheels[@]}"
