import os
import subprocess
import sys

BIN_DIR = os.path.join(os.path.dirname(__file__), "bin")
EXE = ".exe" if os.name == "nt" else ""


def _run():
  binary = os.path.join(BIN_DIR, "git-lfs" + EXE)
  sys.exit(subprocess.call([binary] + sys.argv[1:]))


def smoketest():
  binary = os.path.join(BIN_DIR, "git-lfs" + EXE)
  subprocess.run([binary, "--version"], check=True)
