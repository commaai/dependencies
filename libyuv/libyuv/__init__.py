import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libyuv.a")), "libyuv.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "libyuv.h")), "libyuv.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "libyuv", "version.h")), "libyuv/version.h not found"
