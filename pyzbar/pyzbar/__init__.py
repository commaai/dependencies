"""Read one-dimensional barcodes and QR codes from Python 2 and 3."""
import os

__version__ = '0.1.9'

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")


def smoketest():
  import platform

  if platform.system() == "Darwin":
    lib_name = "libzbar.dylib"
  else:
    lib_name = "libzbar.so"
  lib_path = os.path.join(LIB_DIR, lib_name)
  assert os.path.isfile(lib_path), f"{lib_name} not found at {lib_path}"

  from .pyzbar import decode
  result = decode((b'\x00', 1, 1))
  assert isinstance(result, list), "decode() did not return a list"
