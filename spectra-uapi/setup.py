import subprocess
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py


class BuildHeaders(build_py):
  def run(self):
    subprocess.check_call(["bash", "build.sh"], cwd=Path(__file__).parent)
    super().run()


setup(cmdclass={"build_py": BuildHeaders})
