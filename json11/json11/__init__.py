import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libjson11.a")), "libjson11.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "json11", "json11.hpp")), "json11/json11.hpp not found"
