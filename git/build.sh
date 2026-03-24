#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="2.47.1"
OPENSSL_VERSION="openssl-3.4.1"
CURL_VERSION="curl-8_12_1"
ZLIB_VERSION="v1.3.1"
INSTALL_DIR="$DIR/git/install"
VERSION_FILE="$INSTALL_DIR/.version"

# Skip if already at correct version
if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
  echo "git $VERSION already present, skipping."
  exit 0
fi

PLATFORM="$(uname -s)"
NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

# --- Build zlib (static) ---
if [ ! -d "zlib-src/.git" ]; then
  rm -rf zlib-src
  git clone --depth 1 https://github.com/madler/zlib.git zlib-src
fi
git -C zlib-src fetch --depth 1 origin "$ZLIB_VERSION"
git -C zlib-src checkout --force FETCH_HEAD

cd zlib-src
./configure --prefix="$PREFIX" --static
make -j"$NJOBS"
make install
cd "$DIR"

# --- Build OpenSSL (static) ---
if [ ! -d "openssl-src/.git" ]; then
  rm -rf openssl-src
  git clone --depth 1 https://github.com/openssl/openssl.git openssl-src
fi
git -C openssl-src fetch --depth 1 origin "$OPENSSL_VERSION"
git -C openssl-src checkout --force FETCH_HEAD

cd openssl-src
./Configure \
  --prefix="$PREFIX" \
  --libdir=lib \
  no-shared \
  no-tests \
  no-docs
make -j"$NJOBS"
make install_sw
cd "$DIR"

# --- Build curl (static, with openssl+zlib) ---
if [ ! -d "curl-src/.git" ]; then
  rm -rf curl-src
  git clone --depth 1 https://github.com/curl/curl.git curl-src
fi
git -C curl-src fetch --depth 1 origin "$CURL_VERSION"
git -C curl-src checkout --force FETCH_HEAD

cd curl-src
autoreconf -fi
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
./configure \
  --prefix="$PREFIX" \
  --with-openssl="$PREFIX" \
  --with-zlib="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-ldap \
  --disable-rtsp \
  --disable-dict \
  --disable-telnet \
  --disable-tftp \
  --disable-pop3 \
  --disable-imap \
  --disable-smb \
  --disable-smtp \
  --disable-gopher \
  --disable-mqtt \
  --disable-manual \
  --disable-docs \
  --without-libpsl \
  --without-brotli \
  --without-zstd \
  --without-libidn2 \
  --without-nghttp2 \
  --without-librtmp
make -j"$NJOBS"
make install
cd "$DIR"

# --- Build git (with static curl+openssl+zlib) ---
if [ ! -d "git-src/.git" ]; then
  rm -rf git-src
  git clone --depth 1 https://github.com/git/git.git git-src
fi
git -C git-src fetch --depth 1 origin "v${VERSION}"
git -C git-src checkout --force FETCH_HEAD

# Gather static link flags for curl and openssl dependencies
# CURL_LIBCURL: used by git-remote-http, git-http-fetch, git-http-push
# LIB_4_CRYPTO: used by git-imap-send and other direct openssl consumers
# Both need transitive deps (-ldl, -lpthread) since we link statically
CRYPTO_DEPS="-lpthread"
CURL_EXTRA=""
if [ "$PLATFORM" = "Linux" ]; then
  CRYPTO_DEPS="$CRYPTO_DEPS -ldl"
elif [ "$PLATFORM" = "Darwin" ]; then
  CURL_EXTRA="-framework SystemConfiguration -framework Security -framework CoreFoundation"
fi

cd git-src
make prefix="$PREFIX" \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_EXPAT=YesPlease \
  INSTALL_SYMLINKS=1 \
  CURLDIR="$PREFIX" \
  CURL_LIBCURL="-L$PREFIX/lib -lcurl -lssl -lcrypto -lz $CRYPTO_DEPS $CURL_EXTRA" \
  OPENSSL_LIBSSL="-L$PREFIX/lib -lssl" \
  LIB_4_CRYPTO="-lcrypto $CRYPTO_DEPS" \
  ZLIB_PATH="$PREFIX" \
  -j"$NJOBS" \
  all
make prefix="$PREFIX" \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_EXPAT=YesPlease \
  INSTALL_SYMLINKS=1 \
  CURLDIR="$PREFIX" \
  CURL_LIBCURL="-L$PREFIX/lib -lcurl -lssl -lcrypto -lz $CRYPTO_DEPS $CURL_EXTRA" \
  OPENSSL_LIBSSL="-L$PREFIX/lib -lssl" \
  LIB_4_CRYPTO="-lcrypto $CRYPTO_DEPS" \
  ZLIB_PATH="$PREFIX" \
  install
cd "$DIR"

# Assemble the package install directory
# Only copy real files from libexec to avoid bloating the wheel with
# copies of the main git binary (builtin commands are symlinks to git)
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/libexec/git-core"

# Main binary
cp "$PREFIX/bin/git" "$INSTALL_DIR/bin/"

# libexec/git-core: copy real files, resolve non-git symlinks, skip git symlinks
cd "$PREFIX/libexec/git-core"
for f in *; do
  if [ -L "$f" ]; then
    target="$(readlink "$f")"
    # Skip symlinks to the main git binary (these are builtins)
    case "$target" in
      git|../../bin/git) continue ;;
    esac
    # Resolve other symlinks (e.g., git-remote-https -> git-remote-http)
    cp -L "$f" "$INSTALL_DIR/libexec/git-core/$f"
  elif [ -f "$f" ]; then
    cp "$f" "$INSTALL_DIR/libexec/git-core/$f"
  fi
done
cd "$DIR"

# Copy git binary into libexec for builtin resolution
cp "$PREFIX/bin/git" "$INSTALL_DIR/libexec/git-core/git"

# Templates
cp -r "$PREFIX/share" "$INSTALL_DIR/"

# Strip binaries
strip "$INSTALL_DIR/bin/git" "$INSTALL_DIR/libexec/git-core/git" 2>/dev/null || true
find "$INSTALL_DIR/libexec/git-core" -maxdepth 1 -type f -perm /111 ! -name "*.sh" -exec strip {} \; 2>/dev/null || true

echo "$VERSION" > "$VERSION_FILE"

echo "Installed git to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
