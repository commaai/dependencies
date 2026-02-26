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

echo
echo "Generating PEP 503 package index"

TOKEN="$(gh auth token 2>/dev/null)" || { echo "set GH_TOKEN to publish package index" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
python3 - "$TMP_DIR" "$REPO" <<'PY'
import pathlib
import re
import sys
import tomllib

tmp_dir = pathlib.Path(sys.argv[1])
repo = sys.argv[2]
repo_url = f"https://github.com/{repo}"

def normalize(name):
  return re.sub(r"[-_.]+", "-", name).lower()

simple = tmp_dir / "simple"
root_links = []

for toml in sorted(pathlib.Path(".").glob("*/pyproject.toml")):
  pkg = toml.parent.name
  module = pkg.replace("-", "_")
  data = tomllib.load(toml.open("rb"))
  version = data["project"]["version"]
  tag = f"{pkg}/v{version}"
  normalized = normalize(pkg)

  wheels = sorted(pathlib.Path("dist").glob(f"{module}-{version}-*.whl"))

  pkg_dir = simple / normalized
  pkg_dir.mkdir(parents=True, exist_ok=True)

  links = []
  for whl in wheels:
    url = f"{repo_url}/releases/download/{tag}/{whl.name}"
    links.append(f'<a href="{url}">{whl.name}</a>')

  (pkg_dir / "index.html").write_text(
    "<!DOCTYPE html>\n<html><body>\n" + "\n".join(links) + "\n</body></html>\n"
  )
  root_links.append(f'<a href="{normalized}/">{normalized}</a>')

(simple / "index.html").write_text(
  "<!DOCTYPE html>\n<html><body>\n" + "\n".join(root_links) + "\n</body></html>\n"
)
PY

(
  cd "$TMP_DIR"
  git init -q
  git checkout -b releases
  git add .
  git -c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com" commit -q -m "update package index"
  git remote add origin "https://x-access-token:${TOKEN}@github.com/${REPO}.git"
  git push -f origin releases
)

rm -rf "$TMP_DIR"
