"""Shim setup.py: downloads pre-built wheels from GitHub Releases at install time."""
import os
import platform
import zipfile
from io import BytesIO
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

      whl_name = f"{MODULE}-{VERSION}-py3-none-{plat}.whl"
      url = f"{REPO_URL}/releases/download/{TAG}/{whl_name}"

      print(f"Downloading {url} ...")
      raw = urlopen(url).read()

      print(f"Extracting {DATADIR} ...")
      with zipfile.ZipFile(BytesIO(raw)) as zf:
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

        # Also extract compiled extension modules (.so)
        ext_prefix = f"{MODULE}/"
        ext_alt_prefix = f"{MODULE}-{VERSION}.data/purelib/{MODULE}/"
        for info in zf.infolist():
          if not info.filename.endswith('.so'):
            continue
          for p in (ext_prefix, ext_alt_prefix):
            if info.filename.startswith(p):
              rel = info.filename[len(p):]
              if rel and '/' not in rel:
                dest = os.path.join(module_dir, rel)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                  f.write(zf.read(info))
                if info.external_attr >> 16 & 0o111:
                  os.chmod(dest, 0o755)
              break

    super().run()


setup(cmdclass={"build_py": InstallPrebuilt})
