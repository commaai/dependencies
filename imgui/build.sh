#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/imgui/install"

# Dear ImGui (docking branch, version 1.92.7)
IMGUI_COMMIT="934c6a5f5ef2355d6df25395d555cb71f790c4e9"
# ImPlot
IMPLOT_COMMIT="93c801b4bb801c5c11031d880b6af1d1f70bd79d"
# rlImGui
RLIMGUI_COMMIT="286e11acd6c785004c9550c7ed3762add2ae3d47"

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

# Clone/update rlimgui
if [ ! -d "rlimgui-src/.git" ]; then
  rm -rf rlimgui-src
  git clone --depth 1 https://github.com/raylib-extras/rlImGui.git rlimgui-src
fi
git -C rlimgui-src fetch --depth 1 origin "$RLIMGUI_COMMIT"
git -C rlimgui-src checkout --force "$RLIMGUI_COMMIT"

# Install
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include/extras" "$INSTALL_DIR/src"

# imgui
cp imgui-src/imgui.h imgui-src/imgui_internal.h imgui-src/imconfig.h \
   imgui-src/imstb_rectpack.h imgui-src/imstb_textedit.h imgui-src/imstb_truetype.h \
   "$INSTALL_DIR/include/"
cp imgui-src/imgui.cpp imgui-src/imgui_draw.cpp imgui-src/imgui_tables.cpp \
   imgui-src/imgui_widgets.cpp imgui-src/imgui_demo.cpp \
   "$INSTALL_DIR/src/"
cp imgui-src/backends/imgui_impl_opengl3.h imgui-src/backends/imgui_impl_opengl3_loader.h \
   imgui-src/backends/imgui_impl_glfw.h \
   "$INSTALL_DIR/include/"
cp imgui-src/backends/imgui_impl_opengl3.cpp imgui-src/backends/imgui_impl_glfw.cpp \
   "$INSTALL_DIR/src/"

# implot
cp implot-src/implot.h implot-src/implot_internal.h "$INSTALL_DIR/include/"
cp implot-src/implot.cpp implot-src/implot_items.cpp "$INSTALL_DIR/src/"

# rlimgui
cp rlimgui-src/rlImGui.h rlimgui-src/rlImGuiColors.h rlimgui-src/imgui_impl_raylib.h \
   "$INSTALL_DIR/include/"
cp rlimgui-src/extras/FA6FreeSolidFontData.h rlimgui-src/extras/IconsFontAwesome6.h \
   "$INSTALL_DIR/include/extras/"
cp rlimgui-src/rlImGui.cpp "$INSTALL_DIR/src/"

echo "Installed imgui to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
