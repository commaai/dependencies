import glob
import importlib.util
import os
import sys

_DIR = os.path.join(os.path.dirname(__file__), "install")
_UPSTREAM_DIR = os.path.join(_DIR, "raylib")


def smoketest():
    assert os.path.isdir(_UPSTREAM_DIR), "raylib/ not found in install"
    assert os.path.isdir(os.path.join(_DIR, "pyray")), "pyray/ not found in install"
    so_files = glob.glob(os.path.join(_DIR, "_raylib_cffi*.so"))
    assert so_files, "_raylib_cffi*.so not found in install"


# Make install/ available for pyray and other bundled modules
if _DIR not in sys.path:
    sys.path.insert(0, _DIR)

# Replace this wrapper in sys.modules with the upstream raylib C bindings so
# that `import raylib` exposes the actual raylib API rather than this shim.
_spec = importlib.util.spec_from_file_location(
    "raylib",
    os.path.join(_UPSTREAM_DIR, "__init__.py"),
    submodule_search_locations=[_UPSTREAM_DIR],
)
_mod = importlib.util.module_from_spec(_spec)
_mod.smoketest = smoketest
sys.modules["raylib"] = _mod
_spec.loader.exec_module(_mod)
