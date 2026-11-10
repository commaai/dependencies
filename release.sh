#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

if ! command -v uvx >/dev/null 2>&1; then
  UV_BIN_DIR="$HOME/.local/bin"
  mkdir -p "$UV_BIN_DIR"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$UV_BIN_DIR" sh
  export PATH="$UV_BIN_DIR:$PATH"
fi

shopt -s nullglob
wheels=(dist/*.whl)
shopt -u nullglob

if [[ ${#wheels[@]} -eq 0 ]]; then
  echo "no wheels in dist/" >&2
  exit 1
fi

echo "Publishing ${#wheels[@]} wheel(s) to PyPI:"
printf '  %s\n' "${wheels[@]}"

# PyPI rate-limits new project creation (~20/hour/user), and twine aborts a
# batch at the first 429. Upload everything in one go, and only on a 429 fall
# back to one wheel at a time, retrying the throttled ones once the rate-limit
# window has reset. --skip-existing makes all of this idempotent.
log=$(mktemp)
trap 'rm -f "$log"' EXIT
if uvx twine upload --skip-existing "${wheels[@]}" 2>&1 | tee "$log"; then
  echo "all wheels published"
  exit 0
fi
if ! grep -Eq '(^|[^0-9])429([^0-9]|$)' "$log"; then
  exit 1
fi

remaining=("${wheels[@]}")
for pass in 1 2 3 4 5 6; do
  failed=()
  for whl in "${remaining[@]}"; do
    if ! uvx twine upload --skip-existing "$whl" 2>&1 | tee "$log"; then
      grep -Eq '(^|[^0-9])429([^0-9]|$)' "$log" || exit 1
      failed+=("$whl")
    fi
  done

  if [[ ${#failed[@]} -eq 0 ]]; then
    echo "all wheels published"
    exit 0
  fi

  remaining=("${failed[@]}")
  echo "pass $pass: ${#remaining[@]} wheel(s) rate-limited; waiting 15m for the window to reset"
  if [[ "$pass" -lt 6 ]]; then sleep 900; fi
done

echo "upload failed after all retries:" >&2
printf '  %s\n' "${remaining[@]}" >&2
exit 1
