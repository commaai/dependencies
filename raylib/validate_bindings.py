import ast
import os
import re


def _read_python_assignments(path):
  assignments = {}
  with open(path, "r") as f:
    tree = ast.parse(f.read())
  for node in tree.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
      try:
        assignments[node.targets[0].id] = ast.literal_eval(node.value)
      except ValueError:
        pass
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
      try:
        assignments[node.target.id] = ast.literal_eval(node.value)
      except ValueError:
        pass
  return assignments


def _read_python_enums(path):
  enums = {}
  with open(path, "r") as f:
    tree = ast.parse(f.read())
  for node in tree.body:
    if not isinstance(node, ast.ClassDef):
      continue
    values = {}
    for stmt in node.body:
      if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1 and isinstance(stmt.targets[0], ast.Name):
        values[stmt.targets[0].id] = ast.literal_eval(stmt.value)
    enums[node.name] = values
  return enums


def _strip_c_comments(text):
  text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
  return re.sub(r'//.*', '', text)


def _eval_c_enum_expr(expr, symbols):
  if not re.fullmatch(r'[A-Za-z0-9_ xXa-fA-F|&~!<>()+\-*/]+', expr):
    raise ValueError(expr)
  return int(eval(expr.replace("!", " not "), {"__builtins__": {}}, symbols))


def _read_c_enums(header_texts):
  symbols = {}
  enums = {}
  for text in header_texts:
    for match in re.finditer(r'typedef\s+enum(?:\s+\w+)?\s*\{(.*?)\}\s*(\w+)\s*;', text, re.S):
      body, enum_name = match.groups()
      value = -1
      values = {}
      for raw_item in body.split(','):
        item = raw_item.strip()
        if not item:
          continue
        if '=' in item:
          name, expr = [part.strip() for part in item.split('=', 1)]
          value = _eval_c_enum_expr(expr, symbols)
        else:
          name = item
          value += 1
        if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
          values[name] = value
          symbols[name] = value
      enums[enum_name] = values
  return enums


def validate_static_bindings(package_dir, include_dir):
  headers = {}
  for name in ("raylib.h", "rlgl.h", "raygui.h"):
    with open(os.path.join(include_dir, name), "r") as f:
      headers[name] = _strip_c_comments(f.read())

  defines = _read_python_assignments(os.path.join(package_dir, "defines.py"))
  for header_name, names in (
    ("raylib.h", ("RAYLIB_VERSION_MAJOR", "RAYLIB_VERSION_MINOR", "RAYLIB_VERSION_PATCH", "RAYLIB_VERSION")),
    ("rlgl.h", ("RLGL_VERSION",)),
  ):
    text = headers[header_name]
    for name in names:
      match = re.search(rf"#define\s+{name}\s+(.+)", text)
      if not match:
        continue
      expected = match.group(1).strip().strip('"')
      actual = str(defines[name])
      if actual != expected:
        raise ValueError(f"{name} in defines.py is {actual}, expected {expected}")

  py_enums = _read_python_enums(os.path.join(package_dir, "enums.py"))
  c_enums = _read_c_enums((headers["raylib.h"], headers["raygui.h"]))
  missing_classes = sorted(set(c_enums) - set(py_enums) - {"bool"})
  extra_classes = sorted(set(py_enums) - set(c_enums))
  if missing_classes or extra_classes:
    raise ValueError(f"enums.py drift: missing={missing_classes}, extra={extra_classes}")
  for enum_name in sorted(set(c_enums) & set(py_enums)):
    if py_enums[enum_name] != c_enums[enum_name]:
      raise ValueError(f"enums.py drift in {enum_name}")


if __name__ == "__main__":
  root = os.path.dirname(os.path.abspath(__file__))
  validate_static_bindings(os.path.join(root, "raylib"), os.path.join(root, "raylib", "install", "include"))
