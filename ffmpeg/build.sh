#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

PLATFORM="$(uname -s)"
FFMPEG_VERSION="7.1"
ZLIB_VERSION="da607da739fa6047df13e66a2af6b8bec7c2a498"  # v1.3.2
X264_BRANCH="stable"
LIBDRM_VERSION="libdrm-2.4.124"
LIBVA_VERSION="2.22.0"
INSTALL_DIR="$DIR/ffmpeg/install"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
CC="ccache ${CC:-cc}"
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

# --- Build zlib (static) ---
if [ ! -d "zlib-src/.git" ]; then
  rm -rf zlib-src
  git clone --depth 1 https://github.com/madler/zlib.git zlib-src
fi
git -C zlib-src fetch --depth 1 origin "$ZLIB_VERSION"
git -C zlib-src checkout --force "$ZLIB_VERSION"

cd zlib-src
./configure --prefix="$PREFIX" --static
make -j"$NJOBS"
make install
cd "$DIR"

# --- Build x264 (static) ---
if [ ! -d "x264-src/.git" ]; then
  rm -rf x264-src
  git clone --depth 1 https://code.videolan.org/videolan/x264.git x264-src
fi
git -C x264-src fetch --depth 1 origin "$X264_BRANCH"
git -C x264-src checkout --force FETCH_HEAD

cd x264-src
CFLAGS="-fno-finite-math-only" ./configure \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-cli \
  --disable-opencl \
  --enable-pic
make -j"$NJOBS"
make install
cd "$DIR"

# --- Build nv-codec-headers (Linux only, for CUDA/NVDEC) ---
if [ "$PLATFORM" = "Linux" ]; then
  if [ ! -d "nv-codec-headers-src/.git" ]; then
    rm -rf nv-codec-headers-src
    git clone --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git nv-codec-headers-src
  fi
  make -C nv-codec-headers-src PREFIX="$PREFIX" install
fi

# --- Build Vulkan-Headers from source (Linux only, need >= 1.3.277 for FFmpeg 7.1) ---
if [ "$PLATFORM" = "Linux" ]; then
  if [ ! -d "vulkan-headers-src/.git" ]; then
    rm -rf vulkan-headers-src
    git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git vulkan-headers-src
  fi
  cmake -S vulkan-headers-src -B vulkan-headers-src/build -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
  cmake --install vulkan-headers-src/build >/dev/null
fi

# --- Build libdrm + libva statically (Linux only, for VAAPI without runtime deps) ---
if [ "$PLATFORM" = "Linux" ]; then
  if ! command -v meson &>/dev/null; then
    pip3 install --quiet meson ninja 2>/dev/null || python3 -m pip install --quiet meson ninja 2>/dev/null || true
    command -v meson &>/dev/null || { echo "error: meson is required (apt install meson or pip install meson)" >&2; exit 1; }
  fi

  if [ ! -d "libdrm-src/.git" ]; then
    rm -rf libdrm-src
    git clone --depth 1 --branch "$LIBDRM_VERSION" https://gitlab.freedesktop.org/mesa/drm.git libdrm-src
  fi
  rm -rf libdrm-src/builddir
  meson setup libdrm-src/builddir libdrm-src \
    --prefix="$PREFIX" --libdir=lib --default-library=static \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Dtests=false -Dman-pages=disabled -Dcairo-tests=disabled \
    -Dvalgrind=disabled
  ninja -C libdrm-src/builddir install

  if [ ! -d "libva-src/.git" ]; then
    rm -rf libva-src
    git clone --depth 1 --branch "$LIBVA_VERSION" https://github.com/intel/libva.git libva-src
  fi
  rm -rf libva-src/builddir
  # libva hardcodes shared_library(); patch to library() so --default-library=static works
  sed -i 's/shared_library(/library(/g' libva-src/va/meson.build
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
  meson setup libva-src/builddir libva-src \
    --prefix="$PREFIX" --libdir=lib --default-library=static \
    -Ddisable_drm=false -Dwith_x11=no -Dwith_glx=no -Dwith_wayland=no \
    -Dwith_win32=no -Denable_docs=false
  ninja -C libva-src/builddir install
