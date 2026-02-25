#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

ORIGINAL_ARGS=("$@")
DIST_DIR="dist"
USE_MANYLINUX=0

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manylinux)
      USE_MANYLINUX=1
      shift
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ $USE_MANYLINUX -eq 1 && -z "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  [[ "$(uname -s)" == "Linux" ]] || die "--manylinux is only supported on Linux hosts"
  command -v docker >/dev/null 2>&1 || die "docker is required for --manylinux"
  UV_BIN="$(command -v uv || true)"
  [[ -n "$UV_BIN" ]] || die "uv must be installed on host before using --manylinux"

  ARCH="$(uname -m)"
  IMAGE="quay.io/pypa/manylinux_2_28_${ARCH}"

  exec docker run --rm \
    -e BUILD_SH_IN_MANYLINUX=1 \
    -e UV_PYTHON=/opt/python/cp312-cp312/bin/python3 \
    -v "$ROOT_DIR:/work" \
    -v "$UV_BIN:/usr/local/bin/uv:ro" \
    -w /work \
    "$IMAGE" \
    bash build.sh "${ORIGINAL_ARGS[@]}"
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" && -d /opt/python/cp312-cp312/bin ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"
fi

command -v uv >/dev/null 2>&1 || die "uv not found in PATH"

mkdir -p "$DIST_DIR"

echo "Building workspace packages into $DIST_DIR"
START_SECS=$SECONDS

uv build --all-packages --wheel --clear --out-dir "$DIST_DIR" --no-create-gitignore --no-build-logs

echo
echo "Running smoketests"

VENV_DIR="$ROOT_DIR/.venv"
uv venv --allow-existing --quiet "$VENV_DIR" >/dev/null
uv pip install --python "$VENV_DIR/bin/python" --reinstall --no-deps --quiet "$DIST_DIR"/*.whl >/dev/null

for toml in */pyproject.toml; do
  module="$(basename "$(dirname "$toml")" | tr '-' '_')"
  "$VENV_DIR/bin/python" -c "import $module; $module.smoketest(); print('$module: OK')"
done

echo
echo "Done in $((SECONDS - START_SECS))s"
