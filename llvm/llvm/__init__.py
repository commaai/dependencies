import ctypes
import os
import platform

DIR = os.path.join(os.path.dirname(__file__), "install")
LIB_DIR = os.path.join(DIR, "lib")


def smoketest():
  if platform.system() == "Darwin":
    lib = os.path.join(LIB_DIR, "libLLVM.dylib")
  else:
    lib = os.path.join(LIB_DIR, "libLLVM.so")
  assert os.path.isfile(lib), f"{lib} not found"

  # verify it loads and we can call a basic C API function
  ll = ctypes.CDLL(lib)
  # LLVMInitializeX86TargetInfo should be present
  assert hasattr(ll, "LLVMInitializeX86TargetInfo"), "missing X86 target"
  assert hasattr(ll, "LLVMInitializeAArch64TargetInfo"), "missing AArch64 target"
