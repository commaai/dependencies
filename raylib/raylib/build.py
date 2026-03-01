# Based on commaai/raylib-python-cffi (commit ab0191f)
# Modified to use local install paths and compile standalone (no cffi_modules)

import re
import os
import platform
import subprocess
import time

from cffi import FFI

HERE = os.path.dirname(os.path.abspath(__file__))
RAYLIB_INCLUDE_PATH = os.path.join(HERE, "install", "include")
RAYLIB_LIB_PATH = os.path.join(HERE, "install", "lib")
RAYLIB_PLATFORM = os.getenv("RAYLIB_PLATFORM", "")

ffibuilder = FFI()


def check_raylib_installed():
  return os.path.isfile(os.path.join(RAYLIB_LIB_PATH, 'libraylib.a'))


def pre_process_header(filename, remove_function_bodies=False):
  print("Pre-processing " + filename)
  file = open(filename, "r")
  filetext = "".join([line for line in file if '#include' not in line])
  command = ['gcc', '-CC', '-P', '-undef', '-nostdinc', '-DRL_MATRIX_TYPE',
             '-DRL_QUATERNION_TYPE', '-DRL_VECTOR4_TYPE', '-DRL_VECTOR3_TYPE', '-DRL_VECTOR2_TYPE',
             '-DRLAPI=', '-DPHYSACDEF=', '-DRAYGUIDEF=', '-DRMAPI=',
             '-dDI', '-E', '-']
  filetext = subprocess.run(command, text=True, input=filetext, stdout=subprocess.PIPE).stdout
  filetext = filetext.replace("va_list", "void *")
  if remove_function_bodies:
    filetext = re.sub('\n{\n(.|\n)*?\n}\n', ';', filetext)
  filetext = "\n".join([line for line in filetext.splitlines() if not line.startswith("#")])
  modified_path = os.path.join(HERE, os.path.basename(filename) + ".modified")
  with open(modified_path, "w") as f:
    f.write(filetext)
  return filetext


def check_header_exists(file):
  if not os.path.isfile(file):
    print(f"\nWARNING: {file} not found. Build will not contain these extra functions.\n")
    time.sleep(1)
    return False
  return True


def build_ffi():
  """Set up the FFI builder. Must be called after libraylib.a and headers exist."""
  if not check_raylib_installed():
    raise Exception("ERROR: raylib not found. Please run build.sh first.")

  raylib_h = os.path.join(RAYLIB_INCLUDE_PATH, "raylib.h")
  rlgl_h = os.path.join(RAYLIB_INCLUDE_PATH, "rlgl.h")
  raymath_h = os.path.join(RAYLIB_INCLUDE_PATH, "raymath.h")

  for h in (raylib_h, rlgl_h, raymath_h):
    if not os.path.isfile(h):
      raise Exception(f"ERROR: {h} not found. Please run build.sh first.")

  ffi_includes = """
    #include "raylib.h"
    #include "rlgl.h"
    #include "raymath.h"
  """

  raygui_h = os.path.join(RAYLIB_INCLUDE_PATH, "raygui.h")
  if check_header_exists(raygui_h):
    ffi_includes += """
      #define RAYGUI_IMPLEMENTATION
      #define RAYGUI_SUPPORT_RICONS
      #include "raygui.h"
    """

  ffibuilder.cdef(pre_process_header(raylib_h))
  ffibuilder.cdef(pre_process_header(rlgl_h))
  ffibuilder.cdef(pre_process_header(raymath_h, True))

  if os.path.isfile(raygui_h):
    ffibuilder.cdef(pre_process_header(raygui_h))

  if platform.system() == "Darwin":
    print("BUILDING FOR MAC")
    extra_link_args = [
      os.path.join(RAYLIB_LIB_PATH, 'libraylib.a'),
      '-framework', 'OpenGL',
      '-framework', 'Cocoa',
      '-framework', 'IOKit',
      '-framework', 'CoreFoundation',
      '-framework', 'CoreVideo',
    ]
    libraries = []
    extra_compile_args = ["-Wno-error=incompatible-function-pointer-types"]
  else:
    print("BUILDING FOR LINUX")
    extra_link_args = [
      f'-L{RAYLIB_LIB_PATH}', '-lraylib',
      '-lm', '-lpthread', '-lGL',
      '-lrt', '-ldl', '-lpthread', '-latomic',
    ]
    if RAYLIB_PLATFORM == "PLATFORM_COMMA":
      extra_link_args.remove('-lGL')
      extra_link_args += ['-lGLESv2', '-lEGL', '-lgbm', '-ldrm']
    elif RAYLIB_PLATFORM == "PLATFORM_OFFSCREEN":
      # Use offscreen variant if available, otherwise fall back to default
      offscreen_lib = os.path.join(RAYLIB_LIB_PATH, 'libraylib_offscreen.a')
      if os.path.isfile(offscreen_lib):
        extra_link_args[extra_link_args.index('-lraylib')] = '-lraylib_offscreen'
      extra_link_args.remove('-lGL')
      # Use bundled GLVND dispatchers if available, with RPATH for runtime
      mesa_dir = os.path.join(RAYLIB_LIB_PATH, 'mesa')
      if os.path.isdir(mesa_dir):
        extra_link_args += [f'-L{mesa_dir}', f'-Wl,-rpath,$ORIGIN/install/lib/mesa']
      extra_link_args += ['-lOpenGL', '-lEGL']
    else:
      extra_link_args += ['-lX11']
    extra_compile_args = ["-Wno-incompatible-pointer-types"]
    libraries = []

  print("extra_link_args: " + str(extra_link_args))
  ffibuilder.set_source("raylib._raylib_cffi",
                        ffi_includes,
                        py_limited_api=True,
                        include_dirs=[RAYLIB_INCLUDE_PATH],
                        extra_link_args=extra_link_args,
                        extra_compile_args=extra_compile_args,
                        libraries=libraries)


if __name__ == "__main__":
  build_ffi()
  # compile with output going to the package root (parent of raylib/)
  pkg_root = os.path.dirname(HERE)
  ffibuilder.compile(verbose=True, tmpdir=pkg_root)
