import os
import platform

DESKTOP = "desktop"
COMMA = "comma"
HEADLESS = "headless"
BACKENDS = (DESKTOP, COMMA, HEADLESS)
DEFAULT_BACKEND = DESKTOP

BACKEND_CFFI_MODULES = {
  DESKTOP: "_raylib_cffi_desktop",
  COMMA: "_raylib_cffi_comma",
  HEADLESS: "_raylib_cffi_headless",
}

BACKEND_ARCHIVES = {
  DESKTOP: "libraylib_desktop.a",
  COMMA: "libraylib_comma.a",
  HEADLESS: "libraylib_headless.a",
}

# every backend draws on the CPU. desktop's RGFW window still links GL, though nothing draws with it
BACKEND_LINK_ARGS = {
  DESKTOP: ("-lGL", "-lX11", "-lXrandr"),
  COMMA: ("-ldrm",),
  HEADLESS: (),
}

COMMA_DEVICE_MARKERS = ("/AGNOS", "/TICI")


def host_backends():
  """Backends built into this host's wheels."""
  if platform.system() != "Linux":
    return (DESKTOP,)
  if platform.machine() in ("aarch64", "arm64"):
    return (DESKTOP, COMMA, HEADLESS)
  return (DESKTOP, HEADLESS)


def detect_backend(environ=None, exists=os.path.exists):
  environ = os.environ if environ is None else environ
  if environ.get("RAYLIB_PLATFORM"):
    raise ValueError(f"RAYLIB_PLATFORM is no longer supported; use RAYLIB_BACKEND={'|'.join(BACKENDS)}")

  explicit = environ.get("RAYLIB_BACKEND", "").strip().lower()
  if explicit:
    if explicit not in BACKENDS:
      raise ValueError(f"RAYLIB_BACKEND must be one of {', '.join(repr(b) for b in BACKENDS)}")
    return explicit

  if any(exists(marker) for marker in COMMA_DEVICE_MARKERS):
    return COMMA
  if HEADLESS in host_backends() and not environ.get("DISPLAY"):
    return HEADLESS
  return DEFAULT_BACKEND
