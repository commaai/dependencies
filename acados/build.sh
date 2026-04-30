#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

# v0.2.2
VERSION="8af9b0ad180940ef611884574a0b27a43504311d"
INSTALL_DIR="$DIR/acados/install"
TEMPLATE_DIR="$DIR/acados/acados_template"
CASADI_DIR="$DIR/casadi"
CASADI_VERSION="3.6.7"

NJOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# pick BLAS target per host arch
ARCH="$(uname -m)"
if [[ "$OSTYPE" == "darwin"* ]]; then
  # this BLASFEO version doesn't have an Apple Silicon target; Cortex-A57
  # baseline ARMv8 SIMD compiles and runs fine on M1+.
  BLAS_TARGET="ARMV8A_ARM_CORTEX_A57"
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
  # acados (and several of its submodules) still pin cmake_minimum_required <3.5;
  # CMake 4 removed that compatibility, so re-enable it here.
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)
if [[ "$OSTYPE" == "darwin"* ]]; then
  ACADOS_FLAGS+=(
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_MACOSX_RPATH=1
    # qpOASES C code uses malloc() without including <stdlib.h>; macOS clang
    # rejects implicit function declarations as errors by default.
    "-DCMAKE_C_FLAGS=-Wno-implicit-function-declaration"
  )
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

# we don't ship sample json templates
rm -f "$INSTALL_DIR"/lib/*.json

# python interface package (acados_template)
rm -rf "$TEMPLATE_DIR"
cp -r acados-src/interfaces/acados_template/acados_template "$TEMPLATE_DIR"

# strip future_fstrings (avoids needing the compatibility package on py>=3.6)
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

# vendor a slim casadi: take the upstream wheel, strip the solver plugins/
# include headers/static archives that openpilot's MPC code never touches.
echo "vendoring casadi $CASADI_VERSION ..."
rm -rf "$CASADI_DIR" casadi-wheel
mkdir -p casadi-wheel

if [[ "$OSTYPE" == "darwin"* ]]; then
  CASADI_PLAT_FLAGS=(--platform macosx_11_0_arm64)
elif [[ "$ARCH" == "aarch64" ]]; then
  CASADI_PLAT_FLAGS=(--platform manylinux_2_17_aarch64 --platform manylinux2014_aarch64)
else
  CASADI_PLAT_FLAGS=(--platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64)
fi

# pip is available inside the manylinux container; outside we use uv-managed pip
PIP=(python3 -m pip)
if ! python3 -m pip --version >/dev/null 2>&1; then
  PIP=(uv pip)
fi

"${PIP[@]}" download --only-binary :all: --no-deps \
  --python-version 3.12 "${CASADI_PLAT_FLAGS[@]}" \
  "casadi==$CASADI_VERSION" -d casadi-wheel

unzip -q casadi-wheel/casadi-*.whl -d casadi-wheel/extracted
mv casadi-wheel/extracted/casadi "$CASADI_DIR"

# drop everything we don't need: solver plugins, dev headers, build glue
cd "$CASADI_DIR"
rm -rf include lib64 cmake casadi-cli cbc clp highs pkgconfig
find . -maxdepth 1 -name '*.la' -delete
find . -maxdepth 1 -name '*.a' -delete
# casadi solver plugins are loaded lazily via dlopen; openpilot only uses
# symbolic SX/MX, vertcat, jacobian, etc., which live in libcasadi.so + _casadi.so.
find . -maxdepth 1 \( \
    -name 'libcasadi_conic_*.so*' -o \
    -name 'libcasadi_nlpsol_*.so*' -o \
    -name 'libcasadi_integrator_*.so*' -o \
    -name 'libcasadi_linsol_*.so*' -o \
    -name 'libcasadi_rootfinder_*.so*' -o \
    -name 'libcasadi_interpolant_*.so*' -o \
    -name 'libcasadi_xmlfile_*.so*' -o \
    -name 'libcasadi_importer_*.so*' -o \
    -name 'libcasadi_sundials_common.so*' -o \
    -name 'libcasadi-tp-*.so*' \
  \) -delete
# third-party solver libraries (not referenced by libcasadi.so directly)
find . -maxdepth 1 \( \
    -name 'libalpaqa*.so*' -o -name 'libbonmin*.so*' -o \
    -name 'libcoin*.so*' -o -name 'libCbc*.so*' -o -name 'libClp*.so*' -o \
    -name 'libCgl*.so*' -o -name 'libCoinUtils*.so*' -o -name 'libOsi*.so*' -o \
    -name 'libcplex_adaptor.so' -o -name 'libgurobi_adaptor.so' -o \
    -name 'libhighs*.so*' -o -name 'libhpipm*.so*' -o \
    -name 'libipopt*.so*' -o -name 'libsipopt*.so*' -o \
    -name 'libdaqp*.so*' -o -name 'libfatrop*.so*' -o \
    -name 'libosqp*.so*' -o -name 'libqdldl*.so*' -o \
    -name 'libsleqp*.so*' -o -name 'libtrlib*.so*' -o \
    -name 'libknitro*.so*' -o -name 'libmadnlp*.so*' -o \
    -name 'libsnopt*.so*' -o -name 'libworhp*.so*' -o \
    -name 'libampl*.so*' -o -name 'libsuperscs*.so*' -o \
    -name 'libproxqp*.so*' -o -name 'libqpoases*.so*' -o \
    -name 'libgfortran*.so*' -o -name 'libquadmath*.so*' -o \
    -name 'libblasfeo.so*' -o -name 'libmatlab_ipc.so' \
  \) -delete

cd "$DIR"
rm -rf casadi-wheel

echo "Installed acados to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
echo "Vendored casadi (slim) at $CASADI_DIR"
du -sh "$CASADI_DIR"
