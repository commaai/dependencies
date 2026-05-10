import importlib
import importlib.machinery
import os
import platform as _platform

from ._backend import cffi_module_for_backend, detect_backend, platform_for_backend

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def _has_extension(pkg_dir, module_name):
  return any(os.path.isfile(os.path.join(pkg_dir, module_name + suffix))
             for suffix in importlib.machinery.EXTENSION_SUFFIXES)


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")), "libraylib.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raylib.h")), "raylib.h not found"
  if _platform.system() == "Linux" and _platform.machine() in ("aarch64", "arm64"):
    assert os.path.isfile(os.path.join(LIB_DIR, "libraylib_desktop.a")), "libraylib_desktop.a not found"
    assert os.path.isfile(os.path.join(LIB_DIR, "libraylib_comma.a")), "libraylib_comma.a not found"


# Build CFFI extension on first import if not already compiled,
# or rebuild if the target platform changed since last build.
def _ensure_cffi_built():
  import glob
  import subprocess
  import sys
  pkg_dir = os.path.dirname(__file__)
  backend_marker = os.path.join(pkg_dir, ".raylib_backend")
  backend = detect_backend()

  backend_module = cffi_module_for_backend(backend)
  if _has_extension(pkg_dir, backend_module):
    return backend_module

  # Export so build.py picks it up
  os.environ["RAYLIB_PLATFORM"] = platform_for_backend(backend)
  os.environ["RAYLIB_BACKEND"] = backend

  default_module = "_raylib_cffi"
  cffi_files = glob.glob(os.path.join(pkg_dir, "_raylib_cffi.*"))
  default_exists = _has_extension(pkg_dir, default_module)

  if default_exists:
    built_for = open(backend_marker).read().strip() if os.path.isfile(backend_marker) else "desktop"
    if built_for == backend:
      return default_module

  if cffi_files:
    for f in cffi_files:
      os.remove(f)
    for modified_header in glob.glob(os.path.join(pkg_dir, "*.modified")):
      os.remove(modified_header)

  build_script = os.path.join(pkg_dir, "build.py")
  if os.path.isfile(build_script) and os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")):
    try:
      subprocess.check_call([sys.executable, build_script], cwd=os.path.dirname(pkg_dir))
      with open(backend_marker, "w") as f:
        f.write(backend)
    except subprocess.CalledProcessError:
      pass
  return default_module

_cffi_module = _ensure_cffi_built()

# CFFI bindings (available when graphics libraries are present)
try:
  _cffi = importlib.import_module(f".{_cffi_module}", __name__)
  ffi, rl = _cffi.ffi, _cffi.lib
  for _name in dir(rl):
    if not _name.startswith("_"):
      globals()[_name] = getattr(rl, _name)
  from raylib.colors import *  # noqa: F403
  from raylib.defines import *  # noqa: F403
  from .version import __version__
except (ImportError, OSError):
  pass
