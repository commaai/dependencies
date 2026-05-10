import os

DESKTOP = "desktop"
COMMA = "comma"
BACKENDS = (DESKTOP, COMMA)
DEFAULT_BACKEND = DESKTOP

BACKEND_PLATFORMS = {
  DESKTOP: "PLATFORM_DESKTOP",
  COMMA: "PLATFORM_COMMA",
}
PLATFORM_BACKENDS = {platform: backend for backend, platform in BACKEND_PLATFORMS.items()}

BACKEND_CFFI_MODULES = {
  DESKTOP: "_raylib_cffi_desktop",
  COMMA: "_raylib_cffi_comma",
}

BACKEND_ARCHIVES = {
  DESKTOP: ("libraylib_desktop.a", "libraylib.a"),
  COMMA: ("libraylib_comma.a", "libraylib.a"),
}

BACKEND_LINK_ARGS = {
  DESKTOP: ("-lGL", "-lX11"),
  COMMA: ("-lGLESv2", "-lEGL", "-lgbm", "-ldrm"),
}

COMMA_DEVICE_MARKERS = ("/AGNOS", "/TICI")


def validate_backend(backend):
  if backend not in BACKENDS:
    raise ValueError("RAYLIB_BACKEND must be 'comma' or 'desktop'")
  return backend


def backend_from_platform(platform):
  if platform not in PLATFORM_BACKENDS:
    raise ValueError("RAYLIB_PLATFORM must be 'PLATFORM_COMMA' or 'PLATFORM_DESKTOP'")
  return PLATFORM_BACKENDS[platform]


def detect_backend(environ=None, exists=os.path.exists):
  environ = os.environ if environ is None else environ

  explicit = environ.get("RAYLIB_BACKEND", "").strip().lower()
  if explicit:
    return validate_backend(explicit)

  if any(exists(marker) for marker in COMMA_DEVICE_MARKERS):
    return COMMA

  platform = environ.get("RAYLIB_PLATFORM", "")
  if platform:
    return backend_from_platform(platform)

  return DEFAULT_BACKEND


def platform_for_backend(backend):
  return BACKEND_PLATFORMS[validate_backend(backend)]


def cffi_module_for_backend(backend):
  return BACKEND_CFFI_MODULES[validate_backend(backend)]


def qualified_cffi_module_for_backend(backend):
  return f"raylib.{cffi_module_for_backend(backend)}"


def archive_candidates_for_backend(backend):
  return BACKEND_ARCHIVES[validate_backend(backend)]


def link_args_for_backend(backend):
  return BACKEND_LINK_ARGS[validate_backend(backend)]
