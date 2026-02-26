#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

DIST_DIR="dist"
USE_MANYLINUX=0
PUBLISH_ONLY=0
PUBLISH_SHIMS=0

die() {
  echo "error: $*" >&2
  exit 1
}

publish_wheels() {
  command -v gh >/dev/null 2>&1 || die "gh not found in PATH"

  local repo="${GITHUB_REPOSITORY:-}"
  if [[ -z "$repo" ]]; then
    repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  [[ -n "$repo" ]] || die "could not determine GitHub repository"

  echo
  echo "Publishing wheels to GitHub Releases ($repo)"

  shopt -s nullglob
  for toml in */pyproject.toml; do
    local pkg module version tag
    pkg="$(dirname "$toml")"
    module="${pkg//-/_}"
    version="$(python3 -c "import tomllib; print(tomllib.load(open('$toml', 'rb'))['project']['version'])")"
    tag="${pkg}/v${version}"

    local wheels=("$DIST_DIR/${module}-${version}-"*.whl)
    [[ ${#wheels[@]} -gt 0 ]] || die "missing wheel for $pkg ($module-$version) in $DIST_DIR"

    echo "[$pkg] Uploading ${#wheels[@]} wheel(s) to $tag"

    if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
      gh release upload "$tag" "${wheels[@]}" --repo "$repo" --clobber
    else
      if ! gh release create "$tag" "${wheels[@]}" --repo "$repo" --title "$pkg v$version" --notes "Platform wheels for $pkg $version"; then
        gh release upload "$tag" "${wheels[@]}" --repo "$repo" --clobber
      fi
    fi
  done
  shopt -u nullglob
}

publish_shims() {
  local repo="${GITHUB_REPOSITORY:-}"
  if [[ -z "$repo" ]]; then
    command -v gh >/dev/null 2>&1 || die "gh not found in PATH and GITHUB_REPOSITORY is unset"
    repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  [[ -n "$repo" ]] || die "could not determine GitHub repository"

  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null || true)"
  fi
  [[ -n "$token" ]] || die "set GH_TOKEN (or GITHUB_TOKEN) to publish shim branch"

  local repo_url="https://github.com/${repo}"
  local tmp
  tmp="$(mktemp -d)"

  for toml in */pyproject.toml; do
    local pkg module version tag datadir description scripts_block
    pkg="$(dirname "$toml")"
    module="${pkg//-/_}"
    version="$(python3 -c "import tomllib; print(tomllib.load(open('$toml', 'rb'))['project']['version'])")"
    tag="${pkg}/v${version}"
    datadir="$(python3 -c "import tomllib; t=tomllib.load(open('$toml', 'rb')); p=t.get('tool', {}).get('setuptools', {}).get('package-data', {}).get('$module', [''])[0]; print(p.split('/')[0])")"
    description="$(python3 -c "import tomllib; print(tomllib.load(open('$toml', 'rb'))['project']['description'])")"
    scripts_block="$(python3 - "$toml" <<'PY'
import sys
import tomllib

data = tomllib.load(open(sys.argv[1], "rb"))
scripts = data.get("project", {}).get("scripts", {}) or {}
for name, target in scripts.items():
  print(f'{name} = "{target}"')
PY
)"

    local pkg_dir="$tmp/$pkg"
    local mod_dir="$pkg_dir/$module"
    mkdir -p "$mod_dir"
    cp "$pkg/$module/__init__.py" "$mod_dir/"

    cat > "$pkg_dir/pyproject.toml" <<TOML
[build-system]
requires = ["setuptools>=64", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "$pkg"
version = "$version"
description = "$description (pre-built)"
requires-python = ">=3.8"
TOML

    if [[ -n "$scripts_block" ]]; then
      {
        echo
        echo "[project.scripts]"
        echo "$scripts_block"
      } >> "$pkg_dir/pyproject.toml"
    fi

    cat >> "$pkg_dir/pyproject.toml" <<TOML

[tool.setuptools.packages.find]
include = ["${module}*"]

[tool.setuptools.package-data]
$module = ["${datadir}/**/*"]
TOML

    cat > "$pkg_dir/setup.py" <<SETUP
import os
import platform
import zipfile
from io import BytesIO
from urllib.request import urlopen

from setuptools.command.build_py import build_py

REPO_URL = "${repo_url}"
TAG = "${tag}"
VERSION = "${version}"
MODULE = "${module}"
DATADIR = "${datadir}"

PLATFORM_MAP = {
  ("Linux", "x86_64"): "linux_x86_64",
  ("Linux", "aarch64"): "linux_aarch64",
  ("Darwin", "arm64"): "macosx_11_0_arm64",
}


class InstallPrebuilt(build_py):
  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(pkg_dir, MODULE, DATADIR)

    if not os.path.exists(os.path.join(data_dir, "bin")):
      key = (platform.system(), platform.machine())
      plat = PLATFORM_MAP.get(key)
      if plat is None:
        raise RuntimeError(f"unsupported platform: {key}")

      whl_name = f"{MODULE}-{VERSION}-py3-none-{plat}.whl"
      url = f"{REPO_URL}/releases/download/{TAG}/{whl_name}"

      print(f"Downloading {url} ...")
      data = urlopen(url).read()

      print(f"Extracting {DATADIR} ...")
      with zipfile.ZipFile(BytesIO(data)) as zf:
        prefix = f"{MODULE}/{DATADIR}/"
        alt_prefix = f"{MODULE}-{VERSION}.data/purelib/{MODULE}/{DATADIR}/"
        for info in zf.infolist():
          for p in (prefix, alt_prefix):
            if info.filename.startswith(p):
              rel = info.filename[len(p):]
              if not rel:
                continue
              dest = os.path.join(data_dir, rel)
              if info.is_dir():
                os.makedirs(dest, exist_ok=True)
              else:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                  f.write(zf.read(info))
                if info.external_attr >> 16 & 0o111:
                  os.chmod(dest, 0o755)
              break

    super().run()


def setup():
  from setuptools import setup as _setup

  _setup(cmdclass={"build_py": InstallPrebuilt})


if __name__ == "__main__":
  setup()
SETUP
  done

  (
    cd "$tmp"
    git init
    git checkout -b releases
    git add .
    if git diff --cached --quiet; then
      echo "No shim changes to publish"
      exit 0
    fi
    git -c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com" commit -m "update shim packages"
    git remote add origin "https://x-access-token:${token}@github.com/${repo}.git"
    git push -f origin releases
  )

  rm -rf "$tmp"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manylinux)
      USE_MANYLINUX=1
      shift
      ;;
    --publish-only)
      PUBLISH_ONLY=1
      shift
      ;;
    --publish-shims)
      PUBLISH_SHIMS=1
      shift
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ $PUBLISH_ONLY -eq 1 && $USE_MANYLINUX -eq 1 ]]; then
  die "--publish-only cannot be combined with --manylinux"
fi

if [[ $PUBLISH_SHIMS -eq 1 && $PUBLISH_ONLY -eq 0 ]]; then
  [[ $USE_MANYLINUX -eq 0 ]] || die "--publish-shims cannot be combined with --manylinux"
  publish_shims
  exit 0
fi

if [[ $PUBLISH_ONLY -eq 0 ]]; then
  if [[ $USE_MANYLINUX -eq 1 ]]; then
    ./build.sh --manylinux
  else
    ./build.sh
  fi
fi

publish_wheels

if [[ $PUBLISH_SHIMS -eq 1 ]]; then
  publish_shims
fi
