import glob
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

  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    build_script = os.path.join(pkg_dir, "build.sh")
    subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    # Build CFFI extension so it's included in the wheel. Always regenerate it
    # after build.sh because the cached raylib source pin may have changed.
    for old_cffi in glob.glob(os.path.join(pkg_dir, "raylib", "_raylib_cffi*")):
      os.remove(old_cffi)
    for modified_header in glob.glob(os.path.join(pkg_dir, "raylib", "*.modified")):
      os.remove(modified_header)
    build_cffi = os.path.join(pkg_dir, "raylib", "build.py")
    if os.path.isfile(build_cffi):
      subprocess.check_call([sys.executable, build_cffi], cwd=pkg_dir)

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
