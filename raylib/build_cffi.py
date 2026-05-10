# Based on commaai/raylib-python-cffi (commit a32e910)
# Modified to use local install paths and compile standalone.

import os
import platform
import re
import subprocess
import sys

from cffi import FFI

ROOT = os.path.dirname(os.path.abspath(__file__))
PACKAGE_DIR = os.path.join(ROOT, "raylib")
RAYLIB_INCLUDE_PATH = os.path.join(PACKAGE_DIR, "install", "include")
RAYLIB_LIB_PATH = os.path.join(PACKAGE_DIR, "install", "lib")

sys.path.insert(0, PACKAGE_DIR)
from _backend import BACKEND_ARCHIVES, BACKEND_CFFI_MODULES, BACKEND_LINK_ARGS, detect_backend  # noqa: E402
from validate_bindings import validate_static_bindings  # noqa: E402

RAYLIB_BACKEND = detect_backend()
RAYLIB_CFFI_MODULE = os.getenv("RAYLIB_CFFI_MODULE", f"raylib.{BACKEND_CFFI_MODULES[RAYLIB_BACKEND]}")

ffibuilder = FFI()


def _raylib_archive():
  archive = os.path.join(RAYLIB_LIB_PATH, BACKEND_ARCHIVES[RAYLIB_BACKEND])
  if not os.path.isfile(archive):
    raise FileNotFoundError(f"{archive} not found. Please run build.sh first.")
  return archive


def pre_process_header(filename, remove_function_bodies=False):
  print("Pre-processing " + filename)
  with open(filename, "r") as f:
    filetext = "".join([line for line in f if '#include' not in line])
  command = ['gcc', '-CC', '-P', '-undef', '-nostdinc', '-DRL_MATRIX_TYPE',
             '-DRL_QUATERNION_TYPE', '-DRL_VECTOR4_TYPE', '-DRL_VECTOR3_TYPE', '-DRL_VECTOR2_TYPE',
             '-DRLAPI=', '-DPHYSACDEF=', '-DRAYGUIDEF=', '-DRMAPI=',
             '-dDI', '-E', '-']
  filetext = subprocess.run(command, text=True, input=filetext, stdout=subprocess.PIPE, check=True).stdout
  filetext = filetext.replace("va_list", "void *")
  if remove_function_bodies:
    filetext = re.sub('\n{\n(.|\n)*?\n}\n', ';', filetext)
  return "\n".join([line for line in filetext.splitlines() if not line.startswith("#")])


def build_ffi():
  raylib_archive = _raylib_archive()

  raylib_h = os.path.join(RAYLIB_INCLUDE_PATH, "raylib.h")
  rlgl_h = os.path.join(RAYLIB_INCLUDE_PATH, "rlgl.h")
  raymath_h = os.path.join(RAYLIB_INCLUDE_PATH, "raymath.h")
  raygui_h = os.path.join(RAYLIB_INCLUDE_PATH, "raygui.h")

  for header in (raylib_h, rlgl_h, raymath_h, raygui_h):
    if not os.path.isfile(header):
      raise FileNotFoundError(f"{header} not found. Please run build.sh first.")

  ffi_includes = """
    #include "raylib.h"
    #include "rlgl.h"
    #include "raymath.h"
    #define RAYGUI_IMPLEMENTATION
    #define RAYGUI_SUPPORT_RICONS
    #include "raygui.h"
  """

  ffibuilder.cdef(pre_process_header(raylib_h))
  ffibuilder.cdef(pre_process_header(rlgl_h))
  ffibuilder.cdef(pre_process_header(raymath_h, True))
  ffibuilder.cdef(pre_process_header(raygui_h))

  validate_static_bindings(PACKAGE_DIR, RAYLIB_INCLUDE_PATH)

  if platform.system() == "Darwin":
    print("BUILDING FOR MAC")
    extra_link_args = [
      raylib_archive,
      '-framework', 'OpenGL',
      '-framework', 'Cocoa',
      '-framework', 'IOKit',
      '-framework', 'CoreFoundation',
      '-framework', 'CoreVideo',
    ]
    extra_compile_args = ["-Wno-error=incompatible-function-pointer-types"]
  else:
    print("BUILDING FOR LINUX")
    extra_link_args = [
      raylib_archive,
      '-lm', '-lpthread', '-lrt', '-ldl', '-latomic',
      *BACKEND_LINK_ARGS[RAYLIB_BACKEND],
    ]
    extra_compile_args = ["-Wno-incompatible-pointer-types"]

  print("extra_link_args: " + str(extra_link_args))
  ffibuilder.set_source(RAYLIB_CFFI_MODULE,
                        ffi_includes,
                        py_limited_api=True,
                        include_dirs=[RAYLIB_INCLUDE_PATH],
                        extra_link_args=extra_link_args,
                        extra_compile_args=extra_compile_args,
                        libraries=[])


if __name__ == "__main__":
  build_ffi()
  ffibuilder.compile(verbose=True, tmpdir=ROOT)
