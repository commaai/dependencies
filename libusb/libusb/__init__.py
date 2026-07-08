import os

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")
PKGCONFIG_DIR = os.path.join(LIB_DIR, "pkgconfig")


def smoketest():
  assert os.path.isfile(os.path.join(LIB_DIR, "libusb-1.0.a")), "libusb-1.0.a not found"
  assert os.path.isfile(os.path.join(INCLUDE_DIR, "libusb-1.0", "libusb.h")), "libusb.h not found"
  assert os.path.isfile(os.path.join(PKGCONFIG_DIR, "libusb-1.0.pc")), "libusb-1.0.pc not found"
