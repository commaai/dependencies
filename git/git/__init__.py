import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")


def _run():
  binary = os.path.join(BIN_DIR, "git")
  os.execvp(binary, [binary] + sys.argv[1:])


def smoketest():
  import subprocess
  binary = os.path.join(BIN_DIR, "git")
  subprocess.run([binary, "--version"], check=True)
  subprocess.run([binary, "ls-remote", "https://github.com/commaai/openpilot.git", "HEAD"], check=True)
