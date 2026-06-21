import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def _create_symlinks():
  if not os.path.isdir(LIB_DIR):
    return
  for name in os.listdir(LIB_DIR):
    if ".so." in name:
      parts = name.split(".so.")
      base = parts[0] + ".so"
      soname = parts[0] + ".so." + parts[1].split(".")[0]
      for link in (base, soname):
        path = os.path.join(LIB_DIR, link)
        if not os.path.exists(path):
          try:
            os.symlink(name, path)
          except OSError:
            pass
    elif name.endswith(".dylib") and name.count(".") > 2:
      stem = name.rsplit(".", 1)[0]
      parts = stem.split(".")
      libname = parts[0]
      major = parts[1]
      base = libname + ".dylib"
      soname = f"{libname}.{major}.dylib"
      for link in (base, soname):
        path = os.path.join(LIB_DIR, link)
        if not os.path.exists(path):
          try:
            os.symlink(name, path)
          except OSError:
            pass

_create_symlinks()


def _run(name):
  binary = os.path.join(BIN_DIR, name)
  os.execvp(binary, [binary] + sys.argv[1:])


def _run_ffmpeg():
  _run("ffmpeg")


def _run_ffprobe():
  _run("ffprobe")


def smoketest():
  import subprocess

  ffmpeg = os.path.join(BIN_DIR, "ffmpeg")
  ffprobe = os.path.join(BIN_DIR, "ffprobe")
  subprocess.run([ffmpeg, "-version"], check=True)
  subprocess.run([ffprobe, "-version"], check=True)
