import os
import sys

BIN_DIR = os.path.join(os.path.dirname(__file__), "bin")


def _run():
  binary = os.path.join(BIN_DIR, "git-lfs")
  os.execvp(binary, [binary] + sys.argv[1:])


def smoketest():
  import subprocess
  binary = os.path.join(BIN_DIR, "git-lfs")
  subprocess.run([binary, "--version"], check=True)
