import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "Python.h")), "Python.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "pyconfig.h")), "pyconfig.h not found"
