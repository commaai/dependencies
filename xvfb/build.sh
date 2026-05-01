#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$DIR"

INSTALL_DIR="$DIR/xvfb/install"

# macOS: Xvfb is Linux-only. Ship an empty install dir so the wheel still
# builds; smoketest() is a no-op on Darwin.
if [[ "$OSTYPE" == "darwin"* ]]; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"/{bin,lib,share/X11/xkb}
  echo "xvfb: macOS not supported, shipping empty install dir"
  exit 0
fi

# Linux: bundle the Xvfb binary, xkbcomp, xkb keymap data, and the closure
# of shared libraries it needs (minus libc/libpthread/etc which the host
# always provides). For CI/manylinux we pull from AlmaLinux 8 so the wheel
# works on any glibc >= 2.28 distro; on a Debian/Ubuntu dev host we accept
# whatever the system has (the local wheel just won't be as portable).
if command -v dnf >/dev/null 2>&1; then
  dnf install -y -q xorg-x11-server-Xvfb xorg-x11-xkb-utils xkeyboard-config >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
  if [[ "$(id -u)" -eq 0 ]]; then SUDO=""
  elif command -v sudo >/dev/null 2>&1; then SUDO=sudo
  else echo "xvfb: need sudo or root to apt-get install" >&2; exit 1; fi
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq --no-install-recommends \
    xvfb x11-xkb-utils xkb-data patchelf
else
  echo "xvfb: need dnf or apt-get to fetch upstream Xvfb" >&2
  exit 1
fi

if ! command -v patchelf >/dev/null 2>&1; then
  echo "xvfb: patchelf is required but not found" >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,share/X11/xkb}

# Xvfb may live in /usr/bin (RPM/Debian) — just locate it.
XVFB_SRC="$(command -v Xvfb || true)"
XKBCOMP_SRC="$(command -v xkbcomp || true)"
if [[ -z "$XVFB_SRC" || -z "$XKBCOMP_SRC" ]]; then
  echo "xvfb: Xvfb or xkbcomp not found after install" >&2
  exit 1
fi

cp "$XVFB_SRC"    "$INSTALL_DIR/bin/Xvfb"
cp "$XKBCOMP_SRC" "$INSTALL_DIR/bin/xkbcomp"
chmod u+w "$INSTALL_DIR/bin/Xvfb" "$INSTALL_DIR/bin/xkbcomp"
cp -a /usr/share/X11/xkb/. "$INSTALL_DIR/share/X11/xkb/"

# Two binary patches to make Xvfb relocatable:
#
# 1. "/usr/bin"  -> "" (null bytes)
#    Xvfb's compile-time XkbBinDirectory points at /usr/bin and is used to
#    build an absolute path to xkbcomp. Blanking it makes the spawned
#    command just "xkbcomp", which popen() then resolves via PATH. Our
#    Python wrapper prepends the bundled bin/ to PATH.
#
# 2. "-R%s" -> "-I%s" (in the xkbcomp argv format string)
#    Xvfb passes its XkbBaseDirectory to xkbcomp via -R, expecting xkbcomp
#    to chdir there *and* add "." to the include path. xkbcomp 1.4.x only
#    chdirs — the include-path side was added later. Switching to -I makes
#    1.4.2 actually search the path we hand it via -xkbdir.
python3 - "$INSTALL_DIR/bin/Xvfb" <<'PY'
import sys
path = sys.argv[1]
with open(path, "r+b") as f:
    data = bytearray(f.read())

def replace_unique(needle: bytes, replacement: bytes):
    assert len(needle) == len(replacement)
    idx = data.find(needle)
    if idx < 0:
        sys.exit(f"could not find {needle!r} in Xvfb binary")
    if data.find(needle, idx + 1) >= 0:
        sys.exit(f"multiple {needle!r} matches; refusing to patch")
    data[idx:idx + len(needle)] = replacement

replace_unique(b"/usr/bin\x00", b"\x00" * 9)
replace_unique(b'"-R%s"\x00', b'"-I%s"\x00')

with open(path, "wb") as f:
    f.write(data)
PY

# bundle the shared library closure. Recursively walk ldd output to catch
# libs-of-libs (e.g. libXfont2 -> libfontenc -> libbz2). Skip core glibc
# pieces; everything else gets copied alongside the binary.
declare -A SEEN
collect_libs() {
  local target="$1"
  while IFS= read -r line; do
    local lib
    lib=$(echo "$line" | awk '{print $3}')
    [[ -z "$lib" || "$lib" == "not" ]] && continue
    [[ ! -e "$lib" ]] && continue
    local base
    base=$(basename "$lib")
    case "$base" in
      libc.so.*|libpthread.so.*|libm.so.*|librt.so.*|libdl.so.*|libgcc_s.so.*|libresolv.so.*|libutil.so.*|ld-linux-*.so.*|linux-vdso.so.*|linux-gate.so.*)
        continue ;;
    esac
    [[ -n "${SEEN[$base]:-}" ]] && continue
    SEEN[$base]=1
    cp -L "$lib" "$INSTALL_DIR/lib/$base"
    chmod u+w "$INSTALL_DIR/lib/$base"
    collect_libs "$INSTALL_DIR/lib/$base"
  done < <(ldd "$target" 2>/dev/null || true)
}
collect_libs "$INSTALL_DIR/bin/Xvfb"
collect_libs "$INSTALL_DIR/bin/xkbcomp"

# point the binaries (and the bundled libs) at our private lib dir so they
# don't accidentally resolve against an incompatible host copy.
patchelf --set-rpath '$ORIGIN/../lib' "$INSTALL_DIR/bin/Xvfb"
patchelf --set-rpath '$ORIGIN/../lib' "$INSTALL_DIR/bin/xkbcomp"
for so in "$INSTALL_DIR"/lib/*.so*; do
  patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
done

strip --strip-unneeded "$INSTALL_DIR/bin/Xvfb" "$INSTALL_DIR/bin/xkbcomp" 2>/dev/null || true
find "$INSTALL_DIR/lib" -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true

echo "Installed xvfb to $INSTALL_DIR"
du -sh "$INSTALL_DIR"
