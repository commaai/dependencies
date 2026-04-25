import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = DIR  # header-only; no libraries


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "catch2", "catch.hpp")), "catch2/catch.hpp not found"
