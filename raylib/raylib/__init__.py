import importlib
import os
import subprocess
import sys

from ._backend import BACKEND_ARCHIVES, BACKEND_CFFI_MODULES, HEADLESS, detect_backend, host_backends
from .version import __version__

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = os.path.join(DIR, "lib")

_BACKEND = detect_backend()


def _expected_archives():
  # explicit RAYLIB_BACKEND also selects a single-backend build (see setup.py)
  if os.environ.get("RAYLIB_BACKEND"):
    return (BACKEND_ARCHIVES[_BACKEND],)
  return tuple(BACKEND_ARCHIVES[b] for b in host_backends())


def smoketest():
  subprocess.check_call([sys.executable, "-c", """
import raylib_nb as rl
assert rl.check_collision_point_rec(rl.Vector2(1, 1), rl.Rectangle(0, 0, 2, 2))
import os
if os.environ["RAYLIB_BACKEND"] == "headless":
  rl.init_window(64, 64, "nanobind smoketest")
  rl.begin_drawing()
  rl.clear_background(rl.BLACK)
  rl.end_drawing()
  rl.close_window()
"""], env=dict(os.environ, RAYLIB_BACKEND=_BACKEND))
  assert ffi is not None
  assert rl is not None
  for header in ("raylib.h", "raymath.h", "rlgl.h"):
    assert os.path.isfile(os.path.join(INCLUDE_DIR, header)), f"{header} not found"
  for archive in _expected_archives():
    assert os.path.isfile(os.path.join(LIB_DIR, archive)), f"{archive} not found"
  if _BACKEND == HEADLESS:
    rl.InitWindow(64, 64, b"")
    rl.BeginDrawing()
    rl.ClearBackground((0, 0, 0, 255))
    rl.EndDrawing()
    rl.CloseWindow()


def _load_cffi():
  backend_module = BACKEND_CFFI_MODULES[_BACKEND]
  try:
    return importlib.import_module(f".{backend_module}", __name__)
  except (ImportError, OSError) as e:
    raise ImportError(f"failed to load raylib {_BACKEND} backend extension {backend_module}") from e


_cffi = _load_cffi()
ffi, rl = _cffi.ffi, _cffi.lib
# Module name is dynamic per backend, so we can't use `from ._raylib_cffi_X.lib import *`.
for _name in dir(rl):
  if not _name.startswith("_"):
    globals()[_name] = getattr(rl, _name)
del _name
from raylib.colors import *  # noqa: F403, E402
from raylib.defines import *  # noqa: F403, E402
