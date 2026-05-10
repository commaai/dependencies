from pathlib import Path

DIR = Path(__file__).resolve().parent
INSTALL_DIR = DIR / "install"
SVG_PATH = INSTALL_DIR / "bootstrap-icons.svg"
TTF_PATH = INSTALL_DIR / "bootstrap-icons.ttf"


def smoketest():
  assert SVG_PATH.is_file()
  assert TTF_PATH.is_file()
