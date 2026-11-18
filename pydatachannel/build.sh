#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

LIBDATACHANNEL_COMMIT="6b1e2e620f1e37f0eafeee702eaea0043cb305fd"  # v0.24.6
OPENSSL_VERSION="3.5.8"
OPENSSL_PREFIX="$DIR/build/openssl"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PYTHON="${PYTHON:-python3}"
export MACOSX_DEPLOYMENT_TARGET=14.0  # for OpenSSL and the extension alike; matches the wheel tag in setup.py

# Clone/update libdatachannel source
if [ ! -d "libdatachannel-src/.git" ]; then
  rm -rf libdatachannel-src
  git clone --depth 1 --no-tags https://github.com/paullouisageneau/libdatachannel.git libdatachannel-src
fi

cd libdatachannel-src
if ! git cat-file -e "$LIBDATACHANNEL_COMMIT" 2>/dev/null; then
  git fetch --depth 1 origin "$LIBDATACHANNEL_COMMIT"
fi
git reset --hard "$LIBDATACHANNEL_COMMIT"
# only the dependencies the binding compiles (deps/json is for the examples)
git submodule update --init --depth 1 deps/plog deps/usrsctp deps/libjuice deps/libsrtp
cd "$DIR"

# OpenSSL, built from source and linked statically: the wheel needs no system libssl, whatever its version
if [ ! -f "$OPENSSL_PREFIX/.version" ] || [ "$(cat "$OPENSSL_PREFIX/.version")" != "$OPENSSL_VERSION" ]; then
  if [ ! -d "openssl-src/.git" ]; then
    rm -rf openssl-src
    git clone --depth 1 --no-tags https://github.com/openssl/openssl.git openssl-src
  fi
  git -C openssl-src fetch --depth 1 origin tag "openssl-${OPENSSL_VERSION}"
  git -C openssl-src checkout --force "openssl-${OPENSSL_VERSION}"
  git -C openssl-src clean -fdxq

  cd openssl-src
  OPENSSL_CC="${CC:-cc}"
  if command -v ccache >/dev/null 2>&1; then
    OPENSSL_CC="ccache $OPENSSL_CC"  # optional: only speeds up rebuilds
  fi
  CC="$OPENSSL_CC" ./Configure no-shared no-module no-engine no-apps no-tests no-docs \
    --prefix="$OPENSSL_PREFIX" --libdir=lib -fPIC
  make -j"$NJOBS" build_libs
  make install_dev
  cd "$DIR"
  echo "$OPENSSL_VERSION" > "$OPENSSL_PREFIX/.version"
fi

# Build the extension module
cmake -S "$DIR" -B "$DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DPython_EXECUTABLE="$("$PYTHON" -c 'import sys; print(sys.executable)')" \
  -Dnanobind_DIR="$("$PYTHON" -m nanobind --cmake_dir)" \
  -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
  -DOPENSSL_USE_STATIC_LIBS=ON

cmake --build "$DIR/build" -j"$NJOBS" --target _rtc

# Copy into the package
rm -f pydatachannel/_rtc*.so
cp build/_rtc*.so pydatachannel/

echo "Built pydatachannel/$(basename build/_rtc*.so)"
