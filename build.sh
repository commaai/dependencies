#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

if [[ $# -gt 0 ]]; then
  echo "usage: MANYLINUX=1 ./build.sh" >&2
  exit 2
fi

USE_MANYLINUX="${MANYLINUX:-0}"

package_artifact_dirs() {
  local pkg="$1"
  local module="${pkg//-/_}"
  printf '%s\n' \
    "$pkg/$module/install" \
    "$pkg/$module/toolchain" \
    "$pkg/$module/bin"
}

package_build_stamp() {
  local pkg="$1"
  python3 - "$pkg" <<'PY'
import hashlib
import platform
import sys
from pathlib import Path

pkg = Path(sys.argv[1])
files = [pkg / "build.sh", pkg / "setup.py", pkg / "pyproject.toml"]

h = hashlib.sha256()
h.update(platform.system().encode())
h.update(b"\0")
h.update(platform.machine().encode())

for path in files:
  h.update(b"\0")
  h.update(path.name.encode())
  h.update(b"\0")
  h.update(path.read_bytes())

print(h.hexdigest())
PY
}

invalidate_stale_artifacts() {
  local toml pkg stamp cached_stamp found dir
  for toml in */pyproject.toml; do
    pkg="${toml%/pyproject.toml}"
    stamp="$(package_build_stamp "$pkg")"
    cached_stamp=""
    found=0

    while IFS= read -r dir; do
      if [[ -d "$dir" ]]; then
        found=1
        if [[ -z "$cached_stamp" && -f "$dir/.build-stamp" ]]; then
          cached_stamp="$(cat "$dir/.build-stamp")"
        fi
      fi
    done < <(package_artifact_dirs "$pkg")

    if [[ "$found" -eq 0 ]]; then
      continue
    fi

    if [[ "$cached_stamp" != "$stamp" ]]; then
      echo "[$pkg] cache mismatch, removing stale artifacts"
      while IFS= read -r dir; do
        rm -rf "$dir"
      done < <(package_artifact_dirs "$pkg")
    fi
  done
}

write_artifact_stamps() {
  local toml pkg stamp dir
  for toml in */pyproject.toml; do
    pkg="${toml%/pyproject.toml}"
    stamp="$(package_build_stamp "$pkg")"
    while IFS= read -r dir; do
      if [[ -d "$dir" ]]; then
        printf '%s\n' "$stamp" > "$dir/.build-stamp"
      fi
    done < <(package_artifact_dirs "$pkg")
  done
}

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

  ./setup.sh

  if [[ -z "${BUILD_SH_REUSE_MANYLINUX_ARTIFACTS:-}" ]]; then
    for toml in */pyproject.toml; do
      pkg="${toml%/pyproject.toml}"
      while IFS= read -r dir; do
        rm -rf "$dir"
      done < <(package_artifact_dirs "$pkg")
    done
  fi
fi

invalidate_stale_artifacts

echo "Building workspace packages into dist"
START_SECS=$SECONDS

mkdir -p dist
rm -f dist/*.whl

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

write_artifact_stamps

du -hs dist/* | sort -hr

echo
echo "Done in $((SECONDS - START_SECS))s"
