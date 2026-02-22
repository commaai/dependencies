import os
import platform
import subprocess
import sys

from setuptools.command.build_py import build_py
from setuptools.dist import Distribution

try:
  from wheel.bdist_wheel import bdist_wheel
except ImportError:
  bdist_wheel = None


class BuildToolchain(build_py):
  """Run build.sh to download and prepare the toolchain before collecting package data."""

  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    toolchain_marker = os.path.join(
      pkg_dir, "gcc_arm_none_eabi", "toolchain", "bin", "arm-none-eabi-gcc"
    )

    if not os.path.exists(toolchain_marker):
      build_script = os.path.join(pkg_dir, "build.sh")
      subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    super().run()


cmdclass = {"build_py": BuildToolchain}

if bdist_wheel is not None:

  class PlatformWheel(bdist_wheel):
    """Produce a platform-specific, Python-version-agnostic wheel."""

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


def setup():
  from setuptools import setup as _setup

  _setup(cmdclass=cmdclass)


if __name__ == "__main__":
  setup()
