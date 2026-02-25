#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$REPO_DIR"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv not found, installing..."
  curl -LsSf https://astral.sh/uv/install.sh | sh

  if [ -x "$HOME/.local/bin/uv" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

uv venv --allow-existing
source .venv/bin/activate

# do the build
uv pip install */

# do the tests
echo
echo "Verifying imports..."
for toml in */pyproject.toml; do
  [ -f "$toml" ] || continue
  name="${toml%%/*}"
  module="${name//-/_}"
  python -c "import $module; $module.smoketest(); print('$module OK')"
done

echo
echo "Installed sizes:"
for toml in */pyproject.toml; do
  [ -f "$toml" ] || continue
  name="${toml%%/*}"
  module="${name//-/_}"
  mod_dir="$(python -c "import $module, os; print(os.path.dirname($module.__file__))")"
  size="$(du -sh "$mod_dir" | cut -f1)"
  echo "  $name: $size"
done

echo
echo "Done in $SECONDS seconds."
