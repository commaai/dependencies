import os
import sys
import tempfile

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
INCLUDE_DIR = os.path.join(DIR, "include")


def _run(name):
  binary = os.path.join(BIN_DIR, name)
  env = os.environ.copy()
  # ensure sibling binaries (e.g. capnpc-c++) are findable
  env["PATH"] = BIN_DIR + ":" + env.get("PATH", "")
  os.execvpe(binary, [binary] + sys.argv[1:], env)


def _run_capnp():
  _run("capnp")


def _run_capnpc():
  # capnpc is a symlink to capnp; capnp checks argv[0] to enter compile mode
  binary = os.path.join(BIN_DIR, "capnp")
  env = os.environ.copy()
  env["PATH"] = BIN_DIR + ":" + env.get("PATH", "")
  os.execvpe(binary, ["capnpc"] + sys.argv[1:], env)


def smoketest():
  import subprocess

  capnp = os.path.join(BIN_DIR, "capnp")
  capnpc = os.path.join(BIN_DIR, "capnpc")
  capnpc_cpp = os.path.join(BIN_DIR, "capnpc-c++")
  env = os.environ.copy()
  env["PATH"] = BIN_DIR + ":" + env.get("PATH", "")
  subprocess.run([capnp, "--version"], check=True, env=env)
  subprocess.run([capnpc, "--version"], check=True, env=env)
  subprocess.run([capnpc_cpp, "--version"], check=True, env=env)
  # PyPI rejects a "capnpc-c++" console script, so the c++ plugin ships only in
  # BIN_DIR; make sure capnp still finds it there via PATH.
  with tempfile.TemporaryDirectory() as temp_dir:
    schema = os.path.join(temp_dir, "test.capnp")
    with open(schema, "w") as f:
      f.write("@0xd12f9faaa6e3fdec; struct Test { value @0 :UInt32; }\n")
    env["PWD"] = temp_dir
    subprocess.run([capnp, "compile", "-oc++", schema], cwd=temp_dir, check=True, env=env)
