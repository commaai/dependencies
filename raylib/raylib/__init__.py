import importlib
import os

from ._backend import BACKEND_ARCHIVES, BACKEND_CFFI_MODULES, detect_backend, is_dual_backend_host
from .version import __version__

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = os.path.join(DIR, "lib")

_BACKEND = detect_backend()


def _expected_archives():
  if is_dual_backend_host():
    return BACKEND_ARCHIVES.values()
  return (BACKEND_ARCHIVES[_BACKEND],)


def smoketest():
  assert ffi is not None
  assert rl is not None
  for header in ("raylib.h", "raymath.h", "rlgl.h", "raygui.h"):
    assert os.path.isfile(os.path.join(INCLUDE_DIR, header)), f"{header} not found"
  for archive in _expected_archives():
    assert os.path.isfile(os.path.join(LIB_DIR, archive)), f"{archive} not found"


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
