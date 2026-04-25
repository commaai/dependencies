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
    raylib_pkg_dir = os.path.join(pkg_dir, "raylib")
    build_script = os.path.join(pkg_dir, "build.sh")
    subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    # Build CFFI extensions so they are included in the wheel, and make sure stale
    # local extensions from another raylib platform do not leak into the wheel.
    for path in glob.glob(os.path.join(raylib_pkg_dir, "_raylib_cffi*")):
      os.remove(path)

    build_cffi = os.path.join(raylib_pkg_dir, "build.py")
    if os.path.isfile(build_cffi):
      variants = [
        os.path.basename(path)
        for path in sorted(glob.glob(os.path.join(raylib_pkg_dir, "install", "lib", "*")))
        if os.path.isfile(os.path.join(path, "libraylib.a"))
      ]
      if not variants:
        variants = [""]

      platform_by_variant = {
        "comma": "PLATFORM_COMMA",
        "desktop": "PLATFORM_DESKTOP",
        "offscreen": "PLATFORM_OFFSCREEN",
        "": os.environ.get("RAYLIB_PLATFORM", ""),
      }
      for variant in variants:
        env = os.environ.copy()
        env["RAYLIB_VARIANT"] = variant
        env["RAYLIB_PLATFORM"] = platform_by_variant.get(variant, "PLATFORM_DESKTOP")
        env["RAYLIB_CFFI_MODULE"] = f"raylib._raylib_cffi_{variant}" if variant else "raylib._raylib_cffi"
        subprocess.check_call([sys.executable, build_cffi], cwd=pkg_dir, env=env)

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
