import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libcrypto.a")), "libcrypto.a not found"
  assert os.path.isfile(os.path.join(LIB_DIR, "libssl.a")), "libssl.a not found"
  assert os.path.isdir(os.path.join(INCLUDE_DIR, "openssl")), "openssl headers not found"
