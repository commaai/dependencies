import os
import platform
import sys
import subprocess

from setuptools.command.build_py import build_py

try:
  from wheel.bdist_wheel import bdist_wheel
except ImportError:
  bdist_wheel = None


class BuildRaylibPythonCffi(build_py):
  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    marker = os.path.join(pkg_dir, "raylib_python_cffi", "install", "raylib", "__init__.py")
    if not os.path.exists(marker):
      env = dict(os.environ)
      env["PYTHON_EXECUTABLE"] = sys.executable
      subprocess.check_call(["bash", os.path.join(pkg_dir, "build.sh")], cwd=pkg_dir, env=env)
    super().run()


cmdclass = {"build_py": BuildRaylibPythonCffi}

if bdist_wheel is not None:

  class PlatformWheel(bdist_wheel):
    def finalize_options(self):
      super().finalize_options()
      self.root_is_pure = False

    def get_tag(self):
      py = f"cp{sys.version_info.major}{sys.version_info.minor}"
      system = platform.system()
      machine = platform.machine()
      if system == "Linux":
        plat = f"linux_{machine}"
      elif system == "Darwin":
        plat = "macosx_11_0_arm64"
      else:
        plat = f"{system.lower()}_{machine}"
      return py, py, plat

  cmdclass["bdist_wheel"] = PlatformWheel


def setup():
  from setuptools import setup as _setup
  _setup(cmdclass=cmdclass)


if __name__ == "__main__":
  setup()
