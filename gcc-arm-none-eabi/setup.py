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
    source_dir = os.environ.get("DEPS_SOURCE_DIR", pkg_dir)
    build_script = os.path.join(source_dir, "build.sh")
    subprocess.check_call(["bash", build_script], cwd=source_dir)

    # pip copies source to a temp dir for PEP 517 builds, excluding
    # gitignored build products. Symlink them from the real source dir.
    if os.path.realpath(source_dir) != os.path.realpath(pkg_dir):
      module = os.path.basename(source_dir).replace("-", "_")
      src_mod = os.path.join(source_dir, module)
      dst_mod = os.path.join(pkg_dir, module)
      for name in os.listdir(src_mod):
        s = os.path.join(src_mod, name)
        d = os.path.join(dst_mod, name)
        if os.path.isdir(s) and not os.path.exists(d):
          os.symlink(s, d)

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
