import os
import platform as _platform

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = os.path.join(DIR, "lib")
MESA_DIR = os.path.join(DIR, "lib", "mesa")


def smoketest():
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "imgui.h")), "imgui.h not found"
  assert os.path.isfile(os.path.join(LIB_DIR, "libimgui.a")), "libimgui.a not found"
  assert os.path.isfile(os.path.join(LIB_DIR, "libglfw3.a")), "libglfw3.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "GLFW", "glfw3.h")), "GLFW/glfw3.h not found"
  if _platform.system() == "Linux":
    assert os.path.isfile(os.path.join(MESA_DIR, "libGL.so.1")), "libGL.so.1 not found"
