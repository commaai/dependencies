import glob
import importlib.util
import os
import platform
import shutil
import subprocess
import sys

from setuptools import setup
from setuptools.command.build_py import build_py

try:
  from wheel.bdist_wheel import bdist_wheel
except ImportError:
  bdist_wheel = None


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
  def _build_cffi(pkg_dir, backend_config, backend=None):
    build_cffi = os.path.join(pkg_dir, "raylib", "build.py")
    if not os.path.isfile(build_cffi):
      return

    env = os.environ.copy()
    if backend is not None:
      env["RAYLIB_BACKEND"] = backend
      env["RAYLIB_CFFI_MODULE"] = backend_config.qualified_cffi_module_for_backend(backend)
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
    for modified_header in glob.glob(os.path.join(pkg_dir, "raylib", "*.modified")):
      os.remove(modified_header)
    if self._is_linux_aarch64():
      for backend in backend_config.BACKENDS:
        self._build_cffi(pkg_dir, backend_config, backend)
    else:
      self._build_cffi(pkg_dir, backend_config)

    staged_pkg = os.path.join(self.build_lib, "raylib")
    shutil.rmtree(os.path.join(staged_pkg, "install"), ignore_errors=True)
    for old_cffi in glob.glob(os.path.join(staged_pkg, "_raylib_cffi*")):
      os.remove(old_cffi)

    super().run()


cmdclass = {"build_py": BuildRaylib}

if bdist_wheel is not None:

  class PlatformWheel(bdist_wheel):
    """Produce a platform-specific wheel (contains native .a library)."""

    def finalize_options(self):
      super().finalize_options()
      self.root_is_pure = False

    def get_tag(self):
      system = platform.system()
      machine = platform.machine()

      if system == "Linux":
        plat = f"linux_{machine}"
      elif system == "Darwin":
        plat = "macosx_11_0_arm64"
      else:
        plat = f"{system.lower()}_{machine}"

      return "py3", "none", plat

  cmdclass["bdist_wheel"] = PlatformWheel


setup(cmdclass=cmdclass)
