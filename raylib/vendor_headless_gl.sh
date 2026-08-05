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
        libc.so.6|libm.so.6|libpthread.so.0|librt.so.1|libdl.so.2|ld-linux-x86-64.so.2)
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
