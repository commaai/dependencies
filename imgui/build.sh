#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/imgui/install"

# Idempotent: skip if already present
if [ -f "$INSTALL_DIR/include/imgui.h" ]; then
  echo "imgui already present, skipping download."
  exit 0
fi

# Dear ImGui (docking branch)
IMGUI_VERSION="1.92.7"
IMGUI_COMMIT="934c6a5f5ef2355d6df25395d555cb71f790c4e9"
IMGUI_URL="https://github.com/ocornut/imgui/archive/${IMGUI_COMMIT}.tar.gz"

# ImPlot (master)
IMPLOT_COMMIT="93c801b4bb801c5c11031d880b6af1d1f70bd79d"
IMPLOT_URL="https://github.com/epezent/implot/archive/${IMPLOT_COMMIT}.tar.gz"

# rlImGui (main)
RLIMGUI_COMMIT="286e11acd6c785004c9550c7ed3762add2ae3d47"
RLIMGUI_URL="https://github.com/raylib-extras/rlImGui/archive/${RLIMGUI_COMMIT}.tar.gz"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/include/extras" "$INSTALL_DIR/src"

echo "Downloading Dear ImGui ${IMGUI_VERSION} (docking) ..."
curl -fSL "$IMGUI_URL" | tar xz --strip-components=1 -C /tmp/imgui-src --one-top-level=/tmp/imgui-src
cp /tmp/imgui-src/imgui.h /tmp/imgui-src/imgui_internal.h /tmp/imgui-src/imconfig.h \
   /tmp/imgui-src/imstb_rectpack.h /tmp/imgui-src/imstb_textedit.h /tmp/imgui-src/imstb_truetype.h \
   "$INSTALL_DIR/include/"
cp /tmp/imgui-src/imgui.cpp /tmp/imgui-src/imgui_draw.cpp /tmp/imgui-src/imgui_tables.cpp \
   /tmp/imgui-src/imgui_widgets.cpp /tmp/imgui-src/imgui_demo.cpp \
   "$INSTALL_DIR/src/"
rm -rf /tmp/imgui-src

echo "Downloading ImPlot ..."
curl -fSL "$IMPLOT_URL" | tar xz --strip-components=1 -C /tmp/implot-src --one-top-level=/tmp/implot-src
cp /tmp/implot-src/implot.h /tmp/implot-src/implot_internal.h "$INSTALL_DIR/include/"
cp /tmp/implot-src/implot.cpp /tmp/implot-src/implot_items.cpp "$INSTALL_DIR/src/"
rm -rf /tmp/implot-src

echo "Downloading rlImGui ..."
curl -fSL "$RLIMGUI_URL" | tar xz --strip-components=1 -C /tmp/rlimgui-src --one-top-level=/tmp/rlimgui-src
cp /tmp/rlimgui-src/rlImGui.h /tmp/rlimgui-src/rlImGuiColors.h /tmp/rlimgui-src/imgui_impl_raylib.h \
   "$INSTALL_DIR/include/"
cp /tmp/rlimgui-src/extras/FA6FreeSolidFontData.h /tmp/rlimgui-src/extras/IconsFontAwesome6.h \
   "$INSTALL_DIR/include/extras/"
cp /tmp/rlimgui-src/rlImGui.cpp "$INSTALL_DIR/src/"
rm -rf /tmp/rlimgui-src

echo "Installed imgui to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
