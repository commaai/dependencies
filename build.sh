#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

if [[ $# -gt 0 ]]; then
  echo "usage: MANYLINUX=1 ./build.sh" >&2
  exit 2
fi

USE_MANYLINUX="${MANYLINUX:-0}"

if [[ -z "${BUILD_SH_IN_MANYLINUX:-}" ]] && ! command -v uv >/dev/null 2>&1; then
  ./setup.sh
fi

if [[ "$USE_MANYLINUX" == "1" && -z "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  UV_BIN="$(command -v uv)"
  docker run --rm \
    -e BUILD_SH_IN_MANYLINUX=1 \
    -e BUILD_SH_REUSE_MANYLINUX_ARTIFACTS="${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" \
    -e HOME=/tmp \
    -e UV_CACHE_DIR=/work/.uv-cache \
    -e UV_PYTHON=/opt/python/cp312-cp312/bin/python3 \
    -v "$ROOT_DIR:/work" \
    -v "$UV_BIN:/usr/local/bin/uv:ro" \
    -w /work \
    "quay.io/pypa/manylinux_2_28_$(uname -m)" \
    bash build.sh
  exit 0
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"

  # cached *-src repos may be owned by the host runner user; tell git to trust them
  git config --global --add safe.directory '*'

  ./setup.sh

  if [[ -z "${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" ]]; then
    for toml in */pyproject.toml; do
      pkg="${toml%/pyproject.toml}"
      module="${pkg//-/_}"
      rm -rf "$pkg/$module/install" "$pkg/$module/toolchain" "$pkg/$module/bin"
    done
  fi
fi

export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "Building workspace packages into dist"
START_SECS=$SECONDS

mkdir -p dist/
rm -rf dist/*
uv build --all-packages --wheel --out-dir dist --no-create-gitignore --no-build-logs

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

du -hs dist/* | sort -hr

echo
echo "Done in $((SECONDS - START_SECS))s"
