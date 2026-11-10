#!/usr/bin/env python3
"""Per-package cache of native build outputs, used by CI.

Most changes touch one package, but every CI run used to rebuild all of them.
Each package gets a key hashing its own files, the root build scripts and the
builder environment. `restore` unpacks outputs whose key still matches and
prints those packages; their setup.py then skips build.sh via
DEPENDENCIES_PREBUILT. `save` archives outputs whose key changed and creates
CACHE_DIR/.changed so CI knows to upload a new cache.

Normal source builds (pip install git+...) never touch this.
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

# bump to invalidate every cached package
VERSION = 1

ROOT = Path(__file__).resolve().parent
COMMON_INPUTS = ["build.sh", "setup.sh", "build_native_cache.py"]


def run(*args):
  try:
    return subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
  except FileNotFoundError:
    return ""


def builder_identity():
  info = [VERSION, platform.system(), platform.machine(), sys.version, os.environ.get("DEPENDENCIES_BUILDER_ID", ""),
          run("cc", "--version"), run("c++", "--version"), run("cmake", "--version")]
  # on Linux the pinned manylinux image (DEPENDENCIES_BUILDER_ID) plus setup.sh
  # pin the toolchain; restore runs before setup.sh's dnf install, so don't look at rpms
  if platform.system() == "Darwin":
    info += [run("sw_vers", "-productVersion"), run("xcrun", "--show-sdk-version"),
             run("brew", "list", "--versions", "nasm", "pkg-config", "ccache", "autoconf", "automake", "libtool")]
  return json.dumps(info)


def packages():
  return sorted(p.parent.name for p in ROOT.glob("*/pyproject.toml"))


def outputs(pkg):
  module = pkg.replace("-", "_")
  paths = [f"{pkg}/{module}/toolchain" if pkg == "gcc-arm-none-eabi" else f"{pkg}/{module}/install"]
  if pkg == "acados":
    paths += ["acados/casadi", "acados/acados/acados_template"]
  elif pkg == "raylib":
    paths += [str(p.relative_to(ROOT)) for p in sorted((ROOT / "raylib/raylib").glob("_raylib_cffi*.so"))]
    paths += ["raylib/raylib_nb"]
  return paths


def keys():
  builder = builder_identity()
  result = {}
  for pkg in packages():
    h = hashlib.sha256(builder.encode())
    if pkg == "acados" and platform.machine() == "x86_64":
      # BLASFEO's X64_AUTOMATIC target is picked from the build machine's CPU
      h.update(run("grep", "-m1", "^flags", "/proc/cpuinfo").encode())
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", pkg],
                                    cwd=ROOT, text=True).splitlines()
    for name in sorted(set(files + COMMON_INPUTS)):
      path = ROOT / name
      h.update(name.encode() + b"\0" + (path.read_bytes() if path.is_file() else b"<missing>") + b"\0")
    result[pkg] = h.hexdigest()
  return result


def remove(path):
  if path.is_dir() and not path.is_symlink():
    shutil.rmtree(path)
  elif path.exists() or path.is_symlink():
    path.unlink()


def restore(cache):
  cache.mkdir(parents=True, exist_ok=True)
  remove(cache / ".changed")
  current = keys()
  (cache / "keys.json").write_text(json.dumps(current, indent=2))
  hits = []
  for pkg, key in current.items():
    start = time.monotonic()
    archive, stamp = cache / f"{pkg}.tar", cache / f"{pkg}.key"
    hit = archive.is_file() and stamp.is_file() and stamp.read_text() == key
    if hit:
      for out in outputs(pkg):
        remove(ROOT / out)
      with tarfile.open(archive) as tar:
        if hasattr(tarfile, "data_filter"):
          tar.extractall(ROOT, filter="data")
        else:
          tar.extractall(ROOT)
      hits.append(pkg)
    print(f"native cache: {pkg} {'HIT' if hit else 'MISS'} ({time.monotonic() - start:.2f}s)", file=sys.stderr)
  print(",".join(hits))


def save(cache):
  current = json.loads((cache / "keys.json").read_text())
  for pkg, key in current.items():
    stamp = cache / f"{pkg}.key"
    if stamp.is_file() and stamp.read_text() == key:
      continue
    tmp = cache / f"{pkg}.tar.tmp"
    with tarfile.open(tmp, "w") as tar:
      for out in outputs(pkg):
        if not (ROOT / out).exists():
          raise RuntimeError(f"{pkg}: missing build output {out}")
        tar.add(ROOT / out, arcname=out)
    tmp.replace(cache / f"{pkg}.tar")
    stamp.write_text(key)
    (cache / ".changed").touch()
    print(f"native cache: saved {pkg}", file=sys.stderr)
  # drop packages that no longer exist
  for stale in cache.glob("*.key"):
    if stale.stem not in current:
      remove(stale)
      remove(cache / f"{stale.stem}.tar")
      (cache / ".changed").touch()


if __name__ == "__main__":
  if len(sys.argv) != 3 or sys.argv[1] not in ("restore", "save"):
    raise SystemExit("usage: build_native_cache.py restore|save CACHE_DIR")
  cache_dir = Path(sys.argv[2])
  if not cache_dir.is_absolute():
    cache_dir = ROOT / cache_dir
  {"restore": restore, "save": save}[sys.argv[1]](cache_dir)
