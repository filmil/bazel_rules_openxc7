[![Test](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/test.yml/badge.svg)](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/test.yml)
[![Tag and Release](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/tag-and-release.yml/badge.svg)](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/tag-and-release.yml)
[![Publish on Bazel Central Registry](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/publish-bcr.yml/badge.svg)](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/publish-bcr.yml)
[![Publish to my Bazel registry](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/publish.yml/badge.svg)](https://github.com/filmil/bazel_rules_openxc7/actions/workflows/publish.yml)

# bazel_rules_openxc7

Bazel rules for AMD/Xilinx 7-series FPGAs, built with the open toolchain
instead of Vivado:

* [Yosys](https://github.com/YosysHQ/yosys) synthesises, with `synth_xilinx`;
* [openXC7's nextpnr](https://github.com/openXC7/nextpnr), the himbaechel
  Xilinx architecture, places and routes, against the
  [Project X-Ray database](https://github.com/openXC7/prjxray-db);
* [fpga-assembler](https://github.com/lromor/fpga-assembler) turns the
  result into a bitstream;
* [openFPGALoader](https://github.com/trabucayre/openFPGALoader) programs
  the part and its configuration flash.

The rules take the names and attributes of
[rules_vivado](https://github.com/filmil/bazel_rules_vivado), so a project
can move between the two by changing its `load` line.
The first part is the xc7a200tfbg484-2, on the Alinx AX7A200B.

**Status:** steps 1 and 2 of the plan below. Verilog and SystemVerilog
build to a bitstream for the xc7a200tfbg484-2 with prebuilt tools, and
the bitstream is programmed with openFPGALoader. Nothing has been tried on
a board yet.

## Using it

```python
# MODULE.bazel
bazel_dep(name = "rules_openxc7", version = "<version>")
```

```python
# BUILD.bazel
load(
    "@rules_openxc7//openxc7:defs.bzl",
    "vivado_place_and_route",
    "vivado_program_device",
    "vivado_project",
    "vivado_synthesis",
)

vivado_project(
    name = "blinky",
    srcs = ["blinky.sv"],
    part = "xc7a200tfbg484-2",
    top_level = "up_counter",
    xdcs = ["blinky.xdc"],
)

vivado_synthesis(name = "blinky_synth", project = ":blinky")

vivado_place_and_route(name = "blinky_pnr", synthesis = ":blinky_synth")

vivado_program_device(name = "blinky_prog", deps = [":blinky_pnr"])
```

```sh
bazel build //:blinky_pnr    # -> bazel-bin/blinky_pnr.bit
bazel run //:blinky_prog     # program the FPGA; -- passes more flags to openFPGALoader
```

`tests/blinky/` is this, on rules_vivado's own blinky and Alinx
AX7A200B constraints, unchanged.

### Against rules_vivado

| rules_vivado | Here |
|---|---|
| `vivado_project` | Same attributes. VHDL sources and `deps` (vivado_library) are refused; `env` and `mount` are accepted and do nothing. |
| `vivado_synthesis` | Same. Yosys `synth_xilinx`; the output is a JSON netlist, not a DCP. |
| `vivado_place_and_route` | Same. nextpnr, then fasm2frames and xc7frames2bit, to a `.bit`. |
| `vivado_program_device` | Same, plus `cable` (default `ft232`). `prog_daemon` has no effect: openFPGALoader talks to the cable directly. |
| `vivado_program_flash` | Same, plus `cable`. `flash_part`, `size`, `interface` and `format` have no effect: openFPGALoader identifies the flash itself. |
| the rest | Not provided: simulation, IP, ILA, the GUI. |

### Constraints

nextpnr reads a subset of XDC: `set_property` on `get_ports` and
`get_cells`, and `create_clock`. It rejects `[all_inputs]` and
`[all_outputs]`, and it aborts on a braced list of several ports,
`[get_ports {clk reset}]` (`Assertion failure: str.back() == '}'`).
So `vivado_place_and_route` rewrites the design's XDC first
(`openxc7/private/xdc_translate.py`): every port selector becomes one
command per port, from the synthesised netlist, with wildcards matched.
Other commands pass through; nextpnr warns about those it ignores. The
translated file is the `xdc` output group of the target.

### Reproducible bitstreams

xc7frames2bit writes the wall clock and the whole path of its input into
the `.bit` header. The rules set the date and time to fixed values and
keep only the input's base name, so the same design gives the same bytes
in every build: fastbuild and `-c opt` bitstreams of `tests/blinky`
compare equal.

## Plan

1. The repository scaffold, per the
   [ai-coding-sop](https://github.com/filmil/ai-coding-sop): this.
2. A working flow from Verilog to a `.bit` for the xc7a200tfbg484-2, on
   prebuilt tools pinned by sha256.
3. The same tools built from source by Bazel.
4. This repository's own prebuilt tools, published by its release workflow
   from step 3, which step 2 then fetches.

Steps 2 and 3 are two ways to get the same tools, and a build setting
chooses between them:

```
--@rules_openxc7//:tools=prebuilt   # the default: download, by sha256
--@rules_openxc7//:tools=source     # build every tool with Bazel (step 3; not in yet)
```

The prebuilt tools today come from two bundles, pinned in `MODULE.bazel`
to their 2026-09-27 releases:

* [FPGAwars tools-openxc7](https://github.com/FPGAwars/tools-openxc7):
  openXC7's nextpnr (himbaechel xilinx) e860c9c8, Project X-Ray's tools
  and database (prjxray-db a90f27c1), and chip databases;
* [YosysHQ OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build):
  Yosys and openFPGALoader.

Both are Linux x86-64 only, and both prune old releases in time, which is
why step 4 publishes this repository's own.

## What the open flow does not do

The open 7-series toolchain is not Vivado, and a design that works with one
will not always work with the other. As of openXC7's nextpnr 1.0.0
(September 2026):

* No Vivado IP: nothing generated or encrypted by Vivado, so no MIG, no
  PCIe core and no block designs.
* Timing analysis is rudimentary, and most XDC timing commands beyond
  `create_clock` are ignored with a warning.
* Open defects include MMCMs that do not lock, IDDR that does not capture on
  silicon, and DSP48 and LUTRAM packing gaps; the openXC7 nextpnr issue list
  is the current record.

## Building

Nothing is installed beyond `bazelisk`. The C++ toolchain is LLVM with a
pinned sysroot, from `MODULE.bazel`.

```sh
bazel build //...
bazel test //...
cd integration && bazel test //...    # what the registry presubmit runs
bazel run //docs:update_docs          # after changing a .bzl file
bazel run //tools:buildifier               # format BUILD and .bzl files
```

## Documentation

* [`docs/defs.md`](docs/defs.md): the public API in
  `//openxc7:defs.bzl`, generated by stardoc.
