#!/usr/bin/env python3
import os
import re
import shutil
import sys

BACKUP_SUFFIX = ".build-version.bak"
VERSION_RE = re.compile(r'^(?P<prefix>\s*version\s*=\s*")(?P<version>[^"]+)(?P<suffix>".*)$')


def post_version(version: str, post_n: str) -> str:
  base = re.sub(r"\.post\d+$", "", version)
  if not re.fullmatch(r"\d+(?:\.\d+)*(?:(?:a|b|rc)\d+)?", base):
    raise ValueError(f"unsupported version: {version}")
  return f"{base}.post{post_n}"


def apply(post_n: str, paths: list[str]) -> None:
  if not post_n.isdigit():
    raise ValueError("post number must be a non-negative integer")

  for path in paths:
    shutil.copy2(path, path + BACKUP_SUFFIX)
    lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
    in_project = changed = False

    for i, line in enumerate(lines):
      stripped = line.strip()
      if stripped.startswith("[") and stripped.endswith("]"):
        in_project = stripped == "[project]"
      if in_project and (match := VERSION_RE.match(line)):
        lines[i] = f"{match['prefix']}{post_version(match['version'], post_n)}{match['suffix']}\n"
        changed = True

    if not changed:
      raise RuntimeError(f"no [project] version found in {path}")

    open(path, "w", encoding="utf-8").writelines(lines)


def restore(paths: list[str]) -> None:
  for path in paths:
    backup = path + BACKUP_SUFFIX
    if os.path.exists(backup):
      os.replace(backup, path)


if __name__ == "__main__":
  if len(sys.argv) < 3 or sys.argv[1] not in {"apply", "restore"}:
    raise SystemExit("usage: build_versions.py apply POST_N FILE... | restore FILE...")
  if sys.argv[1] == "apply":
    apply(sys.argv[2], sys.argv[3:])
  else:
    restore(sys.argv[2:])
