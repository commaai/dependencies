import os
import platform

DESKTOP = "desktop"
COMMA = "comma"
BACKENDS = (DESKTOP, COMMA)
DEFAULT_BACKEND = DESKTOP

BACKEND_CFFI_MODULES = {
  DESKTOP: "_raylib_cffi_desktop",
  COMMA: "_raylib_cffi_comma",
}

BACKEND_ARCHIVES = {
  DESKTOP: "libraylib_desktop.a",
  COMMA: "libraylib_comma.a",
}

BACKEND_LINK_ARGS = {
  DESKTOP: ("-lGL", "-lX11"),
  COMMA: ("-lGLESv2", "-lEGL", "-lgbm", "-ldrm"),
}

COMMA_DEVICE_MARKERS = ("/AGNOS", "/TICI")


def is_dual_backend_host():
  return platform.system() == "Linux" and platform.machine() in ("aarch64", "arm64")


def detect_backend(environ=None, exists=os.path.exists):
  environ = os.environ if environ is None else environ
  if environ.get("RAYLIB_PLATFORM"):
    raise ValueError("RAYLIB_PLATFORM is no longer supported; use RAYLIB_BACKEND=comma|desktop")

  explicit = environ.get("RAYLIB_BACKEND", "").strip().lower()
  if explicit:
    if explicit not in BACKENDS:
      raise ValueError("RAYLIB_BACKEND must be 'comma' or 'desktop'")
    return explicit

  if any(exists(marker) for marker in COMMA_DEVICE_MARKERS):
    return COMMA

  return DEFAULT_BACKEND
