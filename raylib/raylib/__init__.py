import importlib
import os
import platform as _platform

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_ROOT = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")
BUILD_INFO = os.path.join(DIR, "build-info.txt")

_PLATFORM_BY_VARIANT = {
  "comma": "PLATFORM_COMMA",
  "desktop": "PLATFORM_DESKTOP",
  "offscreen": "PLATFORM_OFFSCREEN",
}


def _normalize_variant(value):
  if value in ("PLATFORM_COMMA", "comma"):
    return "comma"
  if value in ("PLATFORM_OFFSCREEN", "offscreen"):
    return "offscreen"
  if value in ("PLATFORM_DESKTOP", "desktop", ""):
    return "desktop"
  return value


def _detect_variant():
  explicit = os.environ.get("RAYLIB_VARIANT") or os.environ.get("RAYLIB_PLATFORM", "")
  if explicit:
    return _normalize_variant(explicit)
  if os.path.isfile("/TICI") or os.path.isfile("/AGNOS"):
    return "comma"
  if os.environ.get("CI") and _platform.system() == "Linux" and _platform.machine() == "x86_64":
    return "offscreen"
  return "desktop"


VARIANT = _detect_variant()
LIB_DIR = os.path.join(LIB_ROOT, VARIANT)
if not os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")):
  LIB_DIR = LIB_ROOT


def _module_name(variant):
  return f"_raylib_cffi_{variant}" if variant else "_raylib_cffi"


def _import_cffi_module():
  names = [_module_name(VARIANT), "_raylib_cffi"]
  seen = set()
  for name in names:
    if name in seen:
      continue
    seen.add(name)
    try:
      return importlib.import_module(f".{name}", __name__)
    except ImportError:
      continue
  return None


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")), "libraylib.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raylib.h")), "raylib.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raymath.h")), "raymath.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "rlgl.h")), "rlgl.h not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "raygui.h")), "raygui.h not found"
  assert os.path.isfile(BUILD_INFO), "build-info.txt not found"
  try:
    import _cffi_backend  # noqa: F401
  except ModuleNotFoundError:
    return
  assert _import_cffi_module() is not None, f"CFFI module for {VARIANT} not found"
  import pyray  # noqa: F401


def _ensure_cffi_built():
  import subprocess
  import sys

  if _import_cffi_module() is not None:
    return

  build_script = os.path.join(os.path.dirname(__file__), "build.py")
  if not os.path.isfile(build_script) or not os.path.isfile(os.path.join(LIB_DIR, "libraylib.a")):
    return

  env = os.environ.copy()
  env["RAYLIB_VARIANT"] = VARIANT
  env["RAYLIB_PLATFORM"] = _PLATFORM_BY_VARIANT.get(VARIANT, "PLATFORM_DESKTOP")
  env["RAYLIB_CFFI_MODULE"] = f"raylib.{_module_name(VARIANT)}"

  try:
    subprocess.check_call([sys.executable, build_script], cwd=os.path.dirname(os.path.dirname(__file__)), env=env)
  except subprocess.CalledProcessError:
    pass


_ensure_cffi_built()

_cffi_module = _import_cffi_module()
if _cffi_module is not None:
  ffi = _cffi_module.ffi
  rl = _cffi_module.lib
  for _name in dir(rl):
    if not _name.startswith("_"):
      globals()[_name] = getattr(rl, _name)

  from raylib.colors import *  # noqa: F403
  from raylib.defines import *  # noqa: F403
  from .version import __version__
