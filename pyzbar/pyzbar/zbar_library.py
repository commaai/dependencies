"""Loads the zbar shared library bundled with this package."""
import platform

from ctypes import cdll
from pathlib import Path


def load():
  lib_dir = Path(__file__).parent / 'install' / 'lib'

  if platform.system() == 'Darwin':
    lib_name = 'libzbar.dylib'
  else:
    lib_name = 'libzbar.so'

  lib_path = lib_dir / lib_name
  if not lib_path.exists():
    raise ImportError(
      f'Bundled zbar shared library not found at {lib_path}'
    )

  return cdll.LoadLibrary(str(lib_path)), []
