import os
import subprocess

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")
PLUGINS_DIR = os.path.join(DIR, "plugins")
MKSPECS_DIR = os.path.join(DIR, "mkspecs")


def smoketest():
  # Check qmake runs
  qmake = os.path.join(BIN_DIR, "qmake")
  assert os.path.isfile(qmake), f"qmake not found at {qmake}"
  result = subprocess.run([qmake, "-version"], capture_output=True, text=True)
  assert result.returncode == 0, f"qmake -version failed: {result.stderr}"

  # Check shared libs exist for each module
  for mod in ("Qt5Core", "Qt5Gui", "Qt5Widgets", "Qt5OpenGL", "Qt5Charts"):
    found = any(
      f.startswith(f"lib{mod}.so") or f.startswith(f"lib{mod}.") and f.endswith(".dylib")
      for f in os.listdir(LIB_DIR)
    )
    assert found, f"shared library for {mod} not found in {LIB_DIR}"

  # Check headers exist for each module
  for mod in ("QtCore", "QtGui", "QtWidgets", "QtOpenGL", "QtCharts"):
    header_dir = os.path.join(INCLUDE_DIR, mod)
    assert os.path.isdir(header_dir), f"headers not found at {header_dir}"
