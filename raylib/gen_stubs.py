#!/usr/bin/env python3
"""Write type stubs into a built raylib_nb package.

raylib_nb re-exports its native backend module through globals().update(), which
type checkers can't follow, so the stubs are generated from the backend itself.
"""
import subprocess
import sys
import tempfile
from enum import IntEnum
from pathlib import Path

import raylib_nb
from raylib_nb import colors, enums
from raylib_nb._backend import native


def main(target: Path) -> None:
  with tempfile.TemporaryDirectory() as tmp:
    subprocess.check_call([sys.executable, "-m", "nanobind.stubgen", "-q", "-r", "-m", native.__name__, "-O", tmp])
    out = Path(tmp) / native.__name__.rpartition(".")[2]
    # the backend's stubs become raylib_nb's own: rl.Color, rl.cpu, ...
    init = (out / "__init__.pyi").read_text().replace(native.__name__, "raylib_nb")
    cpu = (out / "cpu.pyi").read_text().replace(native.__name__, "raylib_nb")

  lines = [""]
  lines += [f"{name}: Color" for name in dir(colors) if isinstance(getattr(colors, name), native.Color)]
  enum_types = [e for e in vars(enums).values() if isinstance(e, type) and issubclass(e, IntEnum) and e is not IntEnum]
  lines += [f"from raylib_nb.enums import {e.__name__} as {e.__name__}" for e in enum_types]
  for e in enum_types:
    lines += [f"{name} = {e.__name__}.{name}" for name, member in e.__members__.items() if getattr(raylib_nb, name, None) is member]

  (target / "__init__.pyi").write_text(init + "\n".join(lines) + "\n")
  (target / "cpu.pyi").write_text(cpu)
  (target / "py.typed").touch()


if __name__ == "__main__":
  main(Path(sys.argv[1]))
