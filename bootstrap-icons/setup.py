import os
import subprocess

from setuptools.command.build_py import build_py


class BuildBootstrapIcons(build_py):
  """Run build.sh to fetch Bootstrap Icons before collecting package data."""

  def run(self):
    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    build_script = os.path.join(pkg_dir, "build.sh")
    subprocess.check_call(["bash", build_script], cwd=pkg_dir)

    super().run()


def setup():
  from setuptools import setup as _setup

  _setup(cmdclass={"build_py": BuildBootstrapIcons})


if __name__ == "__main__":
  setup()
