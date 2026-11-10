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
  if [[ "$USE_MANYLINUX" == "1" ]]; then
    ./setup.sh --uv-only
  else
    ./setup.sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
fi

if [[ "$USE_MANYLINUX" == "1" && -z "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  UV_BIN="$(command -v uv)"
  # pinned so the image (and everything cached against it) doesn't change under us daily
  MANYLINUX_IMAGE="${MANYLINUX_IMAGE:-quay.io/pypa/manylinux_2_28_$(uname -m):2026.11.07-1}"
  # a git worktree's .git points outside the repo, so mount both at their host paths
  WORK=/work
  GIT_MOUNT=()
  GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
  if [[ "$GIT_COMMON_DIR" != "$ROOT_DIR/.git" ]]; then
    WORK="$ROOT_DIR"
    GIT_MOUNT=(-v "$GIT_COMMON_DIR:$GIT_COMMON_DIR:ro")
  fi
  docker run --rm \
    -e BUILD_SH_IN_MANYLINUX=1 \
    -e DEPENDENCIES_NATIVE_CACHE="${DEPENDENCIES_NATIVE_CACHE:-}" \
    -e DEPENDENCIES_BUILDER_ID="$MANYLINUX_IMAGE" \
    -e BUILD_SH_REUSE_MANYLINUX_ARTIFACTS="${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" \
    -e BUILD_SH_HOST_UID="$(id -u)" \
    -e BUILD_SH_HOST_GID="$(id -g)" \
    -e HOME=/tmp \
    -e UV_CACHE_DIR="$WORK/.uv-cache" \
    -e CCACHE_DIR="$WORK/.ccache" \
    -e UV_PYTHON=/opt/python/cp312-cp312/bin/python3 \
    -v "$ROOT_DIR:$WORK" \
    -v "$UV_BIN:/usr/local/bin/uv:ro" \
    "${GIT_MOUNT[@]}" \
    -w "$WORK" \
    "$MANYLINUX_IMAGE" \
    bash build.sh
  exit 0
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"

  # cached *-src repos may be owned by the host runner user; tell git to trust them
  git config --global --add safe.directory '*'

  if [[ -z "${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" ]]; then
    for toml in */pyproject.toml; do
      pkg="${toml%/pyproject.toml}"
      module="${pkg//-/_}"
      rm -rf "$pkg/$module/install" "$pkg/$module/toolchain" "$pkg/$module/bin"
    done
  fi
fi

# CI only: reuse native build outputs of packages whose inputs haven't changed
unset DEPENDENCIES_PREBUILT
if [[ -n "${DEPENDENCIES_NATIVE_CACHE:-}" ]]; then
  DEPENDENCIES_PREBUILT="$(python3 build_native_cache.py restore "$DEPENDENCIES_NATIVE_CACHE")"
  export DEPENDENCIES_PREBUILT
fi

# build deps are only needed if something actually gets built
if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  PACKAGES=(*/pyproject.toml)
  IFS=, read -ra PREBUILT <<< "${DEPENDENCIES_PREBUILT:-}"
  if [[ "${#PREBUILT[@]}" -ne "${#PACKAGES[@]}" ]]; then
    ./setup.sh
  fi
fi

export CMAKE_C_COMPILER_LAUNCHER=ccache
export CMAKE_CXX_COMPILER_LAUNCHER=ccache
export CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"

restore_build_versions() {
  python3 build_versions.py restore */pyproject.toml
}

trap restore_build_versions EXIT

echo "Building workspace packages into dist"
START_SECS=$SECONDS

mkdir -p dist/
rm -rf dist/*

# PyPI files are immutable, so each build gets a fresh .postN version. The
# committed pyproject.toml files keep the clean upstream version; the suffix
# only exists while the wheels are built.
POST_N="${DEPENDENCIES_POST_VERSION_N:-$(git rev-list --count HEAD)}"
echo "Applying .post$POST_N package versions for this build"
python3 build_versions.py apply "$POST_N" */pyproject.toml
uv build --all-packages --wheel --out-dir dist --no-create-gitignore
restore_build_versions

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  VENV_DIR="$ROOT_DIR/.venv-manylinux"
else
  VENV_DIR="$ROOT_DIR/.venv"
fi

echo
echo "Running smoketests"

uv venv --allow-existing --quiet "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" --quiet "cffi>=1.17.1" >/dev/null
uv pip install --python "$VENV_DIR/bin/python" --reinstall --no-deps --quiet dist/*.whl >/dev/null

for toml in */pyproject.toml; do
  module="$(basename "$(dirname "$toml")" | tr '-' '_')"
  "$VENV_DIR/bin/python" -c "import $module; $module.smoketest()" >/dev/null
done

if [[ -n "${DEPENDENCIES_NATIVE_CACHE:-}" ]]; then
  python3 build_native_cache.py save "$DEPENDENCIES_NATIVE_CACHE"
fi

du -hs dist/* | sort -hr

echo
echo "Done in $((SECONDS - START_SECS))s"

# Hand workspace ownership back to the host runner so actions/cache can
# tar everything we just produced (manylinux runs as root).
if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" && -n "${BUILD_SH_HOST_UID:-}" ]]; then
  chown -R "$BUILD_SH_HOST_UID:${BUILD_SH_HOST_GID:-0}" "$ROOT_DIR"
fi
