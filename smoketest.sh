#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
WHEEL_DIR="${1:?Usage: smoketest.sh <wheel-directory>}"
WHEEL_DIR="$(cd "$WHEEL_DIR" && pwd)"

VENV_DIR="$(mktemp -d)"
trap 'rm -rf "$VENV_DIR"' EXIT
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install "$WHEEL_DIR"/*.whl

for toml in "$REPO_DIR"/*/pyproject.toml; do
  module="$(basename "$(dirname "$toml")" | tr '-' '_')"
  python3 -c "import $module; $module.smoketest()" && echo "$module: OK"
done
