import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = DIR  # header-only; no libraries


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "nanosvg.h")), "nanosvg.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "nanosvgrast.h")), "nanosvgrast.h not found"
