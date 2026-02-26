#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?usage: ./test_wheels_in_image.sh <image>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

docker build -t wheeltest -f - . <<DOCKERFILE
FROM $IMAGE
RUN if command -v apk >/dev/null; then \
      apk add --no-cache python3 py3-pip bash; \
    elif command -v apt-get >/dev/null; then \
      apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
    elif command -v dnf >/dev/null; then \
      dnf install -y python3 python3-pip; \
    elif command -v pacman >/dev/null; then \
      pacman -Sy --noconfirm python python-pip; \
    elif command -v zypper >/dev/null; then \
      zypper install -y python3 python3-pip; \
    elif command -v xbps-install >/dev/null; then \
      xbps-install -Sy python3 python3-pip bash; \
    fi
DOCKERFILE

docker run --rm -v "$PWD:/work" -w /work wheeltest bash -lc '
  set -euo pipefail
  python3 -m venv /tmp/venv
  /tmp/venv/bin/python -m pip install --upgrade pip >/dev/null
  /tmp/venv/bin/python -m pip install wheels/*.whl
  for toml in */pyproject.toml; do
    module="$(basename "$(dirname "$toml")" | tr "-" "_")"
    /tmp/venv/bin/python -c "import $module; $module.smoketest()" && echo "$module: OK"
  done
'
