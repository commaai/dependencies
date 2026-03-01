import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")), "libraylib.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raylib.h")), "raylib.h not found"


# Build CFFI extension on first import if not already compiled,
# or rebuild if RAYLIB_PLATFORM changed since last build.
def _ensure_cffi_built():
  import glob
  import subprocess
  import sys
  pkg_dir = os.path.dirname(__file__)
  platform_marker = os.path.join(pkg_dir, ".raylib_platform")
  requested = os.environ.get("RAYLIB_PLATFORM", "")
  cffi_files = glob.glob(os.path.join(pkg_dir, "_raylib_cffi*"))

  # Rebuild if platform changed
  if cffi_files and requested:
    built_for = open(platform_marker).read().strip() if os.path.isfile(platform_marker) else ""
    if built_for != requested:
      for f in cffi_files:
        os.remove(f)
      cffi_files = []

  if not cffi_files:
    build_script = os.path.join(pkg_dir, "build.py")
    if os.path.isfile(build_script) and os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")):
      try:
        subprocess.check_call([sys.executable, build_script], cwd=os.path.dirname(pkg_dir))
        with open(platform_marker, "w") as f:
          f.write(requested)
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
