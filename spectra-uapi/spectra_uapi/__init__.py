import os

DIR = os.path.join(os.path.dirname(__file__), "install")
INCLUDE_DIRS = {abi: os.path.join(DIR, abi, "include") for abi in ("agnos", "camera_kt")}


def smoketest():
  for path in INCLUDE_DIRS.values():
    assert os.path.isfile(os.path.join(path, "media", "cam_sensor.h")), "Camera headers not found"
