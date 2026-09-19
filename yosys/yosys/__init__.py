import os
import sys

DIR = os.path.join(os.path.dirname(__file__), "install")


def _run(name):
  binary = os.path.join(DIR, "bin", name)
  os.execv(binary, [binary] + sys.argv[1:])


def _run_yosys():
  _run("yosys")


def _run_nextpnr():
  _run("nextpnr-himbaechel")


def smoketest():
  import subprocess
  import tempfile
  from pathlib import Path

  # Pins from Apicula's Primer 25K, Tang Console 60K, and Tang Mega 138K examples.
  devices = [
    ("GW5A-25A", "GW5A-LV25MG121NES", "E2", "G5"),
    ("GW5AT-60B", "GW5AT-LV60PG484AC1/I0", "V22", "B22"),
    ("GW5AST-138C", "GW5AST-LV138PG484AC1/I0", "V22", "P19"),
  ]
  with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    (work / "top.v").write_text(
      "module top(input clk, output led);\n"
      "  reg [7:0] counter = 0;\n"
      "  always @(posedge clk) counter <= counter + 1'b1;\n"
      "  assign led = counter[7];\n"
      "endmodule\n"
    )
    subprocess.run([
      os.path.join(DIR, "bin", "yosys"), "-Q", "-q", "-p",
      "read_verilog top.v; synth_gowin -top top -family gw5a -json synth.json",
    ], cwd=tmp, check=True)
    for family, device, clk_pin, led_pin in devices:
      (work / "top.cst").write_text(
        f'IO_LOC "clk" {clk_pin};\nIO_LOC "led" {led_pin};\n'
        'IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;\n'
        'IO_PORT "led" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8;\n'
      )
      # Apicula 0.33 has no global clock buffers for GW5AT-60B; use fabric routing.
      clock_options = ["--vopt", "disable_gp_clock_routing"] if family == "GW5AT-60B" else []
      subprocess.run([
        os.path.join(DIR, "bin", "nextpnr-himbaechel"), "--quiet",
        "--device", device, "--json", "synth.json", "--write", "pnr.json",
        "--vopt", "cst=top.cst", "--freq", "1",
      ] + clock_options, cwd=tmp, check=True)
      (work / "top.fs").unlink(missing_ok=True)
      subprocess.run([
        sys.executable, "-m", "apycula.gowin_pack", "-d", family,
        "--cpu_as_gpio", "-o", "top.fs", "pnr.json",
      ], cwd=tmp, check=True)
      if (work / "top.fs").stat().st_size == 0:
        raise RuntimeError(f"Empty bitstream for {family}")
      print(f"{family}: synthesis, place and route, and bitstream packing passed")
