import importlib

from ._backend import BACKEND_CFFI_MODULES, detect_backend
from .version import __version__


def smoketest():
  assert ffi is not None
  assert rl is not None


def _load_cffi():
  backend = detect_backend()
  backend_module = BACKEND_CFFI_MODULES[backend]
  try:
    return importlib.import_module(f".{backend_module}", __name__)
  except (ImportError, OSError) as e:
    raise ImportError(f"failed to load raylib {backend} backend extension {backend_module}") from e


_cffi = _load_cffi()
ffi, rl = _cffi.ffi, _cffi.lib
for _name in dir(rl):
  if not _name.startswith("_"):
    globals()[_name] = getattr(rl, _name)
from raylib.colors import *  # noqa: F403
from raylib.defines import *  # noqa: F403
