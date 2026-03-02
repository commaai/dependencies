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

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading Dear ImGui ${IMGUI_VERSION} (docking) ..."
curl -fSL -o "$TMPDIR/imgui.tar.gz" "$IMGUI_URL"
mkdir -p "$TMPDIR/imgui"
tar --strip-components=1 -xzf "$TMPDIR/imgui.tar.gz" -C "$TMPDIR/imgui"
cp "$TMPDIR/imgui/imgui.h" "$TMPDIR/imgui/imgui_internal.h" "$TMPDIR/imgui/imconfig.h" \
   "$TMPDIR/imgui/imstb_rectpack.h" "$TMPDIR/imgui/imstb_textedit.h" "$TMPDIR/imgui/imstb_truetype.h" \
   "$INSTALL_DIR/include/"
cp "$TMPDIR/imgui/imgui.cpp" "$TMPDIR/imgui/imgui_draw.cpp" "$TMPDIR/imgui/imgui_tables.cpp" \
   "$TMPDIR/imgui/imgui_widgets.cpp" "$TMPDIR/imgui/imgui_demo.cpp" \
   "$INSTALL_DIR/src/"
cp "$TMPDIR/imgui/backends/imgui_impl_opengl3.h" "$TMPDIR/imgui/backends/imgui_impl_opengl3_loader.h" \
   "$INSTALL_DIR/include/"
cp "$TMPDIR/imgui/backends/imgui_impl_opengl3.cpp" "$INSTALL_DIR/src/"

echo "Downloading ImPlot ..."
curl -fSL -o "$TMPDIR/implot.tar.gz" "$IMPLOT_URL"
mkdir -p "$TMPDIR/implot"
tar --strip-components=1 -xzf "$TMPDIR/implot.tar.gz" -C "$TMPDIR/implot"
cp "$TMPDIR/implot/implot.h" "$TMPDIR/implot/implot_internal.h" "$INSTALL_DIR/include/"
cp "$TMPDIR/implot/implot.cpp" "$TMPDIR/implot/implot_items.cpp" "$INSTALL_DIR/src/"

echo "Downloading rlImGui ..."
curl -fSL -o "$TMPDIR/rlimgui.tar.gz" "$RLIMGUI_URL"
mkdir -p "$TMPDIR/rlimgui"
tar --strip-components=1 -xzf "$TMPDIR/rlimgui.tar.gz" -C "$TMPDIR/rlimgui"
cp "$TMPDIR/rlimgui/rlImGui.h" "$TMPDIR/rlimgui/rlImGuiColors.h" "$TMPDIR/rlimgui/imgui_impl_raylib.h" \
   "$INSTALL_DIR/include/"
cp "$TMPDIR/rlimgui/extras/FA6FreeSolidFontData.h" "$TMPDIR/rlimgui/extras/IconsFontAwesome6.h" \
   "$INSTALL_DIR/include/extras/"
cp "$TMPDIR/rlimgui/rlImGui.cpp" "$INSTALL_DIR/src/"

echo "Installed imgui to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
