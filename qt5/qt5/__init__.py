import os
import platform

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")
PLUGINS_DIR = os.path.join(DIR, "plugins")


def smoketest():
  ext = "dylib" if platform.system() == "Darwin" else "so"
  assert any(f.startswith("libQt5Core.") and f.endswith(ext)
             for f in os.listdir(LIB_DIR)), "libQt5Core not found"
  assert os.path.isdir(os.path.join(INCLUDE_DIR, "QtCore")), "QtCore headers not found"
  assert os.path.isfile(os.path.join(BIN_DIR, "moc")), "moc not found"
