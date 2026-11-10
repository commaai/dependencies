#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
CC="ccache ${CC:-cc}" CXX="ccache ${CXX:-c++}"

is_linux_aarch64() {
  [[ "$(uname)" == "Linux" && ( "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ) ]]
}

if [ -n "${RAYLIB_PLATFORM:-}" ]; then
  echo "RAYLIB_PLATFORM is no longer supported; use RAYLIB_BACKEND=desktop or RAYLIB_BACKEND=comma" >&2
  exit 1
fi

# An explicit RAYLIB_BACKEND builds only that backend; otherwise all of the
# host's backends are built (matches host_backends() in raylib/_backend.py)
RAYLIB_BACKEND="${RAYLIB_BACKEND:-}"
case "$RAYLIB_BACKEND" in
  ""|desktop|comma|headless) ;;
  *)
    echo "Unsupported RAYLIB_BACKEND=$RAYLIB_BACKEND; expected desktop, comma or headless" >&2
    exit 1
    ;;
esac

# Clone and build raylib C library
RAYLIB_COMMIT="767e8880f6eefccd9739860c29b61a5b2a262184"

if [ ! -d "raylib-src/.git" ]; then
  rm -rf raylib-src
  git clone --depth 1 -b master --no-tags https://github.com/commaai/raylib.git raylib-src
fi

cd raylib-src
git remote set-url origin https://github.com/commaai/raylib.git
if ! git cat-file -e "$RAYLIB_COMMIT" 2>/dev/null; then
  git fetch --depth 1 origin "$RAYLIB_COMMIT"
fi
git reset --hard "$RAYLIB_COMMIT"

cd "$DIR"

# Install lib + headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

cp raylib-src/src/raylib.h raylib-src/src/raymath.h raylib-src/src/rlgl.h "$INSTALL_DIR/include/"

build_raylib() {
  local platform="$1"
  local output="$2"

  cd "$DIR/raylib-src/src"
  make clean
  make -j"$NJOBS" PLATFORM="$platform" GRAPHICS=GRAPHICS_API_OPENGL_SOFTWARE CC="${CC:-gcc}"
  cp libraylib.a "$INSTALL_DIR/lib/$output"
  cd "$DIR"
}

backend_platform() {
  case "$1" in
    desktop) echo PLATFORM_DESKTOP_RGFW ;;
    comma) echo PLATFORM_COMMA ;;
    headless) echo PLATFORM_HEADLESS ;;
  esac
}

if [ -n "$RAYLIB_BACKEND" ]; then
  BACKENDS="$RAYLIB_BACKEND"
elif [ "$(uname)" == "Linux" ]; then
  BACKENDS="desktop headless"
  if is_linux_aarch64; then
    BACKENDS="$BACKENDS comma"
  fi
else
  BACKENDS="desktop"
fi

for backend in $BACKENDS; do
  echo "Building $backend backend..."
  build_raylib "$(backend_platform "$backend")" "libraylib_${backend}.a"
done

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
