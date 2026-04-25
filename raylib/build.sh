#!/usr/bin/env bash
set -euo pipefail

export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/raylib/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
if command -v ccache >/dev/null 2>&1; then
  CC="${CC:-ccache cc}"
else
  CC="${CC:-cc}"
fi

is_linux() {
  [[ "$(uname)" == "Linux" ]]
}

install_linux_deps() {
  local platform="$1"
  if ! is_linux; then
    return
  fi

  if [ "$platform" = "PLATFORM_COMMA" ]; then
    # comma device: needs DRM/EGL/GLES headers (usually already present on AGNOS)
    # apt may fail on devices due to read-only rootfs or package conflicts; that's OK.
    if command -v apt-get >/dev/null 2>&1; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      else
        sudo apt-get update && sudo apt-get install -y libdrm-dev libgbm-dev libgles2-mesa-dev libegl1-mesa-dev || true
      fi
    fi
  elif [ "$platform" = "PLATFORM_OFFSCREEN" ]; then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y mesa-libEGL-devel mesa-libGL-devel libglvnd-opengl libglvnd-core-devel 2>/dev/null || true
    elif command -v apt-get >/dev/null 2>&1; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libegl-dev libgl-dev
      else
        sudo apt-get update && sudo apt-get install -y libegl-dev libgl-dev
      fi
    fi
  else
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y libX11-devel libXcursor-devel libXrandr-devel libXinerama-devel libXi-devel mesa-libGL-devel
    elif command -v apt-get >/dev/null 2>&1; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev
      else
        sudo apt-get update && sudo apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev
      fi
    fi
  fi
}

# RAYLIB_COMMIT matches the openpilot third_party/raylib pin this package replaces.
RAYLIB_COMMIT="${RAYLIB_COMMIT:-3425bd9d1fb292ede4d80f97a1f4f258f614cffc}"
RAYLIB_OFFSCREEN_COMMIT="${RAYLIB_OFFSCREEN_COMMIT:-d9d7cc1353ec0f73c97e84ddf0973983d1ee25e2}"
RAYGUI_COMMIT="${RAYGUI_COMMIT:-76b36b597edb70ffaf96f046076adc20d67e7827}"

if [ ! -d "raylib-src/.git" ]; then
  rm -rf raylib-src
  git clone --depth 1 -b master --no-tags https://github.com/commaai/raylib.git raylib-src
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,include}

if [ -n "${RAYLIB_VARIANTS:-}" ]; then
  read -r -a VARIANTS <<< "$RAYLIB_VARIANTS"
elif [[ -f /TICI || -f /AGNOS ]]; then
  VARIANTS=(comma)
elif is_linux && [[ "$(uname -m)" == "x86_64" ]]; then
  VARIANTS=(desktop offscreen)
elif is_linux && [[ "$(uname -m)" == "aarch64" ]]; then
  VARIANTS=(desktop comma)
else
  VARIANTS=(desktop)
fi

build_variant() {
  local variant="$1"
  local platform="PLATFORM_DESKTOP"
  local commit="$RAYLIB_COMMIT"

  if [ "$variant" = "comma" ]; then
    platform="PLATFORM_COMMA"
  elif [ "$variant" = "offscreen" ]; then
    platform="PLATFORM_OFFSCREEN"
    commit="$RAYLIB_OFFSCREEN_COMMIT"
  fi

  echo "Building raylib $variant ($platform)"
  install_linux_deps "$platform"

  cd "$DIR/raylib-src"
  git fetch --depth 1 origin "$commit"
  git reset --hard "$commit"
  git clean -xdff .

  cd src
  make clean
  make -j"$NJOBS" PLATFORM="$platform" CC="$CC"

  mkdir -p "$INSTALL_DIR/lib/$variant"
  cp libraylib.a "$INSTALL_DIR/lib/$variant/libraylib.a"
  if [ "$variant" = "${VARIANTS[0]}" ]; then
    cp raylib.h raymath.h rlgl.h "$INSTALL_DIR/include/"
    cp libraylib.a "$INSTALL_DIR/lib/libraylib.a"
  fi
}

for variant in "${VARIANTS[@]}"; do
  build_variant "$variant"
done

cd "$DIR"

if is_linux && [[ "$(uname -m)" == "x86_64" && " ${VARIANTS[*]} " == *" offscreen "* ]]; then
  MESA_DIR="$INSTALL_DIR/lib/mesa"
  mkdir -p "$MESA_DIR"
  ldconfig 2>/dev/null || true
  for lib in libEGL.so.1 libOpenGL.so.0 libGLdispatch.so.0; do
    src="$(ldconfig -p 2>/dev/null | grep "$lib" | grep -E 'x86.64|libc6,' | awk '{print $NF}' | head -1)"
    if [ -n "$src" ] && [ -f "$src" ]; then
      cp -L "$src" "$MESA_DIR/"
      base="${lib%%.so.*}"
      ln -sf "$lib" "$MESA_DIR/${base}.so"
    fi
  done
fi

curl -fsSLo "$INSTALL_DIR/include/raygui.h" \
  "https://raw.githubusercontent.com/raysan5/raygui/$RAYGUI_COMMIT/src/raygui.h"

cat > "$INSTALL_DIR/build-info.txt" <<EOF
raylib_commit=$RAYLIB_COMMIT
raylib_offscreen_commit=$RAYLIB_OFFSCREEN_COMMIT
raygui_commit=$RAYGUI_COMMIT
variants=${VARIANTS[*]}
EOF

echo "Installed raylib to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
