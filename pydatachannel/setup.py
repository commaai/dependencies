import os
import platform
import shutil
import subprocess
import sys

from setuptools import Distribution, setup
from setuptools.command.bdist_wheel import bdist_wheel
from setuptools.command.build_py import build_py

PKG_DIR = os.path.dirname(os.path.abspath(__file__))


class BuildPydatachannel(build_py):
  """Run build.sh to compile the extension, then run the tests against the built package."""

  def run(self):
    subprocess.check_call(["bash", "build.sh"], cwd=PKG_DIR, env=dict(os.environ, PYTHON=sys.executable))

    # Wipe the cached build_lib package so a stale _rtc*.so doesn't get packaged.
    shutil.rmtree(os.path.join(self.build_lib, "pydatachannel"), ignore_errors=True)
    super().run()

    # cwd=build_lib so `import pydatachannel` resolves to the built package
    subprocess.check_call([sys.executable, "-m", "pytest", os.path.join(PKG_DIR, "tests"), "-n", "auto", "-p", "no:cacheprovider"],
                          cwd=os.path.abspath(self.build_lib), env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))


class BinaryDistribution(Distribution):
  """The extension is built by build.sh, not setuptools: still install it to platlib."""

  def has_ext_modules(self):
    return True


class PlatformWheel(bdist_wheel):
  """Produce one cp312-abi3 wheel per platform."""

  def get_tag(self):
    _, _, plat_tag = super().get_tag()
    if platform.system() == "Linux":
      # manylinux images set AUDITWHEEL_PLAT (e.g. manylinux_2_28_x86_64);
      # PyPI rejects bare linux_* tags, so use it when building in one.
      plat_tag = os.environ.get("AUDITWHEEL_PLAT", f"linux_{platform.machine()}")
    elif platform.system() == "Darwin":
      plat_tag = "macosx_14_0_arm64"  # matches MACOSX_DEPLOYMENT_TARGET in build.sh
    return "cp312", "abi3", plat_tag


setup(distclass=BinaryDistribution, cmdclass={"build_py": BuildPydatachannel, "bdist_wheel": PlatformWheel})
