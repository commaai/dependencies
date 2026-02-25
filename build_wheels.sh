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
  GHCR_IMAGE="ghcr.io/commaai/dependencies/manylinux:${ARCH}"
  # try pre-built image first, fall back to building locally
  if docker pull "$GHCR_IMAGE" 2>/dev/null; then
    IMAGE="$GHCR_IMAGE"
  else
    docker build -t deps-manylinux --build-arg "ARCH=${ARCH}" manylinux/
    IMAGE="deps-manylinux"
  fi
  exec docker run --rm \
    -e MANYLINUX=1 \
    -v "$DIR:/work" \
    -w /work \
    "$IMAGE" \
    bash build_wheels.sh "$WHEEL_DIR" "${PKGS[@]}"
fi

# inside manylinux container (or macOS)
if [ -z "${MANYLINUX:-}" ]; then
  ./setup.sh
  pip install setuptools wheel
fi

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
  DEPS_SOURCE_DIR="$(pwd)/$pkgname" pip wheel "./$pkgname" --no-deps --no-build-isolation --wheel-dir "$WHEEL_DIR"/
done
