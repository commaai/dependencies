#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export MACOSX_DEPLOYMENT_TARGET=14.0  # for OpenSSL and the extension alike; matches the wheel tag in setup.py
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

# fetch <dir> <repo> <tag>: a shallow clone of the tag, kept until the tag changes
fetch() {
  if [ "$(git -C "$1" describe --tags --exact-match 2>/dev/null)" != "$3" ]; then
    rm -rf "$1"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$3" "https://github.com/$2.git" "$1"
  fi
}

fetch libdatachannel-src paullouisageneau/libdatachannel v0.24.6
git -C libdatachannel-src submodule update -q --init --depth 1 deps/plog deps/usrsctp deps/libjuice deps/libsrtp

# OpenSSL, linked statically: the wheel needs no system libssl, whatever its version. Installed to a versioned prefix,
# whose lib/ layout libdatachannel's CMake expects on macOS.
OPENSSL=openssl-3.5.8
fetch openssl-src openssl/openssl "$OPENSSL"
if [ ! -f "build/$OPENSSL/lib/libssl.a" ]; then
  (cd openssl-src && CC="$(command -v ccache || true) ${CC:-cc}" ./Configure no-shared no-module no-engine no-apps no-tests no-docs \
     no-autoload-config -fPIC --prefix="$PWD/../build/$OPENSSL" --libdir=lib &&
   make -j"$NJOBS" build_libs && make install_dev)
fi

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DPython_EXECUTABLE="${PYTHON:-python3}" -DOPENSSL_ROOT_DIR="$PWD/build/$OPENSSL" \
  -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build build -j"$NJOBS" --target _rtc
cp build/_rtc*.so pydatachannel/