fi

# --- Build FFmpeg ---
if [ ! -d "ffmpeg-src/.git" ]; then
  rm -rf ffmpeg-src
  git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
fi
git -C ffmpeg-src fetch --depth 1 origin "n${FFMPEG_VERSION}"
git -C ffmpeg-src checkout --force FETCH_HEAD

cd ffmpeg-src

# Platform-specific hardware acceleration flags
HW_FLAGS=()
if [ "$PLATFORM" = "Linux" ]; then
  HW_FLAGS+=(
    # NVIDIA CUDA/NVDEC (uses dlopen at runtime)
    --enable-ffnvcodec --enable-cuda --enable-cuvid --enable-nvdec
    --enable-hwaccel=h264_nvdec,hevc_nvdec
    --enable-decoder=h264_cuvid,hevc_cuvid

    # VAAPI (Intel/AMD — libva linked statically, driver loaded via dlopen at runtime)
    --enable-vaapi
    --enable-hwaccel=h264_vaapi,hevc_vaapi

    # V4L2 Memory-to-Memory (embedded: RPi, Qualcomm, Rockchip)
    --enable-v4l2-m2m
    --enable-decoder=h264_v4l2m2m,hevc_v4l2m2m
    --enable-encoder=h264_v4l2m2m,hevc_v4l2m2m

    # Vulkan video decode/encode (uses dlopen at runtime)
    --enable-vulkan
    --enable-hwaccel=h264_vulkan,hevc_vulkan
    --enable-encoder=h264_vulkan,hevc_vulkan
  )
elif [ "$PLATFORM" = "Darwin" ]; then
  HW_FLAGS+=(
    # VideoToolbox (Apple Silicon / macOS)
    --enable-videotoolbox
    --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
    --enable-encoder=h264_videotoolbox,hevc_videotoolbox
  )
fi

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
./configure \
  --cc="${CC:-cc}" \
  --prefix="$PREFIX" \
  --enable-gpl \
  --enable-static \
  --disable-shared \
  --enable-zlib \
  --enable-libx264 \
  --enable-pic \
  --disable-doc \
  --disable-ffplay \
  --disable-autodetect \
  --disable-everything \
  --enable-encoder=libx264,aac,ffvhuff,rawvideo,png,mjpeg \
  --enable-decoder=h264,hevc,ffvhuff,aac,rawvideo,png,mjpeg,mp3,pcm_s16le \
  --enable-muxer=mpegts,matroska,mp4,hevc,rawvideo,image2,null,mov,framehash \
  --enable-demuxer=hevc,matroska,mpegts,mov,rawvideo,image2,aac,concat \
  --enable-parser=h264,hevc,aac,mpegaudio \
  --enable-protocol=file,pipe \
  --enable-filter=blend,vflip,format,scale,aformat,anull,aresample,null \
  --enable-bsf=extract_extradata,h264_mp4toannexb,hevc_mp4toannexb \
  --extra-cflags="-I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib" \
  "${HW_FLAGS[@]}"
make -j"$NJOBS"
make install
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,include}

# Binaries
cp "$PREFIX/bin/ffmpeg" "$INSTALL_DIR/bin/"
cp "$PREFIX/bin/ffprobe" "$INSTALL_DIR/bin/"

# Libraries
LIBS="libavformat.a libavcodec.a libavutil.a libswresample.a libx264.a libz.a"
if [ "$PLATFORM" = "Linux" ]; then
  LIBS="$LIBS libva.a libva-drm.a libdrm.a"
fi
for lib in $LIBS; do
  cp "$PREFIX/lib/$lib" "$INSTALL_DIR/lib/"
done

# Headers
for dir in libavformat libavcodec libavutil libswresample; do
  cp -r "$PREFIX/include/$dir" "$INSTALL_DIR/include/"
done

# Strip binaries
strip "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe" 2>/dev/null || true

echo "Installed ffmpeg to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
