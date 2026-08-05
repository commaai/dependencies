#!/bin/bash
set -euo pipefail
WHEEL="$(realpath "$1")"
TMPDIR="$(mktemp -d)"
OUTDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR" "$OUTDIR"' EXIT

cd "$TMPDIR"
unzip -q "$WHEEL"
L=comma_deps_raylib.libs

resolve() { ldconfig -p | awk -v n="$1" '$1==n {print $NF; exit}'; }

ROOTS="libEGL_mesa.so.0 swrast_dri.so"
DRI_DIR=/usr/lib64/dri

declare -A DONE
todo="$ROOTS"
while [ -n "$todo" ]; do
  next=""
  for soname in $todo; do
    [ -n "${DONE[$soname]:-}" ] && continue
    DONE[$soname]=1
    if [ "$soname" = "swrast_dri.so" ]; then
      src="$DRI_DIR/swrast_dri.so"
    else
      src=$(resolve "$soname")
    fi
    [ -f "$src" ] || continue
    cp -L "$src" "$L/$soname"
    for dep in $(readelf -d "$src" 2>/dev/null | awk '/NEEDED/{print $5}' | tr -d '[]'); do
      case "$dep" in
        libc.so.6|libm.so.6|libpthread.so.0|librt.so.1|libdl.so.2|ld-linux-x86-64.so.2|libLLVM*)
          continue;;
      esac
      next="$next $dep"
    done
  done
  todo="$next"
done

for f in "$L"/*; do
  patchelf --force-rpath --set-rpath '$ORIGIN' "$f"
done

LLVM_SONAME="$(readelf -d "$L/swrast_dri.so" | awk '/NEEDED.*libLLVM/{print $NF}' | tr -d '[]')"
if [ -n "$LLVM_SONAME" ]; then
  python3 - "$L/swrast_dri.so" "$L/$LLVM_SONAME" <<'PY'
import re, subprocess, sys
swrast, out = sys.argv[1], sys.argv[2]
lines = subprocess.check_output(["objdump", "-T", swrast], text=True).splitlines()
ver = next((m.group(1) for line in lines if (m := re.search(r"\((LLVM_[0-9]+)\)", line))), "")
if not ver:
    sys.exit(f"no LLVM version found in {swrast}")
TYPES = {"DF", "F", "IF", "WF", "DO", "D", "O", "WO"}
funcs, datas = [], []
for line in lines:
    parts = line.split()
    if f"({ver})" not in parts:
        continue
    idx = parts.index(f"({ver})")
    name = parts[idx + 1] if idx + 1 < len(parts) else ""
    if not name or name.startswith("."):
        continue
    typ = next((p for p in parts[1:idx] if p in TYPES), "DF")
    (funcs if typ in ("DF", "F", "IF", "WF") else datas).append(name)
c = [f"__attribute__((visibility(\"default\"))) void *{n}(void){{ return 0; }}" for n in funcs]
c += [f"__attribute__((visibility(\"default\"))) unsigned long long {n} = 0;" for n in datas]
open("/tmp/llvm_stub.c", "w").write("\n".join(c) + "\n")
open("/tmp/llvm_stub.map", "w").write(f"{ver} {{ global: *; }};\n")
subprocess.check_call(["gcc", "-shared", "-fPIC",
    "-Wl,--version-script=/tmp/llvm_stub.map", "-Wl,-soname," + out.rsplit("/", 1)[-1],
    "-o", out, "/tmp/llvm_stub.c"])
PY
fi

OUT="$OUTDIR/$(basename "$WHEEL")"
python3 - "$OUT" <<'PY'
import base64, hashlib, sys, zipfile
from pathlib import Path
root = Path(".")
record = next(root.glob("*.dist-info/RECORD"))
rows = []
for f in sorted(root.rglob("*")):
    if not f.is_file() or f == record:
        continue
    h = hashlib.sha256(f.read_bytes()).digest()
    rows.append(f"{f.as_posix()},sha256={base64.urlsafe_b64encode(h).rstrip(b'=').decode()},{f.stat().st_size}")
rows.append(f"{record.as_posix()},,")
record.write_text("\n".join(rows) + "\n")
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(root.rglob("*")):
        if f.is_file():
            z.write(f, f.as_posix())
PY
cp "$OUT" "$WHEEL"
