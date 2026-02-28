#!/usr/bin/env bash
set -e

export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

RAYLIB_PLATFORM="PLATFORM_DESKTOP"
if [ -f /TICI ]; then
  RAYLIB_PLATFORM="PLATFORM_COMMA"
fi

INSTALL_DIR="$DIR/raylib/install"
if [ -d "$INSTALL_DIR/raylib" ]; then
  echo "raylib already present, skipping build."
  exit 0
fi

# Linux: install X11 deps (same as openpilot)
if [[ "$OSTYPE" == "linux"* ]]; then
  SUDO=""
  [[ $(id -u) -ne 0 ]] && [[ -n $(which sudo 2>/dev/null) ]] && SUDO="sudo"
  $SUDO apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev 2>/dev/null || true
fi

# 1. Build raylib C library (from openpilot third_party/raylib/build.sh)
RAYLIB_INSTALL="$DIR/build/raylib"
INSTALL_H_DIR="$DIR/build/include"
rm -rf "$RAYLIB_INSTALL" "$INSTALL_H_DIR"
mkdir -p "$RAYLIB_INSTALL" "$INSTALL_H_DIR"

if [ ! -d raylib_repo ]; then
  git clone -b master --no-tags https://github.com/commaai/raylib.git raylib_repo
fi

cd raylib_repo
RAYLIB_COMMIT="${1:-3425bd9d1fb292ede4d80f97a1f4f258f614cffc}"
git fetch origin "$RAYLIB_COMMIT"
git reset --hard "$RAYLIB_COMMIT"
git clean -xdff .
cd src

make -j$(nproc) PLATFORM=$RAYLIB_PLATFORM RAYLIB_RELEASE_PATH="$RAYLIB_INSTALL"
cp raylib.h raymath.h rlgl.h "$INSTALL_H_DIR/"

RAYGUI_COMMIT="76b36b597edb70ffaf96f046076adc20d67e7827"
curl -fsSLo "$INSTALL_H_DIR/raygui.h" "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

cd "$DIR"

# 2. Build wheel using electronstudio/raylib-python-cffi (commit 1f08f56)
BINDINGS_COMMIT="1f08f56708e76921367368b6be1fbae5240a3848"
if [ ! -d raylib_python_repo ]; then
  git clone -b master --no-tags https://github.com/electronstudio/raylib-python-cffi.git raylib_python_repo
fi

cd raylib_python_repo
git fetch origin "$BINDINGS_COMMIT"
git reset --hard "$BINDINGS_COMMIT"
git clean -xdff .

PYTHON="${PYTHON_EXECUTABLE:-python3}"

# Patch for stable ABI (Python 3.8+)
"$PYTHON" -c "
import pathlib
f = pathlib.Path('raylib/build.py')
text = f.read_text()
text = text.replace('py_limited_api=False', 'py_limited_api=True')
text = text.replace(', \"-D_CFFI_NO_LIMITED_API\"', '')
text = text.replace(', "-D_CFFI_NO_LIMITED_API"', '')
f.write_text(text)
"

# GLFW is bundled in commaai/raylib src
GLFW_INCLUDE="$DIR/raylib_repo/src/external/glfw/include"
[ ! -d "$GLFW_INCLUDE" ] && GLFW_INCLUDE="$INSTALL_H_DIR"

export RAYLIB_PLATFORM
export RAYLIB_INCLUDE_PATH="$INSTALL_H_DIR"
export RAYLIB_LINK_ARGS="$RAYLIB_INSTALL/libraylib.a"
export RAYGUI_INCLUDE_PATH="$INSTALL_H_DIR"
export GLFW_INCLUDE_PATH="$GLFW_INCLUDE"
export PHYSAC_INCLUDE_PATH="$INSTALL_H_DIR"

"$PYTHON" setup.py bdist_wheel
cd "$DIR"

# Extract wheel into install/ (package expects raylib/, pyray/, _raylib_cffi*.so)
rm -rf "$INSTALL_DIR" wheel_extract
mkdir -p "$INSTALL_DIR" wheel_extract
unzip -q -o raylib_python_repo/dist/raylib-*.whl -d wheel_extract
cp -r wheel_extract/raylib wheel_extract/pyray "$INSTALL_DIR/"
find wheel_extract -name "_raylib_cffi*.so" -exec cp {} "$INSTALL_DIR/" \;

# Cleanup
rm -rf raylib_repo raylib_python_repo "$DIR/build" wheel_extract

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
