import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def _run(name):
  binary = os.path.join(BIN_DIR, name)
  os.execvp(binary, [binary] + sys.argv[1:])


def _run_ffmpeg():
  _run("ffmpeg")


def _run_ffprobe():
  _run("ffprobe")
