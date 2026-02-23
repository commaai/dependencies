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


def smoketest():
  import subprocess
  import tempfile

  gcc = os.path.join(TOOLCHAIN_DIR, "bin", "arm-none-eabi-gcc")
  size = os.path.join(TOOLCHAIN_DIR, "bin", "arm-none-eabi-size")

  subprocess.run([gcc, "--version"], check=True)

  with tempfile.TemporaryDirectory() as tmp:
    src = os.path.join(tmp, "hello.c")
    elf = os.path.join(tmp, "hello.elf")
    with open(src, "w") as f:
      f.write("volatile int counter;\nint main(void) { counter = 42; while(1){} }\n")
    subprocess.run([gcc, "-mcpu=cortex-m7", "-mthumb", "-nostdlib", "-o", elf, src], check=True)
    subprocess.run([size, elf], check=True)
