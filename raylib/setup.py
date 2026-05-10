import glob
import importlib.util
import os
import platform
import shutil
import subprocess
import sys

from setuptools import setup
from setuptools.command.build_py import build_py
from setuptools.command.bdist_wheel import bdist_wheel


class BuildRaylib(build_py):
  """Run build.sh to compile the C library and CFFI extension before collecting package data."""

  @staticmethod
  def _backend_config(pkg_dir):
    backend_config = os.path.join(pkg_dir, "raylib", "_backend.py")
    spec = importlib.util.spec_from_file_location("_raylib_backend_config", backend_config)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

  @staticmethod
  def _is_linux_aarch64():
    return platform.system() == "Linux" and platform.machine() in ("aarch64", "arm64")

  @staticmethod
  def _build_cffi(pkg_dir, backend_config, backend):
    build_cffi = os.path.join(pkg_dir, "build_cffi.py")
    if not os.path.isfile(build_cffi):
      return

    env = os.environ.copy()
    env["RAYLIB_BACKEND"] = backend
    env["RAYLIB_CFFI_MODULE"] = f"raylib.{backend_config.BACKEND_CFFI_MODULES[backend]}"
    subprocess.check_call([sys.executable, build_cffi], cwd=pkg_dir, env=env)

  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    backend_config = self._backend_config(pkg_dir)
    build_script = os.path.join(pkg_dir, "build.sh")
    subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    # Build CFFI extension so it's included in the wheel. Always regenerate it
    # after build.sh because the cached raylib source pin may have changed.
    for old_cffi in glob.glob(os.path.join(pkg_dir, "raylib", "_raylib_cffi*")):
      os.remove(old_cffi)
    if self._is_linux_aarch64():
      for backend in backend_config.BACKENDS:
        self._build_cffi(pkg_dir, backend_config, backend)
    else:
      self._build_cffi(pkg_dir, backend_config, backend_config.detect_backend())

    staged_pkg = os.path.join(self.build_lib, "raylib")
    shutil.rmtree(os.path.join(staged_pkg, "install"), ignore_errors=True)
    for old_cffi in glob.glob(os.path.join(staged_pkg, "_raylib_cffi*")):
      os.remove(old_cffi)

    super().run()


class PlatformWheel(bdist_wheel):
  """Produce a platform-specific wheel (contains native .a library)."""

  def finalize_options(self):
    super().finalize_options()
    self.root_is_pure = False

  def get_tag(self):
    _, _, plat_tag = super().get_tag()
    if platform.system() == "Linux":
      plat_tag = f"linux_{platform.machine()}"
    return "py3", "none", plat_tag


cmdclass = {"build_py": BuildRaylib, "bdist_wheel": PlatformWheel}


setup(cmdclass=cmdclass)
