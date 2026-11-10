import glob
import os
import platform
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import distribution
from pathlib import Path

from setuptools import setup
from setuptools.command.bdist_wheel import bdist_wheel
from setuptools.command.build_py import build_py

PKG_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(PKG_DIR, "raylib"))
from _backend import BACKEND_CFFI_MODULES, detect_backend, host_backends  # noqa: E402


class BuildRaylib(build_py):
  """Run build.sh to compile raylib artifacts before collecting package data."""

  @staticmethod
  def _build_cffi(backend):
    env = os.environ.copy()
    env["RAYLIB_BACKEND"] = backend
    env["RAYLIB_CFFI_MODULE"] = f"raylib.{BACKEND_CFFI_MODULES[backend]}"
    subprocess.check_call([sys.executable, "build_cffi.py"], cwd=PKG_DIR, env=env)

  @staticmethod
  def _build_nanobind_backend(backend):
    env = dict(os.environ, RAYLIB_BACKEND=backend)
    subprocess.check_call([sys.executable, "build_nanobind.py", "build_ext", "--inplace", "--force",
                           "--build-temp", os.path.join("build", f"temp-nanobind-{backend}")], cwd=PKG_DIR, env=env)

  def _build_nanobind(self, backends):
    source = Path(PKG_DIR) / "raylib-src"
    package = source / "python" / "raylib_nb"
    for old in package.glob("_raylib*.so"):
      old.unlink()
    with ThreadPoolExecutor(len(backends)) as pool:
      list(pool.map(self._build_nanobind_backend, backends))
    target = Path(self.build_lib) / "raylib_nb"
    shutil.copytree(package, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    notices = target / "licenses"
    notices.mkdir()
    shutil.copy2(source / "LICENSE", notices / "LICENSE.raylib")
    (notices / "LICENSE.nanobind").write_text(distribution("nanobind").read_text("licenses/LICENSE"))
    nb = Path(distribution("nanobind").locate_file("nanobind"))
    header = nb / "ext" / "robin_map" / "include" / "tsl" / "robin_map.h"
    (notices / "LICENSE.robin-map").write_text(header.read_text().split("*/", 1)[0] + "*/\n")
    env = dict(os.environ, PYTHONPATH=str(Path(self.build_lib).resolve()),
               RAYLIB_BACKEND="headless" if platform.system() == "Linux" and "headless" in backends else backends[0],
               RAYLIB_TEST_RENDER="1" if platform.system() == "Linux" else "0")
    subprocess.check_call([sys.executable, "-m", "unittest", "discover", "-s", str(source / "python" / "tests"), "-v"], env=env)

  def run(self):
    # CI's native cache (build_native_cache.py) already restored the compiled artifacts
    prebuilt = "raylib" in os.environ.get("DEPENDENCIES_PREBUILT", "").split(",")
    if not prebuilt:
      subprocess.check_call(["bash", "build.sh"], cwd=PKG_DIR)

      # Always regenerate CFFI extensions: the cached raylib source pin may have changed.
      for old_cffi in glob.glob(os.path.join(PKG_DIR, "raylib", "_raylib_cffi*")):
        os.remove(old_cffi)
      # explicit RAYLIB_BACKEND builds only that backend (matches build.sh)
      backends = (detect_backend(),) if os.environ.get("RAYLIB_BACKEND") else host_backends()
      with ThreadPoolExecutor(len(backends)) as pool:
        list(pool.map(self._build_cffi, backends))

    # Wipe build_lib package dirs so deleted/renamed files (e.g. old _raylib_cffi*
    # backends, removed modules) don't get packaged from the cached build/ tree.
    for package in ("raylib", "pyray", "raylib_nb"):
      shutil.rmtree(os.path.join(self.build_lib, package), ignore_errors=True)

    super().run()

    # raylib_nb/ in the package dir holds the last built nanobind package for the native cache
    nb_cache = Path(PKG_DIR) / "raylib_nb"
    if prebuilt:
      shutil.copytree(nb_cache, Path(self.build_lib) / "raylib_nb")
    else:
      self._build_nanobind(backends)
      shutil.rmtree(nb_cache, ignore_errors=True)
      shutil.copytree(Path(self.build_lib) / "raylib_nb", nb_cache)


class PlatformWheel(bdist_wheel):
  """Produce a platform-specific wheel with native raylib artifacts."""

  def finalize_options(self):
    super().finalize_options()
    self.root_is_pure = False

  def get_tag(self):
    _, _, plat_tag = super().get_tag()
    if platform.system() == "Linux":
      # manylinux images set AUDITWHEEL_PLAT (e.g. manylinux_2_28_x86_64);
      # PyPI rejects bare linux_* tags, so use it when building in one.
      plat_tag = os.environ.get("AUDITWHEEL_PLAT", f"linux_{platform.machine()}")
    elif platform.system() == "Darwin":
      plat_tag = "macosx_11_0_arm64"
    return "cp312", "abi3", plat_tag


setup(cmdclass={"build_py": BuildRaylib, "bdist_wheel": PlatformWheel})
