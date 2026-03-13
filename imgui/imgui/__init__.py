import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
SRC_DIR = os.path.join(DIR, "src")
LIB_DIR = os.path.join(DIR, "lib")


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "imgui.h")), "imgui.h not found"
  assert os.path.isfile(os.path.join(SRC_DIR, "imgui.cpp")), "imgui.cpp not found"
  assert os.path.isfile(os.path.join(LIB_DIR, "libglfw3.a")), "libglfw3.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "GLFW", "glfw3.h")), "GLFW/glfw3.h not found"
