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
case "$(uname -s)" in MINGW*|MSYS*) WINDOWS=1 ;; *) WINDOWS="" ;; esac
if [ -n "$WINDOWS" ]; then
  # BLASFEO's x86 assembly kernels assume the SysV calling convention; use the C fallback on Windows
  BLAS_TARGET="GENERIC"
elif [[ "$OSTYPE" == "darwin"* ]]; then
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
  # qpOASES + blasfeo both call malloc()/posix_memalign() without including
  # <stdlib.h>. C99/C2x and modern gcc/clang reject implicit declarations as
  # errors. qpOASES also has a real Constraints*/Constraints** pointer bug
  # that gcc 14+ now flags as an error too. Downgrade both so the upstream
  # (pinned) sources keep compiling.
  "-DCMAKE_C_FLAGS=-Wno-implicit-function-declaration -Wno-incompatible-pointer-types"
)
if [ -n "$WINDOWS" ]; then
  ACADOS_FLAGS+=(-DHPIPM_TARGET=GENERIC)
fi
if [[ "$OSTYPE" == "darwin"* ]]; then
  ACADOS_FLAGS+=(
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_MACOSX_RPATH=1
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
cmake --build . -j"$NJOBS" --target install
cd "$DIR"

# we don't ship sample json templates
rm -f "$INSTALL_DIR"/lib/*.json

# python interface package (acados_template)
rm -rf "$TEMPLATE_DIR"
cp -r acados-src/interfaces/acados_template/acados_template "$TEMPLATE_DIR"

# strip future_fstrings (avoids needing the compatibility package on py>=3.6).
# Cython chokes on the unknown encoding in .pyx/.pxd too, not just .py.
find "$TEMPLATE_DIR" -type f \( -name '*.py' -o -name '*.pyx' -o -name '*.pxd' \) \
  -exec sed -i.bak '/future.fstrings/d' {} +
find "$TEMPLATE_DIR" -name '*.bak' -delete

# acados_template's gnsf/check_reformulation.py uses an absolute `from
# acados_template.utils import ...` that only worked when acados_template was
# itself a top-level package on the path. We ship it as `acados.acados_template`,
# so rewrite to the relative form the rest of gnsf already uses.
if [ -f "$TEMPLATE_DIR/gnsf/check_reformulation.py" ]; then
  sed -i.bak 's/^from acados_template\.utils /from ..utils /' "$TEMPLATE_DIR/gnsf/check_reformulation.py"
  rm -f "$TEMPLATE_DIR/gnsf/check_reformulation.py.bak"
fi

# render_template() quotes the tera arguments but not the t_renderer path, and
# runs it through cmd.exe (os.system), which strips the command's outer quote
# pair. Quote the executable and wrap the whole command so a spaced path works.
sed -i.bak "s|f\"{tera_path} |f\"'{tera_path}' |" "$TEMPLATE_DIR/utils.py"
sed -i "s|os_cmd = \(os_cmd\.replace.*\)|os_cmd = '\"' + \1 + '\"'|" "$TEMPLATE_DIR/utils.py"
rm -f "$TEMPLATE_DIR/utils.py.bak"

# build tera renderer (needs cargo)
if [ -n "$WINDOWS" ]; then
  # no rust toolchain requirement on Windows: fetch the release binary acados_template pins
  TERA_VERSION="$(sed -n 's/^TERA_VERSION *= *"\(.*\)"/\1/p' "$TEMPLATE_DIR/utils.py" | head -1)"
  mkdir -p "$INSTALL_DIR/bin"
  curl -fSL -o "$INSTALL_DIR/bin/t_renderer.exe" "https://github.com/acados/tera_renderer/releases/download/v${TERA_VERSION}/t_renderer-v${TERA_VERSION}-windows"
elif ! command -v cargo >/dev/null 2>&1; then
  echo "installing rust toolchain (needed for tera_renderer)..."
  curl -LsSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi

if [ -z "$WINDOWS" ]; then
  mkdir -p "$INSTALL_DIR/bin"
  cd "$DIR/acados-src/interfaces/acados_template/tera_renderer/"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    cargo build --release --target aarch64-apple-darwin
    cp target/aarch64-apple-darwin/release/t_renderer "$INSTALL_DIR/bin/t_renderer"
  else
    cargo build --release
    cp target/release/t_renderer "$INSTALL_DIR/bin/t_renderer"
  fi
  cd "$DIR"
fi

# vendor a slim casadi: install the upstream wheel into a throwaway directory
# (uv resolves the right platform wheel automatically), then move the casadi/
# tree out and slim it.
echo "vendoring casadi $CASADI_VERSION ..."
rm -rf "$CASADI_DIR" casadi-target
uv pip install --python 3.12 --target casadi-target --no-deps --quiet "casadi==$CASADI_VERSION"
mv casadi-target/casadi "$CASADI_DIR"
rm -rf casadi-target

# drop everything except the bits openpilot actually needs:
#   - __init__.py, casadi.py, tools/  (Python wrapper)
#   - _casadi.so                       (CPython extension; same name on linux+darwin)
#   - libcasadi.{so,dylib}*            (the C++ runtime that _casadi.so links to)
# openpilot only uses symbolic SX/MX/Function/jacobian etc., which live in
# libcasadi + _casadi. Solver plugins (conic_*, nlpsol_*, integrator_*, ...)
# and their third-party backends (ipopt, bonmin, hpipm, fatrop, ...) are
# loaded lazily via dlopen and never reached.
cd "$CASADI_DIR"
shopt -s extglob
# libc++.*.dylib only exists on darwin and is needed by _casadi.so via @rpath
rm -rf !(__init__.py|casadi.py|_casadi.*|tools|libcasadi.*|libc++.*|*.dll)
shopt -u extglob

cd "$DIR"
rm -rf casadi-wheel

echo "Installed acados to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
echo "Vendored casadi (slim) at $CASADI_DIR"
du -sh "$CASADI_DIR"
