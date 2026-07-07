import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")
BIN_DIR = os.path.join(DIR, "bin")
LIB_DIR = os.path.join(DIR, "lib")
XKB_DIR = os.path.join(DIR, "share", "X11", "xkb")

XVFB_BIN = os.path.join(BIN_DIR, "Xvfb")
XKBCOMP_BIN = os.path.join(BIN_DIR, "xkbcomp")


# Common host paths where Mesa DRI drivers (e.g. swrast_dri.so) live. Xvfb
# was built on AlmaLinux 8 with /usr/lib64/dri baked in; on other distros
# (Debian/Ubuntu in particular) the drivers are elsewhere, and without them
# Xvfb fails to bring up a GL provider and silently disables the GLX
# extension. Probing the standard locations lets the host's drivers be
# found regardless of distro.
_DRI_PATHS = (
  "/usr/lib64/dri",
  "/usr/lib/x86_64-linux-gnu/dri",
  "/usr/lib/aarch64-linux-gnu/dri",
  "/usr/lib/dri",
)


def _run_xvfb():
  # The bundled Xvfb has its compile-time XkbBinDirectory blanked out so it
  # invokes xkbcomp via PATH lookup; prepend our bin dir so the bundled
  # xkbcomp wins. -xkbdir points the server at the bundled keymap data.
  env = os.environ.copy()
  env["PATH"] = BIN_DIR + os.pathsep + env.get("PATH", "")
  if "LIBGL_DRIVERS_PATH" not in env:
    found = [p for p in _DRI_PATHS if os.path.isdir(p)]
    if found:
      env["LIBGL_DRIVERS_PATH"] = os.pathsep.join(found)
  args = sys.argv[1:]
  if not any(a == "-xkbdir" for a in args):
    args = ["-xkbdir", XKB_DIR] + args
  os.execvpe(XVFB_BIN, [XVFB_BIN] + args, env)


def smoketest():
  if sys.platform == "darwin":
    return
  assert os.path.isfile(XVFB_BIN), f"Xvfb not found at {XVFB_BIN}"
  assert os.path.isfile(XKBCOMP_BIN), f"xkbcomp not found at {XKBCOMP_BIN}"
  assert os.path.isdir(XKB_DIR), f"xkb data not found at {XKB_DIR}"

  import subprocess
  # Xvfb prints usage to stderr and exits non-zero on `-help`; the banner
  # mentions Xvfb-specific flags like -screen and -fbdir. If those appear,
  # the binary loaded its bundled libs and ran far enough to print help.
  result = subprocess.run([XVFB_BIN, "-help"], capture_output=True, text=True)
  output = result.stderr + result.stdout
  assert "-screen scrn WxHxD" in output, \
      f"Xvfb -help did not produce expected output: {output}"
