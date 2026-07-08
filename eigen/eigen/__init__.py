import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = DIR
LIB_DIR = DIR  # header-only; no libraries


def smoketest():
  assert os.path.isdir(os.path.join(DIR, "eigen3", "Eigen")), "Eigen headers not found"
