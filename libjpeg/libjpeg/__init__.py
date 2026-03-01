import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libjpeg.a")), "libjpeg.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "jpeglib.h")), "jpeglib.h not found"
