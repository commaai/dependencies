#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"

# Create a temporary virtualenv
VENV_DIR="$(mktemp -d)"
trap 'rm -rf "$VENV_DIR"' EXIT
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null

# Auto-discover packages: any subdirectory containing a pyproject.toml
PACKAGES=()
for toml in "$REPO_DIR"/*/pyproject.toml; do
  [ -f "$toml" ] || continue
  PACKAGES+=("$(dirname "$toml")")
done

if [ ${#PACKAGES[@]} -eq 0 ]; then
  echo "No packages found."
  exit 1
fi

FAILED=()

for pkg in "${PACKAGES[@]}"; do
  name="$(basename "$pkg")"
  echo "========================================="
  echo "Testing: $name"
  echo "========================================="

  # Install from git URL with subdirectory (simulates real-world usage)
  echo "[$name] pip install ..."
  pip install "$pkg" --verbose

  # Verify import works
  module="${name//-/_}"
  echo "[$name] Verifying import of $module ..."
  python -c "import $module; print(f'{$module.__name__} OK')"

  echo "[$name] PASSED"
  echo
done

if [ ${#FAILED[@]} -ne 0 ]; then
  echo "FAILED packages: ${FAILED[*]}"
  exit 1
fi

echo "All ${#PACKAGES[@]} package(s) passed."
echo
echo "Installed sizes:"
for pkg in "${PACKAGES[@]}"; do
  name="$(basename "$pkg")"
  module="${name//-/_}"
  mod_dir="$(python -c "import $module, os; print(os.path.dirname($module.__file__))")"
  size="$(du -sh "$mod_dir" | cut -f1)"
  echo "  $name: $size"
done
