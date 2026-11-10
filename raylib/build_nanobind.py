import os
import platform
import sys
from pathlib import Path

import nanobind
from setuptools import Extension, setup

sys.path.insert(0, str(Path(__file__).resolve().parent / "raylib"))
from _backend import BACKEND_ARCHIVES, BACKEND_LINK_ARGS  # noqa: E402

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "raylib-src"
LIB = ROOT / "raylib" / "install" / "lib"
NB = Path(nanobind.__file__).resolve().parent
BACKEND = os.environ["RAYLIB_BACKEND"]

if platform.system() == "Darwin":
  link_args = [flag for framework in ("OpenGL", "Cocoa", "IOKit", "CoreAudio", "CoreVideo")
               for flag in ("-framework", framework)]
else:
  link_args = ["-lm", "-lpthread", "-lrt", "-ldl", "-latomic", *BACKEND_LINK_ARGS[BACKEND]]

setup(
  package_dir={"raylib_nb": str(SOURCE / "python" / "raylib_nb")},
  ext_modules=[Extension(
    f"raylib_nb._raylib_{BACKEND}",
    sources=[str(SOURCE / "python" / "bindings.cc"), str(NB / "src" / "nb_combined.cpp")],
    include_dirs=[str(SOURCE / "src"), str(NB / "include"), str(NB / "ext" / "robin_map" / "include")],
    define_macros=[("RAYLIB_MODULE", f"_raylib_{BACKEND}"), ("Py_LIMITED_API", "0x030C0000")],
    extra_objects=[str(LIB / BACKEND_ARCHIVES[BACKEND])],
    extra_compile_args=["-std=c++17", "-fvisibility=hidden"],
    extra_link_args=link_args,
    py_limited_api=True,
    language="c++",
  )],
)
