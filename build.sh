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

restore_workspace_ownership() {
  if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" && -n "${BUILD_SH_HOST_UID:-}" && -n "${BUILD_SH_HOST_GID:-}" ]]; then
    chown -R "${BUILD_SH_HOST_UID}:${BUILD_SH_HOST_GID}" "$ROOT_DIR"
  fi
}

reset_packaged_artifacts_for_manylinux() {
  python3 - "$ROOT_DIR" <<'PY'
import pathlib
import shutil
import sys
import tomllib

root = pathlib.Path(sys.argv[1])

for toml in sorted(root.glob("*/pyproject.toml")):
  pkg_dir = toml.parent
  module = pkg_dir.name.replace("-", "_")
  data = tomllib.load(toml.open("rb"))
  package_data = data.get("tool", {}).get("setuptools", {}).get("package-data", {})
  patterns = package_data.get(module, [])
  roots = {pattern.split("/", 1)[0] for pattern in patterns if pattern}

  for artifact_root in sorted(roots):
    target = pkg_dir / module / artifact_root
    if target.exists():
      shutil.rmtree(target)
      print(f"Removed stale artifact dir: {target}")
PY
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

  docker run --rm \
    -e BUILD_SH_HOST_UID="$(id -u)" \
    -e BUILD_SH_HOST_GID="$(id -g)" \
    -e BUILD_SH_IN_MANYLINUX=1 \
    -e HOME=/tmp \
    -e UV_PYTHON=/opt/python/cp312-cp312/bin/python3 \
    -v "$ROOT_DIR:/work" \
    -v "$UV_BIN:/usr/local/bin/uv:ro" \
    -w /work \
    "$IMAGE" \
    bash build.sh "${ORIGINAL_ARGS[@]}"
  exit 0
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" && -d /opt/python/cp312-cp312/bin ]]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"
fi

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  trap restore_workspace_ownership EXIT
fi

command -v uv >/dev/null 2>&1 || die "uv not found in PATH"

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  ./setup.sh
  reset_packaged_artifacts_for_manylinux
fi

mkdir -p "$DIST_DIR"

echo "Building workspace packages into $DIST_DIR"
START_SECS=$SECONDS

uv build --all-packages --wheel --clear --out-dir "$DIST_DIR" --no-create-gitignore --no-build-logs

echo
echo "Running smoketests"

if [[ -n "${BUILD_SH_IN_MANYLINUX:-}" ]]; then
  VENV_DIR="$ROOT_DIR/.venv-manylinux"
else
  VENV_DIR="$ROOT_DIR/.venv"
fi

uv venv --allow-existing --quiet "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" --reinstall --no-deps --quiet "$DIST_DIR"/*.whl >/dev/null

for toml in */pyproject.toml; do
  module="$(basename "$(dirname "$toml")" | tr '-' '_')"
  "$VENV_DIR/bin/python" -c "import $module; $module.smoketest()" >/dev/null
done

echo
echo "Done in $((SECONDS - START_SECS))s"
