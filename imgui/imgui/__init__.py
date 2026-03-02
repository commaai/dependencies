import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
SRC_DIR = os.path.join(DIR, "src")


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "imgui.h")), "imgui.h not found"
  assert os.path.isfile(os.path.join(SRC_DIR, "imgui.cpp")), "imgui.cpp not found"
