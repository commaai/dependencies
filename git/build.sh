#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

VERSION="2.47.1"
INSTALL_DIR="$DIR/git/install"
VERSION_FILE="$INSTALL_DIR/.version"

# Skip if already at correct version
if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
  echo "git $VERSION already present, skipping."
  exit 0
fi

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PREFIX="$DIR/build/prefix"
mkdir -p "$DIR/build"

# Clone git source
if [ ! -d "git-src/.git" ]; then
  rm -rf git-src
  git clone --depth 1 https://github.com/git/git.git git-src
fi
git -C git-src fetch --depth 1 origin "v${VERSION}"
git -C git-src checkout --force FETCH_HEAD

# Build git
cd git-src
make prefix="$PREFIX" \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_EXPAT=YesPlease \
  INSTALL_SYMLINKS=1 \
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
