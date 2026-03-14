import os

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(BIN_DIR, "moc")), "moc not found"
  assert os.path.isfile(os.path.join(BIN_DIR, "rcc")), "rcc not found"
  import glob
  import platform
  if platform.system() == "Darwin":
    assert os.path.isdir(os.path.join(LIB_DIR, "QtCore.framework")), "QtCore.framework not found"
    assert os.path.isdir(os.path.join(LIB_DIR, "QtCharts.framework")), "QtCharts.framework not found"
  else:
    assert glob.glob(os.path.join(LIB_DIR, "libQt5Core.so*")), "libQt5Core.so not found"
    assert glob.glob(os.path.join(LIB_DIR, "libQt5Charts.so*")), "libQt5Charts.so not found"
