#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/imgui/install"
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Dear ImGui (docking branch, version 1.92.7)
IMGUI_COMMIT="934c6a5f5ef2355d6df25395d555cb71f790c4e9"
# ImPlot
IMPLOT_COMMIT="93c801b4bb801c5c11031d880b6af1d1f70bd79d"

# GLFW 3.4
GLFW_COMMIT="7b6aead9fb88b3623e3b3725ebb42670cbe4c579"

# Clone/update imgui
if [ ! -d "imgui-src/.git" ]; then
  rm -rf imgui-src
  git clone --depth 1 https://github.com/ocornut/imgui.git imgui-src
fi
git -C imgui-src fetch --depth 1 origin "$IMGUI_COMMIT"
git -C imgui-src checkout --force "$IMGUI_COMMIT"

# Clone/update implot
if [ ! -d "implot-src/.git" ]; then
  rm -rf implot-src
  git clone --depth 1 https://github.com/epezent/implot.git implot-src
fi
git -C implot-src fetch --depth 1 origin "$IMPLOT_COMMIT"
git -C implot-src checkout --force "$IMPLOT_COMMIT"

# Clone/update GLFW
if [ ! -d "glfw-src/.git" ]; then
  rm -rf glfw-src
  git clone --depth 1 https://github.com/glfw/glfw.git glfw-src
fi
git -C glfw-src fetch --depth 1 origin "$GLFW_COMMIT"
git -C glfw-src checkout --force "$GLFW_COMMIT"

# Install GLFW build dependencies (manylinux deps installed centrally in build.sh)
if [[ "$(uname)" == "Linux" ]]; then
  if command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev \
                                           libwayland-dev wayland-protocols libxkbcommon-dev
    else
      sudo apt-get update && sudo apt-get install -y libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libgl-dev \
                                                     libwayland-dev wayland-protocols libxkbcommon-dev
    fi
  fi
fi

# Build GLFW static library
cmake -B glfw-src/build -S glfw-src \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGLFW_BUILD_EXAMPLES=OFF \
  -DGLFW_BUILD_TESTS=OFF \
  -DGLFW_BUILD_DOCS=OFF
cmake --build glfw-src/build --parallel "$NJOBS"

# Install headers
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include" "$INSTALL_DIR/lib"

# imgui headers
cp imgui-src/imgui.h imgui-src/imgui_internal.h imgui-src/imconfig.h \
   imgui-src/imstb_rectpack.h imgui-src/imstb_textedit.h imgui-src/imstb_truetype.h \
   "$INSTALL_DIR/include/"
cp imgui-src/backends/imgui_impl_opengl3.h imgui-src/backends/imgui_impl_opengl3_loader.h \
   imgui-src/backends/imgui_impl_glfw.h \
   "$INSTALL_DIR/include/"

# implot headers
cp implot-src/implot.h implot-src/implot_internal.h "$INSTALL_DIR/include/"

# glfw
cp glfw-src/build/src/libglfw3.a "$INSTALL_DIR/lib/"
cp -r glfw-src/include/GLFW "$INSTALL_DIR/include/"

# Build libimgui.a (imgui core + backends + implot)
IMGUI_SRCS=(
  imgui-src/imgui.cpp
  imgui-src/imgui_draw.cpp
  imgui-src/imgui_tables.cpp
  imgui-src/imgui_widgets.cpp
  imgui-src/imgui_demo.cpp
  imgui-src/backends/imgui_impl_opengl3.cpp
  imgui-src/backends/imgui_impl_glfw.cpp
  implot-src/implot.cpp
  implot-src/implot_items.cpp
)
OBJ_DIR="$(mktemp -d)"
for src in "${IMGUI_SRCS[@]}"; do
  obj="$OBJ_DIR/$(basename "${src%.cpp}.o")"
  c++ -c -O2 -fPIC -I"$INSTALL_DIR/include" "$src" -o "$obj" &
done
wait
ar rcs "$INSTALL_DIR/lib/libimgui.a" "$OBJ_DIR"/*.o
rm -rf "$OBJ_DIR"

# Bundle GLVND dispatchers so Linux users don't need system libGL
if [[ "$(uname)" == "Linux" ]]; then
  MESA_DIR="$INSTALL_DIR/lib/mesa"
  mkdir -p "$MESA_DIR"
  ldconfig 2>/dev/null || true
  for lib in libGL.so.1 libGLX.so.0 libEGL.so.1 libOpenGL.so.0 libGLdispatch.so.0; do
    src="$(ldconfig -p 2>/dev/null | grep -F "$lib" | awk '{print $NF}' | head -1)"
    if [ -n "$src" ] && [ -f "$src" ]; then
      cp -L "$src" "$MESA_DIR/"
      # Create unversioned symlink for the linker
      base="${lib%%.so.*}"
      ln -sf "$lib" "$MESA_DIR/${base}.so"
    fi
  done
fi

echo "Installed imgui to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
