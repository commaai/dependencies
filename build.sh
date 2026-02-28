#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

if [[ $# -gt 0 ]]; then
  echo "usage: MANYLINUX=1 ./build.sh  or  MUSL=1 ./build.sh" >&2
  exit 2
fi

USE_MANYLINUX="${MANYLINUX:-0}"
USE_MUSL="${MUSL:-0}"

if [[ -z "${BUILD_SH_IN_MANYLINUX:-}" ]] && [[ -z "${BUILD_SH_IN_MUSL:-}" ]] && ! command -v uv >/dev/null 2>&1; then
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

if [[ "$USE_MUSL" == "1" && -z "${BUILD_SH_IN_MUSL:-}" ]]; then
  docker run --rm \
    -e BUILD_SH_IN_MUSL=1 \
    -e BUILD_SH_REUSE_MUSL_ARTIFACTS="${BUILD_SH_REUSE_MUSL_ARTIFACTS:-}" \
    -e HOME=/tmp \
    -e UV_CACHE_DIR=/work/.uv-cache \
    -v "$ROOT_DIR:/work" \
    -w /work \
    "alpine:3.21" \
    sh -c 'apk add --no-cache bash python3 nasm cmake g++ pkgconf make git perl linux-headers curl tar && bash build.sh'
  exit 0
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"

  ./setup.sh

  if [[ -z "${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" ]]; then
    for toml in */pyproject.toml; do
      pkg="${toml%/pyproject.toml}"
      module="${pkg//-/_}"
      rm -rf "$pkg/$module/install" "$pkg/$module/toolchain" "$pkg/$module/bin"
    done
  fi
fi

if [[ -n "${BUILD_SH_IN_MUSL:-}" ]]; then
  ./setup.sh
  export PATH="$HOME/.local/bin:$PATH"

  if [[ -z "${BUILD_SH_REUSE_MUSL_ARTIFACTS:-}" ]]; then
    for toml in */pyproject.toml; do
      pkg="${toml%/pyproject.toml}"
      module="${pkg//-/_}"
      rm -rf "$pkg/$module/install" "$pkg/$module/toolchain" "$pkg/$module/bin"
    done
  fi
fi

echo "Building workspace packages into dist"
START_SECS=$SECONDS

uv build --all-packages --wheel --out-dir dist --no-create-gitignore --no-build-logs

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  VENV_DIR="$ROOT_DIR/.venv-manylinux"
elif [[ -n "${BUILD_SH_IN_MUSL:-}" ]]; then
  VENV_DIR="$ROOT_DIR/.venv-musl"
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
