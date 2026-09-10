import os
import subprocess
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")
EXE = ".exe" if os.name == "nt" else ""


def _run():
  binary = os.path.join(DIR, "cppcheck" + EXE)
  sys.exit(subprocess.call(["cppcheck"] + sys.argv[1:], executable=binary))


def smoketest():
  binary = os.path.join(DIR, "cppcheck" + EXE)
  result = subprocess.run([binary, "--version"], capture_output=True, text=True, check=True)
  print(result.stdout.strip())
