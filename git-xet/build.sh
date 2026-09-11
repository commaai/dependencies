#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="0.2.2.dev1"
REVISION="3cb5b2bf8e34bca2423a29d3110bb03c22a4a581"
SOURCE_URL="https://github.com/haraschax/xet-core.git"
RUST_VERSION="1.95.0"
INSTALL_DIR="$DIR/git_xet/bin"

if [ -f "$INSTALL_DIR/LICENSE" ] && [ -f "$INSTALL_DIR/.version" ] && [ "$(cat "$INSTALL_DIR/.version")" = "$REVISION" ]; then
  echo "git-xet $VERSION already present, skipping."
  exit 0
fi

# Build OpenSSL into the executable; upstream's Linux binaries require system OpenSSL 3.
export CARGO_HOME="$DIR/git_xet/toolchain/cargo"
export RUSTUP_HOME="$DIR/git_xet/toolchain/rustup"
export PATH="$CARGO_HOME/bin:$PATH"
if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION"
fi
rustup toolchain install "$RUST_VERSION" --profile minimal

if [ ! -d "xet-core-src/.git" ]; then
  git clone --filter=blob:none --no-checkout "$SOURCE_URL" xet-core-src
fi
git -C xet-core-src fetch --depth 1 "$SOURCE_URL" "$REVISION"
git -C xet-core-src checkout --force --detach FETCH_HEAD

cd xet-core-src
CARGO_PROFILE_RELEASE_DEBUG=0 CARGO_PROFILE_RELEASE_STRIP=symbols \
  cargo +"$RUST_VERSION" build --locked --release --package git_xet --features git2-vendored-openssl

mkdir -p "$INSTALL_DIR"
cp target/release/git-xet "$INSTALL_DIR/"
cp LICENSE "$INSTALL_DIR/"
echo "$REVISION" > "$INSTALL_DIR/.version"
echo "Installed git-xet $VERSION to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
