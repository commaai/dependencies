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

# PyPI rate-limits new project creation (429), and --skip-existing makes
# retries idempotent, so back off and retry until the window resets.
for wait_secs in 60 120 300 600 900 0; do
  if uvx twine upload --skip-existing "${wheels[@]}"; then
    exit 0
  fi
  if [[ $wait_secs -eq 0 ]]; then
    break
  fi
  echo "upload failed; retrying in ${wait_secs}s"
  sleep "$wait_secs"
done

echo "upload failed after all retries" >&2
exit 1
