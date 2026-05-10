import importlib
import importlib.machinery
import os
import platform as _platform

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def _detect_backend():
  explicit = os.environ.get("RAYLIB_BACKEND", "").strip().lower()
  if explicit:
    if explicit not in ("comma", "desktop"):
      raise ValueError("RAYLIB_BACKEND must be 'comma' or 'desktop'")
    return explicit
  if os.path.exists("/AGNOS") or os.path.exists("/TICI"):
    return "comma"
  platform_override = os.environ.get("RAYLIB_PLATFORM", "")
  if platform_override == "PLATFORM_COMMA":
    return "comma"
  if platform_override == "PLATFORM_MEMORY":
    return "memory"
  if platform_override == "PLATFORM_DESKTOP":
    return "desktop"
  if os.environ.get("CI") and _platform.system() == "Linux" and _platform.machine() == "x86_64":
    return "memory"
  return "desktop"


def _backend_platform(backend):
  if backend == "comma":
    return "PLATFORM_COMMA"
  if backend == "memory":
    return "PLATFORM_MEMORY"
  return "PLATFORM_DESKTOP"


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
  backend = _detect_backend()

  if backend in ("desktop", "comma"):
    backend_module = f"_raylib_cffi_{backend}"
    if _has_extension(pkg_dir, backend_module):
      return backend_module

  # Export so build.py picks it up
  os.environ["RAYLIB_PLATFORM"] = _backend_platform(backend)
  if backend in ("desktop", "comma"):
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
