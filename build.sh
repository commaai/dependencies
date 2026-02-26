#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

USE_MANYLINUX=0
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--manylinux" && $# -eq 1 ]]; then
    USE_MANYLINUX=1
  else
    echo "usage: ./build.sh [--manylinux]" >&2
    exit 2
  fi
fi

if [[ -z "${BUILD_SH_IN_MANYLINUX:-}" ]] && ! command -v uv >/dev/null 2>&1; then
  ./setup.sh
fi

if [[ $USE_MANYLINUX -eq 1 && -z "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  UV_BIN="$(command -v uv)"
  docker run --rm \
    -e BUILD_SH_HOST_UID="$(id -u)" \
    -e BUILD_SH_HOST_GID="$(id -g)" \
    -e BUILD_SH_IN_MANYLINUX=1 \
    -e HOME=/tmp \
    -e UV_PYTHON=/opt/python/cp312-cp312/bin/python3 \
    -v "$ROOT_DIR:/work" \
    -v "$UV_BIN:/usr/local/bin/uv:ro" \
    -w /work \
    "quay.io/pypa/manylinux_2_28_$(uname -m)" \
    bash build.sh --manylinux
  exit 0
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"

  ./setup.sh

  for toml in */pyproject.toml; do
    pkg="${toml%/pyproject.toml}"
    module="${pkg//-/_}"
    rm -rf "$pkg/$module/install" "$pkg/$module/toolchain" "$pkg/$module/bin"
  done
fi

echo "Building workspace packages into dist"
START_SECS=$SECONDS

uv build --all-packages --wheel --clear --out-dir dist --no-create-gitignore --no-build-logs

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  VENV_DIR="$ROOT_DIR/.venv-manylinux"
else
  VENV_DIR="$ROOT_DIR/.venv"
fi

echo
echo "Running smoketests"

uv venv --allow-existing --quiet "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" --reinstall --no-deps --quiet dist/*.whl >/dev/null

for toml in */pyproject.toml; do
  module="$(basename "$(dirname "$toml")" | tr '-' '_')"
  "$VENV_DIR/bin/python" -c "import $module; $module.smoketest()" >/dev/null
done

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  chown -R "${BUILD_SH_HOST_UID}:${BUILD_SH_HOST_GID}" dist .venv-manylinux
  for toml in */pyproject.toml; do
    pkg="${toml%/pyproject.toml}"
    chown -R "${BUILD_SH_HOST_UID}:${BUILD_SH_HOST_GID}" "$pkg"
  done
fi

echo
echo "Done in $((SECONDS - START_SECS))s"
