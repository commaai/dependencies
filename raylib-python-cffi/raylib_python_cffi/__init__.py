import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")

# Expose bundled raylib and pyray modules
if DIR not in sys.path:
    sys.path.insert(0, DIR)


def smoketest():
    import raylib
    import pyray
    assert hasattr(raylib, 'InitWindow'), "raylib.InitWindow not found"
    assert hasattr(pyray, 'init_window'), "pyray.init_window not found"
