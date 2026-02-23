#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
WHEEL_DIR="${1:?Usage: smoketest.sh <wheel-directory>}"
WHEEL_DIR="$(cd "$WHEEL_DIR" && pwd)"

# Create a temporary virtualenv
VENV_DIR="$(mktemp -d)"
trap 'rm -rf "$VENV_DIR"' EXIT
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null

# Install all wheels from the given directory
pip install "$WHEEL_DIR"/*.whl

# Auto-discover and run per-package smoketests
TESTS=("$REPO_DIR"/*/smoketest.sh)
if [ ${#TESTS[@]} -eq 0 ]; then
  echo "No smoketests found."
  exit 1
fi

PASSED=0
FAILED=()

for test in "${TESTS[@]}"; do
  [ -f "$test" ] || continue
  pkg="$(basename "$(dirname "$test")")"
  echo "========================================="
  echo "Smoketest: $pkg"
  echo "========================================="
  if bash "$test"; then
    PASSED=$((PASSED + 1))
  else
    FAILED+=("$pkg")
  fi
  echo
done

echo "========================================="
if [ ${#FAILED[@]} -ne 0 ]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "All $PASSED package(s) passed."
