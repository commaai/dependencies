#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

# v0.2.2
VERSION="8af9b0ad180940ef611884574a0b27a43504311d"
INSTALL_DIR="$DIR/acados/install"
TEMPLATE_DIR="$DIR/acados/acados_template"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# pick BLAS target per host arch — match openpilot's vendored build
ARCH="$(uname -m)"
if [[ "$OSTYPE" == "darwin"* ]]; then
  # openpilot's prebuilt darwin binaries used X64_AUTOMATIC; BLASFEO falls back
  # to runtime detection of ARM features when arch is forced via CMAKE_OSX_ARCHITECTURES
  BLAS_TARGET="X64_AUTOMATIC"
elif [[ "$ARCH" == "aarch64" ]]; then
  # Cortex-A57 = TICI baseline; safe for any modern aarch64
  BLAS_TARGET="ARMV8A_ARM_CORTEX_A57"
else
  BLAS_TARGET="X64_AUTOMATIC"
fi

ACADOS_FLAGS=(
  -DACADOS_WITH_QPOASES=ON
  -UBLASFEO_TARGET
  -DBLASFEO_TARGET="$BLAS_TARGET"
  -DACADOS_INSTALL_DIR="$INSTALL_DIR"
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
)
if [[ "$OSTYPE" == "darwin"* ]]; then
  ACADOS_FLAGS+=(-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_MACOSX_RPATH=1)
fi

# clone/update source
if [ ! -d "acados-src/.git" ]; then
  rm -rf acados-src
  git clone https://github.com/acados/acados.git acados-src
fi
git -C acados-src fetch --all --tags
git -C acados-src checkout --force "$VERSION"
git -C acados-src submodule update --init --recursive --depth=1

# build acados
mkdir -p build
cd build
cmake "${ACADOS_FLAGS[@]}" "$DIR/acados-src"
make -j"$NJOBS" install
cd "$DIR"

# clean install dir of stuff we don't need
rm -f "$INSTALL_DIR"/lib/*.json

# python interface package
rm -rf "$TEMPLATE_DIR"
cp -r acados-src/interfaces/acados_template/acados_template "$TEMPLATE_DIR"

# strip future_fstrings (avoids needing the compatibility package on py>=3.6)
# sed -i differs between GNU and BSD; use a portable form
find "$TEMPLATE_DIR" -type f -name '*.py' -exec sed -i.bak '/future.fstrings/d' {} +
find "$TEMPLATE_DIR" -name '*.bak' -delete

# build tera renderer (needs cargo)
if ! command -v cargo >/dev/null 2>&1; then
  echo "installing rust toolchain (needed for tera_renderer)..."
  curl -LsSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi

cd "$DIR/acados-src/interfaces/acados_template/tera_renderer/"
if [[ "$OSTYPE" == "darwin"* ]]; then
  cargo build --release --target aarch64-apple-darwin
  cp target/aarch64-apple-darwin/release/t_renderer "$INSTALL_DIR/bin/t_renderer"
else
  cargo build --release
  cp target/release/t_renderer "$INSTALL_DIR/bin/t_renderer"
fi

cd "$DIR"

echo "Installed acados to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
