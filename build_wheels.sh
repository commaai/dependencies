#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

WHEEL_DIR="${1:-dist}"
shift 2>/dev/null || true
PKGS=("$@")

# on Linux, build inside manylinux_2_28 container for glibc 2.28 compatibility.
# for reference, Ubuntu 20.04 is glibc 2.31, so this gives us wide compatibility.
if [ "$(uname)" = "Linux" ] && [ -z "${MANYLINUX:-}" ]; then
  ARCH="$(uname -m)"
  IMAGE="quay.io/pypa/manylinux_2_28_${ARCH}"
  exec docker run --rm \
    -e MANYLINUX=1 \
    -v "$DIR:/work" \
    -w /work \
    "$IMAGE" \
    bash build_wheels.sh "$WHEEL_DIR" "${PKGS[@]}"
fi

# Set up Python inside manylinux container
if [ -n "${MANYLINUX:-}" ]; then
  export PATH="/opt/python/cp312-cp312/bin:$PATH"
fi

./setup.sh
pip install setuptools wheel

mkdir -p "$WHEEL_DIR"
for pkg in */pyproject.toml; do
  pkgname="$(dirname "$pkg")"
  if [ ${#PKGS[@]} -gt 0 ]; then
    match=0
    for p in "${PKGS[@]}"; do
      [ "$p" = "$pkgname" ] && match=1 && break
    done
    [ "$match" -eq 0 ] && continue
  fi
  pip wheel "./$pkgname" --no-deps --wheel-dir "$WHEEL_DIR"/
done
