import importlib
import json
import os


def _setup_headless_gl():
  if os.environ.get("RAYLIB_BACKEND", "").lower() != "headless":
    return
  libs_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "comma_deps_raylib.libs")
  mesa_egl = os.path.join(libs_dir, "libEGL_mesa.so.0")
  if os.path.isdir(libs_dir) and os.path.isfile(mesa_egl):
    vendor_json = os.path.join(libs_dir, "egl_vendor.json")
    with open(vendor_json, "w") as f:
      json.dump({"file_format_version": "1.0.0", "ICD": {"library_path": "libEGL_mesa.so.0"}}, f)
    os.environ["__EGL_VENDOR_LIBRARY_FILENAMES"] = vendor_json
    os.environ.setdefault("LIBGL_DRIVERS_PATH", libs_dir)
    os.environ["GALLIUM_DRIVER"] = "llvmpipe"


_setup_headless_gl()

from ._backend import BACKEND_ARCHIVES, BACKEND_CFFI_MODULES, detect_backend, host_backends
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
