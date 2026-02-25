#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

FFMPEG_VERSION="7.1"
INSTALL_DIR="$DIR/ffmpeg/install"

# Idempotent: skip if already built
if [ -x "$INSTALL_DIR/bin/ffmpeg" ]; then
  echo "ffmpeg already present, skipping build."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

# --- Build x264 (static) ---
if [ ! -d "x264-src" ]; then
  git clone --depth 1 --branch stable https://code.videolan.org/videolan/x264.git x264-src
fi

cd x264-src
./configure \
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
if [ ! -d "ffmpeg-src" ]; then
  git clone --depth 1 --branch "n${FFMPEG_VERSION}" https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
fi

cd ffmpeg-src
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
./configure \
  --prefix="$PREFIX" \
  --enable-gpl \
  --enable-static \
  --disable-shared \
  --enable-libx264 \
  --enable-pic \
  --disable-doc \
  --disable-ffplay \
  --disable-autodetect \
  --disable-everything \
  --enable-encoder=libx264,aac,ffvhuff,rawvideo,png \
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
for lib in libavformat.a libavcodec.a libavutil.a libswresample.a libx264.a; do
  cp "$PREFIX/lib/$lib" "$INSTALL_DIR/lib/"
done

# Headers
for dir in libavformat libavcodec libavutil libswresample; do
  cp -r "$PREFIX/include/$dir" "$INSTALL_DIR/include/"
done

# Strip binaries
strip "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe" 2>/dev/null || true

# Clean up
rm -rf x264-src ffmpeg-src "$DIR/build"

echo "Installed ffmpeg to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
