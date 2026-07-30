import glob
import os
import platform
import shutil
import subprocess
import sys

from setuptools import Distribution, setup
from setuptools.command.build_py import build_py
from setuptools.command.bdist_wheel import bdist_wheel

PKG_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(PKG_DIR, "raylib"))
from _backend import BACKEND_CFFI_MODULES, detect_backend, host_backends  # noqa: E402


class BuildRaylib(build_py):
  """Run build.sh to compile raylib artifacts before collecting package data."""

  @staticmethod
  def _build_cffi(backend):
    env = os.environ.copy()
    env["RAYLIB_BACKEND"] = backend
    env["RAYLIB_CFFI_MODULE"] = f"raylib.{BACKEND_CFFI_MODULES[backend]}"
    subprocess.check_call([sys.executable, "build_cffi.py"], cwd=PKG_DIR, env=env)

  def run(self):
    subprocess.check_call(["bash", "build.sh"], cwd=PKG_DIR)

    # Always regenerate CFFI extensions: the cached raylib source pin may have changed.
    for old_cffi in glob.glob(os.path.join(PKG_DIR, "raylib", "_raylib_cffi*")):
      os.remove(old_cffi)
    # explicit RAYLIB_BACKEND builds only that backend (matches build.sh)
    backends = (detect_backend(),) if os.environ.get("RAYLIB_BACKEND") else host_backends()
    for backend in backends:
      self._build_cffi(backend)

    # Wipe build_lib package dirs so deleted/renamed files (e.g. old _raylib_cffi*
    # backends, removed modules) don't get packaged from the cached build/ tree.
    for package in ("raylib", "pyray"):
      shutil.rmtree(os.path.join(self.build_lib, package), ignore_errors=True)

    super().run()


class PlatformWheel(bdist_wheel):
  """Produce a platform-specific wheel with native raylib artifacts."""

  def finalize_options(self):
    super().finalize_options()
    self.root_is_pure = False

  def get_tag(self):
    _, _, plat_tag = super().get_tag()
    if platform.system() == "Linux":
      # manylinux images set AUDITWHEEL_PLAT (e.g. manylinux_2_28_x86_64);
      # PyPI rejects bare linux_* tags, so use it when building in one.
      plat_tag = os.environ.get("AUDITWHEEL_PLAT", f"linux_{platform.machine()}")
    elif platform.system() == "Darwin":
      plat_tag = "macosx_11_0_arm64"
    return "py3", "none", plat_tag


class BinaryDistribution(Distribution):
  def has_ext_modules(self):
    return True


setup(
  cmdclass={"build_py": BuildRaylib, "bdist_wheel": PlatformWheel},
  distclass=BinaryDistribution,
)
