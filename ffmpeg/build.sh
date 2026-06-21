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
CC="${CC:-cc}"
if command -v ccache &>/dev/null; then
  CC="ccache $CC"
fi
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
X264_FLAGS=(--prefix="$PREFIX" --enable-static --disable-shared --disable-cli --disable-opencl --enable-pic)
if ! command -v nasm &>/dev/null; then
  X264_FLAGS+=(--disable-asm)
fi
CFLAGS="-fno-finite-math-only" ./configure "${X264_FLAGS[@]}"
make -j"$NJOBS"
make install
cd "$DIR"

# Ensure pkg-config is available (macOS doesn't have it by default)
if ! command -v pkg-config &>/dev/null; then
  if [ "$PLATFORM" = "Darwin" ]; then
    for p in /opt/homebrew/bin /usr/local/bin; do
      [ -x "$p/pkg-config" ] && export PATH="$p:$PATH"
    done
  fi
  if ! command -v pkg-config &>/dev/null && command -v brew &>/dev/null; then
    brew install pkg-config
    for p in /opt/homebrew/bin /usr/local/bin; do
      [ -x "$p/pkg-config" ] && export PATH="$p:$PATH"
    done
  fi
fi

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
HAVE_VAAPI=no
if [ "$PLATFORM" = "Linux" ]; then
  if ! command -v meson &>/dev/null; then
    pip3 install --quiet --break-system-packages meson ninja 2>/dev/null || python3 -m pip install --quiet meson ninja 2>/dev/null || true
  fi

  if command -v meson &>/dev/null; then
    HAVE_VAAPI=yes
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

    # V4L2 Memory-to-Memory (embedded: RPi, Qualcomm, Rockchip)
    --enable-v4l2-m2m
    --enable-decoder=h264_v4l2m2m,hevc_v4l2m2m
    --enable-encoder=h264_v4l2m2m,hevc_v4l2m2m

    # Vulkan video decode/encode (uses dlopen at runtime)
    --enable-vulkan
    --enable-hwaccel=h264_vulkan,hevc_vulkan
    --enable-encoder=h264_vulkan,hevc_vulkan
  )
  if [ "$HAVE_VAAPI" = "yes" ]; then
    HW_FLAGS+=(
      # VAAPI (Intel/AMD — libva linked statically, driver loaded via dlopen at runtime)
      --enable-vaapi
      --enable-hwaccel=h264_vaapi,hevc_vaapi
    )
  fi
elif [ "$PLATFORM" = "Darwin" ]; then
  HW_FLAGS+=(
    # VideoToolbox (Apple Silicon / macOS)
    --enable-videotoolbox
    --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
    --enable-encoder=h264_videotoolbox,hevc_videotoolbox
  )
fi

RPATH='$ORIGIN/../lib'

FFMPEG_FLAGS=(
  --cc="${CC:-cc}" \
  --prefix="$PREFIX" \
  --enable-gpl \
  --enable-shared \
  --disable-static \
  --enable-zlib \
  --enable-libx264 \
  --enable-pic \
  --disable-doc \
  --disable-ffplay \
  --disable-autodetect \
  --disable-everything \
  --disable-debug \
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
)
if ! command -v nasm &>/dev/null; then
  FFMPEG_FLAGS+=(--disable-x86asm)
fi

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
./configure "${FFMPEG_FLAGS[@]}"
make -j"$NJOBS"
make install
cd "$DIR"

# Copy to package install dir
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,include}

# Binaries
cp "$PREFIX/bin/ffmpeg" "$INSTALL_DIR/bin/"
cp "$PREFIX/bin/ffprobe" "$INSTALL_DIR/bin/"

# Shared libraries (only the real versioned files, symlinks created at install time)
if [ "$PLATFORM" = "Darwin" ]; then
  for lib in "$PREFIX"/lib/libav*.*.*.dylib "$PREFIX"/lib/libsw*.*.*.dylib "$PREFIX"/lib/libpost*.*.*.dylib; do
    [ -f "$lib" ] && cp "$lib" "$INSTALL_DIR/lib/"
  done
else
  for lib in "$PREFIX"/lib/libav*.so.*.* "$PREFIX"/lib/libsw*.so.*.* "$PREFIX"/lib/libpost*.so.*.*; do
    [ -f "$lib" ] && cp "$lib" "$INSTALL_DIR/lib/"
  done
fi

# Headers
for dir in libavformat libavcodec libavutil libswresample; do
  cp -r "$PREFIX/include/$dir" "$INSTALL_DIR/include/"
done

# Strip binaries and shared libraries
strip "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe" 2>/dev/null || true
for lib in "$INSTALL_DIR"/lib/*.so.* "$INSTALL_DIR"/lib/*.dylib.*; do
  [ -f "$lib" ] && strip -x "$lib" 2>/dev/null || true
done

# Set RPATH/RPATH so binaries find shared libs relative to their own location
if [ "$PLATFORM" = "Darwin" ]; then
  install_name_tool -add_rpath @loader_path/../lib "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe" 2>/dev/null || true
elif command -v patchelf &>/dev/null; then
  patchelf --set-rpath '$ORIGIN/../lib' "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe"
fi

echo "Installed ffmpeg to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
