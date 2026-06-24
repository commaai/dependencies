#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

echo "Publishing wheels to PyPI"

shopt -s nullglob
wheels=(dist/*.whl)
shopt -u nullglob

if [[ ${#wheels[@]} -eq 0 ]]; then
  echo "no wheels in dist/" >&2
  exit 1
fi

echo "Uploading ${#wheels[@]} wheel(s):"
printf '  %s\n' "${wheels[@]}"

uvx twine upload "${wheels[@]}"
