import glob
import os
import platform
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
    marker = os.path.join(pkg_dir, "raylib", "install", "lib", "libraylib.a")

    if not os.path.exists(marker):
      build_script = os.path.join(pkg_dir, "build.sh")
      subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    # Build CFFI extension so it's included in the wheel
    cffi_so = glob.glob(os.path.join(pkg_dir, "raylib", "_raylib_cffi*"))
    if not cffi_so:
      build_cffi = os.path.join(pkg_dir, "raylib", "build.py")
      if os.path.isfile(build_cffi):
        subprocess.check_call([sys.executable, build_cffi], cwd=pkg_dir)

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
