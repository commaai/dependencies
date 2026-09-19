# Gowin 5-series toolchain

`comma-deps-yosys` provides `yosys` and `nextpnr-himbaechel`, with
`gowin_pack` and `gowin_unpack` supplied by the pinned `apycula` dependency.
It targets Linux x86_64/aarch64 and macOS arm64, like the other packages here.

The build pins Yosys 0.63, nextpnr commit
`3e53a0bf44d13c0de603dd089a323ea85d67d4ef`, and Apicula 0.33. Only the
GW5A-25A, GW5AT-60B, and GW5AST-138C nextpnr databases are included.
Support for individual primitives follows [Apicula](https://github.com/YosysHQ/apicula/wiki/Supported-primitives);
this does not imply support for every Gowin 5-series part or feature.

Build and install locally:

```sh
./setup.sh
uv build --package comma-deps-yosys --wheel
uv pip install dist/comma_deps_yosys-*.whl
python -c 'import yosys; yosys.smoketest()'
```

For a GW5A-25A (Tang Primer 25K), with your own `top.v` and board pin
constraints in `top.cst`:

```sh
yosys -p 'read_verilog top.v; synth_gowin -top top -family gw5a -json synth.json'
nextpnr-himbaechel --device GW5A-LV25MG121NES --json synth.json \
  --write pnr.json --vopt cst=top.cst --freq 50
gowin_pack -d GW5A-25A --cpu_as_gpio -o top.fs pnr.json
```

Use the exact device/package and clock frequency for your design. The other
included families use `GW5AT-LV60PG484AC1/I0` / `GW5AT-60B` and
`GW5AST-LV138PG484AC1/I0` / `GW5AST-138C` for the nextpnr device / packer family.
Examples and pin constraints are available in
[Apicula's GW5A examples](https://github.com/YosysHQ/apicula/tree/master/examples/gw5a).
Programming hardware requires a separate programmer such as openFPGALoader.

The smoke test synthesizes an 8-bit counter and places, routes, and packs it
for all three included families. Apicula 0.33 has no global clock buffers for
GW5AT-60B, so that test uses `--vopt disable_gp_clock_routing` and a 1 MHz
timing target. Check clock routing and timing for your actual design.
The test does not program hardware.
