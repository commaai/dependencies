import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")), "libraylib.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raylib.h")), "raylib.h not found"


# Build CFFI extension on first import if not already compiled
def _ensure_cffi_built():
  import glob
  import subprocess
  import sys
  pkg_dir = os.path.dirname(__file__)
  if not glob.glob(os.path.join(pkg_dir, "_raylib_cffi*")):
    build_script = os.path.join(pkg_dir, "build.py")
    if os.path.isfile(build_script) and os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")):
      try:
        subprocess.check_call([sys.executable, build_script], cwd=os.path.dirname(pkg_dir))
      except subprocess.CalledProcessError:
        pass

_ensure_cffi_built()

# CFFI bindings (available when graphics libraries are present)
try:
  from ._raylib_cffi import ffi, lib as rl
  from raylib._raylib_cffi.lib import *  # noqa: F403
  from raylib.colors import *  # noqa: F403
  from raylib.defines import *  # noqa: F403
  from .version import __version__
except (ImportError, OSError):
  pass
