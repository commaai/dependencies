#!/usr/bin/env python3
import hashlib
import pathlib
import shutil
import sys
import zipfile


ARTIFACT_PRIORITY = (
  "wheels-linux-x86_64",
  "wheels-linux-arm64",
  "wheels-macos",
)


def wheel_digest(path: pathlib.Path) -> str:
  h = hashlib.sha256()
  with path.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
      h.update(chunk)
  return h.hexdigest()


def validate_wheel(path: pathlib.Path) -> str:
  with zipfile.ZipFile(path) as zf:
    bad_file = zf.testzip()
  if bad_file is not None:
    raise RuntimeError(f"{path}: bad zip entry {bad_file}")
  return wheel_digest(path)


def source_priority(artifacts_dir: pathlib.Path, path: pathlib.Path) -> tuple[int, str, str]:
  source = path.relative_to(artifacts_dir).parts[0]
  try:
    index = ARTIFACT_PRIORITY.index(source)
  except ValueError:
    index = len(ARTIFACT_PRIORITY)
  return index, source, str(path)


def main() -> int:
  if len(sys.argv) != 3:
    print("usage: merge_wheel_artifacts.py <artifacts-dir> <dist-dir>", file=sys.stderr)
    return 2

  artifacts_dir = pathlib.Path(sys.argv[1])
  dist_dir = pathlib.Path(sys.argv[2])

  wheels_by_name: dict[str, list[pathlib.Path]] = {}
  for wheel in artifacts_dir.glob("*/*.whl"):
    wheels_by_name.setdefault(wheel.name, []).append(wheel)

  if not wheels_by_name:
    print(f"no wheels found in {artifacts_dir}", file=sys.stderr)
    return 1

  if dist_dir.exists():
    shutil.rmtree(dist_dir)
  dist_dir.mkdir(parents=True)

  for name, wheels in sorted(wheels_by_name.items()):
    checked = [(source_priority(artifacts_dir, wheel), wheel, validate_wheel(wheel)) for wheel in wheels]
    checked.sort(key=lambda item: item[0])

    selected = checked[0]
    if len(checked) > 1:
      sources = ", ".join(f"{item[0][1]}:{item[2][:12]}" for item in checked)
      print(f"{name}: duplicate artifact, using {selected[0][1]} ({sources})")

    shutil.copy2(selected[1], dist_dir / name)

  print(f"merged {len(wheels_by_name)} wheels into {dist_dir}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
