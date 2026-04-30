"""Shim setup.py: downloads pre-built wheels from GitHub Releases at install time."""
import os
import platform
import time
import zipfile
from io import BytesIO
from urllib.error import URLError
from urllib.request import urlopen

try:
  import tomllib
except ImportError:
  import tomli as tomllib

from setuptools import setup
from setuptools.command.build_py import build_py

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "pyproject.toml"), "rb") as _f:
  _cfg = tomllib.load(_f)

REPO_URL = _cfg["tool"]["shim"]["repo_url"]
TAG = _cfg["tool"]["shim"]["tag"]
DATADIR = _cfg["tool"]["shim"]["datadir"]
VERSION = _cfg["project"]["version"]
MODULE = _cfg["project"]["name"].replace("-", "_")

# all top-level packages bundled in this wheel (e.g. acados + casadi).
# `packages` may be a flat list or a dict with find.include patterns.
_pkgs = _cfg.get("tool", {}).get("setuptools", {}).get("packages", [f"{MODULE}*"])
if isinstance(_pkgs, list):
  _INCLUDE = _pkgs
elif isinstance(_pkgs, dict):
  _INCLUDE = _pkgs.get("find", {}).get("include", [f"{MODULE}*"])
else:
  _INCLUDE = [f"{MODULE}*"]
TOP_PACKAGES = sorted({p.rstrip("*").rstrip("/") for p in _INCLUDE if p.rstrip("*").rstrip("/")})

PLATFORM_MAP = {
  ("Linux", "x86_64"): "linux_x86_64",
  ("Linux", "aarch64"): "linux_aarch64",
  ("Darwin", "arm64"): "macosx_11_0_arm64",
}


class InstallPrebuilt(build_py):
  def run(self):
    module_dir = os.path.join(_HERE, MODULE)
    data_dir = os.path.join(module_dir, DATADIR)

    if not os.path.exists(os.path.join(data_dir, "bin")):
      key = (platform.system(), platform.machine())
      plat = PLATFORM_MAP.get(key)
      if plat is None:
        raise RuntimeError(f"unsupported platform: {key}")

      whl_names = [
        f"{MODULE}-{VERSION}-py3-none-{plat}.whl",
        f"{MODULE}-{VERSION}-py3-none-any.whl",
      ]

      raw = None
      for whl_name in whl_names:
        url = f"{REPO_URL}/releases/download/{TAG}/{whl_name}"
        print(f"Downloading {url} ...")
        for attempt in range(3):
          try:
            raw = urlopen(url, timeout=60).read()
            break
          except (URLError, OSError) as e:
            if attempt == 2:
              if whl_name == whl_names[-1]:
                raise
              break
            wait = 2 ** attempt
            print(f"Download failed ({e}), retrying in {wait}s ...")
            time.sleep(wait)
        if raw is not None:
          break

      print("Extracting wheel ...")
      with zipfile.ZipFile(BytesIO(raw)) as zf:
        purelib_data = f"{MODULE}-{VERSION}.data/purelib/"
        for info in zf.infolist():
          if info.is_dir():
            continue
          name = info.filename
          if name.startswith(purelib_data):
            rel = name[len(purelib_data):]
          else:
            rel = name
          if "/" not in rel:
            continue
          top = rel.split("/", 1)[0]
          if top not in TOP_PACKAGES:
            continue
          dest = os.path.join(_HERE, rel)
          os.makedirs(os.path.dirname(dest), exist_ok=True)
          with open(dest, "wb") as f:
            f.write(zf.read(info))
          if info.external_attr >> 16 & 0o111:
            os.chmod(dest, 0o755)

    super().run()


setup(cmdclass={"build_py": InstallPrebuilt})
