#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

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

  gh release create "$tag" "${wheels[@]}" --repo "$REPO" --title "$pkg v$version" --notes "Platform wheels for $pkg $version" 2>/dev/null ||
    gh release upload "$tag" "${wheels[@]}" --repo "$REPO" --clobber
done
shopt -u nullglob

TOKEN="$(gh auth token 2>/dev/null)" || { echo "set GH_TOKEN to publish shim branch" >&2; exit 1; }

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
shim_setup = pathlib.Path("_shim_setup.py")

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

  # copy all .py files from the main module
  src_mod = pathlib.Path(pkg) / module
  for py_file in src_mod.glob("*.py"):
    shutil.copy2(py_file, mod_dir / py_file.name)

  # copy extra packages (e.g. pyray for raylib)
  include_patterns = data.get("tool", {}).get("setuptools", {}).get("packages", {}).get("find", {}).get("include", [])
  extra_packages = []
  for pattern in include_patterns:
    p = pattern.rstrip("*")
    if p and p != module and p != f"{module}/":
      src_extra = pathlib.Path(pkg) / p
      if src_extra.is_dir():
        dst_extra = pkg_dir / p
        shutil.copytree(src_extra, dst_extra, dirs_exist_ok=True)
        extra_packages.append(pattern)

  shutil.copy2(shim_setup, pkg_dir / "setup.py")

  deps = data.get("project", {}).get("dependencies", [])

  lines = [
    "[build-system]",
    'requires = ["setuptools>=64", "wheel", \'tomli; python_version < \"3.11\"\']',
    'build-backend = "setuptools.build_meta"',
    "",
    "[project]",
    f'name = "{pkg}"',
    f'version = "{version}"',
    f"description = {json.dumps(description + ' (pre-built)')}",
    'requires-python = ">=3.8"',
  ]

  if deps:
    lines.append(f"dependencies = {json.dumps(deps)}")

  if scripts:
    lines += ["", "[project.scripts]"]
    for name, target in scripts.items():
      lines.append(f'"{name}" = {json.dumps(target)}')

  find_include = [f"{module}*"] + extra_packages
  lines += [
    "",
    "[tool.setuptools.packages.find]",
    f"include = {json.dumps(find_include)}",
    "",
    "[tool.setuptools.package-data]",
    f'{module} = ["{datadir}/**/*", "*.so"]',
    "",
    "[tool.shim]",
    f'repo_url = "{repo_url}"',
    f'tag = "{tag}"',
    f'datadir = "{datadir}"',
  ]

  (pkg_dir / "pyproject.toml").write_text("\n".join(lines) + "\n")
PY

(
  cd "$TMP_DIR"
  git init
  git checkout -b releases
  git add .
  git -c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com" commit -m "update shim packages"
  git remote add origin "https://x-access-token:${TOKEN}@github.com/${REPO}.git"
  git push -f origin releases
)

rm -rf "$TMP_DIR"
