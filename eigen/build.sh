#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="3.4.0"
INSTALL_DIR="$DIR/eigen/install"

# Idempotent: skip if already present
if [ -d "$INSTALL_DIR/eigen3/Eigen" ]; then
  echo "eigen already present, skipping download."
  exit 0
fi

TARBALL="eigen-${VERSION}.tar.gz"
URL="https://gitlab.com/libeigen/eigen/-/archive/${VERSION}/${TARBALL}"

echo "Downloading Eigen ${VERSION} ..."
curl -fSL -o "$TARBALL" "$URL"

echo "Extracting headers ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/eigen3"

# Extract only the Eigen/ and unsupported/Eigen/ header directories
tar --strip-components=1 -xzf "$TARBALL" -C "$INSTALL_DIR/eigen3" \
  "eigen-${VERSION}/Eigen" \
  "eigen-${VERSION}/unsupported"

rm -f "$TARBALL"

echo "Installed eigen to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
