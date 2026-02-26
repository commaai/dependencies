#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

./build.sh

REPO=commaai/dependencies

echo
echo "Publishing wheels to GitHub Releases ($REPO)"

shopt -s nullglob
for toml in */pyproject.toml; do
  pkg="$(dirname "$toml")"
  module="${pkg//-/_}"
  version="$(python3 -c "import tomllib; print(tomllib.load(open('$toml', 'rb'))['project']['version'])")"
  tag="${pkg}/v${version}"

  wheels=("dist/${module}-${version}-"*.whl)
  if [[ ${#wheels[@]} -eq 0 ]]; then
    echo "missing wheel for $pkg ($module-$version) in dist" >&2
    exit 1
  fi

  echo "[$pkg] Uploading ${#wheels[@]} wheel(s) to $tag"

  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$tag" "${wheels[@]}" --repo "$REPO" --clobber
  else
    if ! gh release create "$tag" "${wheels[@]}" --repo "$REPO" --title "$pkg v$version" --notes "Platform wheels for $pkg $version"; then
      gh release upload "$tag" "${wheels[@]}" --repo "$REPO" --clobber
    fi
  fi
done
shopt -u nullglob

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi

if [[ -z "$TOKEN" ]]; then
  echo "set GH_TOKEN (or GITHUB_TOKEN) to publish shim branch" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
python3 - "$TMP_DIR" "$REPO" <<'PY'
import json
import pathlib
import shutil
import tomllib
import sys

tmp_dir = pathlib.Path(sys.argv[1])
repo = sys.argv[2]
repo_url = f"https://github.com/{repo}"

for toml in sorted(pathlib.Path(".").glob("*/pyproject.toml")):
  pkg = toml.parent.name
  module = pkg.replace("-", "_")
  data = tomllib.load(toml.open("rb"))
  version = str(data["project"]["version"])
  tag = f"{pkg}/v{version}"
  description = data["project"]["description"]
  patterns = data.get("tool", {}).get("setuptools", {}).get("package-data", {}).get(module, [""])
  datadir = patterns[0].split("/", 1)[0] if patterns and patterns[0] else ""
  scripts = data.get("project", {}).get("scripts", {}) or {}

  pkg_dir = tmp_dir / pkg
  mod_dir = pkg_dir / module
  mod_dir.mkdir(parents=True, exist_ok=True)
  shutil.copy2(pathlib.Path(pkg) / module / "__init__.py", mod_dir / "__init__.py")

  lines = [
    "[build-system]",
    'requires = ["setuptools>=64", "wheel"]',
    'build-backend = "setuptools.build_meta"',
    "",
    "[project]",
    f'name = "{pkg}"',
    f'version = "{version}"',
    f"description = {json.dumps(description + ' (pre-built)')}",
    'requires-python = ">=3.8"',
  ]

  if scripts:
    lines += ["", "[project.scripts]"]
    for name, target in scripts.items():
      lines.append(f"{name} = {json.dumps(target)}")

  lines += [
    "",
    "[tool.setuptools.packages.find]",
    f'include = ["{module}*"]',
    "",
    "[tool.setuptools.package-data]",
    f'{module} = ["{datadir}/**/*"]',
  ]

  (pkg_dir / "pyproject.toml").write_text("\n".join(lines) + "\n")

  setup_text = f'''import os
import platform
import zipfile
from io import BytesIO
from urllib.request import urlopen

from setuptools.command.build_py import build_py

REPO_URL = {repo_url!r}
TAG = {tag!r}
VERSION = {version!r}
MODULE = {module!r}
DATADIR = {datadir!r}

PLATFORM_MAP = {{
  ("Linux", "x86_64"): "linux_x86_64",
  ("Linux", "aarch64"): "linux_aarch64",
  ("Darwin", "arm64"): "macosx_11_0_arm64",
}}


class InstallPrebuilt(build_py):
  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(pkg_dir, MODULE, DATADIR)

    if not os.path.exists(os.path.join(data_dir, "bin")):
      key = (platform.system(), platform.machine())
      plat = PLATFORM_MAP.get(key)
      if plat is None:
        raise RuntimeError(f"unsupported platform: {{key}}")

      whl_name = f"{{MODULE}}-{{VERSION}}-py3-none-{{plat}}.whl"
      url = f"{{REPO_URL}}/releases/download/{{TAG}}/{{whl_name}}"

      print(f"Downloading {{url}} ...")
      data = urlopen(url).read()

      print(f"Extracting {{DATADIR}} ...")
      with zipfile.ZipFile(BytesIO(data)) as zf:
        prefix = f"{{MODULE}}/{{DATADIR}}/"
        alt_prefix = f"{{MODULE}}-{{VERSION}}.data/purelib/{{MODULE}}/{{DATADIR}}/"
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
  _setup(cmdclass={{"build_py": InstallPrebuilt}})


if __name__ == "__main__":
  setup()
'''

  (pkg_dir / "setup.py").write_text(setup_text)
PY

(
  cd "$TMP_DIR"
  git init
  git checkout -b releases
  git add .
  if git diff --cached --quiet; then
    echo "No shim changes to publish"
    exit 0
  fi
  git -c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com" commit -m "update shim packages"
  git remote add origin "https://x-access-token:${TOKEN}@github.com/${REPO}.git"
  git push -f origin releases
)

rm -rf "$TMP_DIR"
