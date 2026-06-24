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

echo "Found ${#wheels[@]} wheel(s):"
printf '  %s\n' "${wheels[@]}"

upload_dir="$(mktemp -d)"
trap 'rm -rf "$upload_dir"' EXIT
cp "${wheels[@]}" "$upload_dir"/

retag_linux_wheels() {
  local from_platform="$1"
  local to_platform="$2"

  shopt -s nullglob
  local platform_wheels=("$upload_dir"/*-"$from_platform".whl)
  shopt -u nullglob

  if [[ ${#platform_wheels[@]} -gt 0 ]]; then
    uvx --from wheel wheel tags --remove --platform-tag "$to_platform" "${platform_wheels[@]}"
  fi
}

# PyPI rejects generic linux_* binary wheel tags. The packages are built in
# manylinux_2_28 containers in CI, so only rewrite the upload copies.
retag_linux_wheels linux_x86_64 manylinux_2_28_x86_64
retag_linux_wheels linux_aarch64 manylinux_2_28_aarch64
retag_linux_wheels linux_arm64 manylinux_2_28_aarch64

shopt -s nullglob
upload_wheels=("$upload_dir"/*.whl)
shopt -u nullglob

echo "Uploading ${#upload_wheels[@]} PyPI wheel(s):"
printf '  %s\n' "${upload_wheels[@]}"

uvx twine upload --skip-existing "${upload_wheels[@]}"
