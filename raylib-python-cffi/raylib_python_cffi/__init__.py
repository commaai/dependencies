import glob
import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")

# Expose bundled raylib and pyray modules
if DIR not in sys.path:
    sys.path.insert(0, DIR)


def smoketest():
    assert os.path.isdir(os.path.join(DIR, "raylib")), "raylib/ not found in install"
    assert os.path.isdir(os.path.join(DIR, "pyray")), "pyray/ not found in install"
    so_files = glob.glob(os.path.join(DIR, "_raylib_cffi*.so"))
    assert so_files, "_raylib_cffi*.so not found in install"
