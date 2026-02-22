import os
import sys

TOOLCHAIN_DIR = os.path.join(os.path.dirname(__file__), "toolchain")


def _run(name):
  binary = os.path.join(TOOLCHAIN_DIR, "bin", name)
  os.execvp(binary, [binary] + sys.argv[1:])


def _run_gcc():
  _run("arm-none-eabi-gcc")


def _run_objcopy():
  _run("arm-none-eabi-objcopy")


def _run_size():
  _run("arm-none-eabi-size")
