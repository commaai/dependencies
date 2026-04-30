import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIR = os.path.join(DIR, "include")
LIB_DIR = os.path.join(DIR, "lib")
BIN_DIR = os.path.join(DIR, "bin")
TERA_PATH = os.path.join(BIN_DIR, "t_renderer")

TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "acados_template")


def smoketest():
  import sys

  lib_ext = ".dylib" if sys.platform == "darwin" else ".so"
  for lib in ("libacados", "libblasfeo", "libhpipm", "libqpOASES_e"):
    path = os.path.join(LIB_DIR, lib + lib_ext)
    assert os.path.isfile(path), f"missing lib: {path}"

  assert os.path.isfile(os.path.join(INCLUDE_DIR, "acados_c", "ocp_nlp_interface.h"))
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "blasfeo", "include", "blasfeo.h"))
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "hpipm", "include", "hpipm_common.h"))

  assert os.path.isfile(TERA_PATH) and os.access(TERA_PATH, os.X_OK), f"t_renderer missing/not executable: {TERA_PATH}"

  assert os.path.isfile(os.path.join(TEMPLATE_DIR, "__init__.py"))
  assert os.path.isfile(os.path.join(TEMPLATE_DIR, "acados_layout.json"))
  assert os.path.isdir(os.path.join(TEMPLATE_DIR, "c_templates_tera"))
