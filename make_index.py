#!/usr/bin/env python3
"""Generate a static PEP 503 "simple" index from this repo's GitHub Releases.

The index pages link directly to the wheel assets on GitHub Releases, so the
index itself is just HTML. Served via GitHub Pages (gh-pages branch):
  https://commaai.github.io/dependencies/simple/
"""
import hashlib
import json
import os
import re
import sys
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "commaai/dependencies")
API = f"https://api.github.com/repos/{REPO}/releases"


def _get(url):
  req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
  token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
  if token:
    req.add_header("Authorization", f"Bearer {token}")
  return urllib.request.urlopen(req, timeout=60)


def get_releases():
  releases = []
  page = 1
  while True:
    with _get(f"{API}?per_page=100&page={page}") as resp:
      batch = json.load(resp)
    releases += batch
    if len(batch) < 100:
      return releases
    page += 1


def normalize(name):
  # PEP 503 name normalization
  return re.sub(r"[-_.]+", "-", name).lower()


def sha256_of(asset):
  digest = asset.get("digest")
  if digest and digest.startswith("sha256:"):
    return digest.removeprefix("sha256:")
  print(f"  no digest for {asset['name']}, downloading to hash ...")
  with _get(asset["browser_download_url"]) as resp:
    return hashlib.sha256(resp.read()).hexdigest()


def main(out_dir):
  # project name -> list of (filename, url, sha256), from release tags like "capnproto/v1.0.1"
  projects = {}
  for release in get_releases():
    name = normalize(release["tag_name"].split("/")[0])
    for asset in release["assets"]:
      if not asset["name"].endswith(".whl"):
        continue
      projects.setdefault(name, []).append((asset["name"], asset["browser_download_url"], sha256_of(asset)))

  os.makedirs(os.path.join(out_dir, "simple"), exist_ok=True)
  root = ["<!DOCTYPE html>", "<html><body>"]
  for name in sorted(projects):
    root.append(f'<a href="{name}/">{name}</a><br>')
    page = ["<!DOCTYPE html>", "<html><body>", f"<h1>{name}</h1>"]
    for filename, url, sha in sorted(projects[name]):
      page.append(f'<a href="{url}#sha256={sha}">{filename}</a><br>')
    page += ["</body></html>", ""]
    os.makedirs(os.path.join(out_dir, "simple", name), exist_ok=True)
    with open(os.path.join(out_dir, "simple", name, "index.html"), "w") as f:
      f.write("\n".join(page))
  root += ["</body></html>", ""]
  with open(os.path.join(out_dir, "simple", "index.html"), "w") as f:
    f.write("\n".join(root))

  # tell GitHub Pages not to run Jekyll
  open(os.path.join(out_dir, ".nojekyll"), "w").close()
  with open(os.path.join(out_dir, "index.html"), "w") as f:
    f.write(f'<!DOCTYPE html>\n<html><body><h1>{REPO}</h1>PEP 503 index: <a href="simple/">simple/</a></body></html>\n')

  n = sum(len(v) for v in projects.values())
  print(f"wrote index for {len(projects)} projects ({n} wheels) to {out_dir}/simple")


if __name__ == "__main__":
  main(sys.argv[1] if len(sys.argv) > 1 else "pages")
