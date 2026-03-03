#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

FFMPEG_VERSION="7.1"
ZLIB_VERSION="da607da739fa6047df13e66a2af6b8bec7c2a498"  # v1.3.2
X264_BRANCH="stable"
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

# --- Build FFmpeg ---
if [ ! -d "ffmpeg-src/.git" ]; then
  rm -rf ffmpeg-src
  git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
fi
git -C ffmpeg-src fetch --depth 1 origin "n${FFMPEG_VERSION}"
git -C ffmpeg-src checkout --force FETCH_HEAD

cd ffmpeg-src
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
  --extra-ldflags="-L$PREFIX/lib"
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
for lib in libavformat.a libavcodec.a libavutil.a libswresample.a libx264.a libz.a; do
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
