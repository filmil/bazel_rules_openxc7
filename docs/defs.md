<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API of rules_openxc7.

The rules take the names and attributes of
[rules_vivado](https://github.com/filmil/bazel_rules_vivado), so that a
project can move between the two by changing its `load` line:

```python
load("@rules_openxc7//openxc7:defs.bzl", "vivado_project", "vivado_synthesis")
```

The flow is Yosys (`synth_xilinx`), nextpnr (himbaechel xilinx),
Project X-Ray's fasm2frames and xc7frames2bit, and openFPGALoader. See
README.md for what the open flow does not do that Vivado does.

<a id="vivado_place_and_route"></a>

## vivado_place_and_route

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "vivado_place_and_route")

vivado_place_and_route(<a href="#vivado_place_and_route-name">name</a>, <a href="#vivado_place_and_route-env">env</a>, <a href="#vivado_place_and_route-mount">mount</a>, <a href="#vivado_place_and_route-synthesis">synthesis</a>)
</pre>

Places, routes and writes the bitstream of a vivado_synthesis.

nextpnr (himbaechel xilinx) places and routes against the part's chip
database, Project X-Ray's fasm2frames and xc7frames2bit write the .bit,
and the header's date and time are fixed so that the file is
reproducible. The design's XDC is first rewritten into the subset
nextpnr reads (see xdc_translate.py). Output groups: `log`, `fasm`,
`frames` and `xdc` (the translated constraints).

`env` and `mount` configure Vivado's container in rules_vivado; they are
accepted here and have no effect.

Example:

```python
vivado_place_and_route(
    name = "blinky_pnr",
    synthesis = ":blinky_synth",
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vivado_place_and_route-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vivado_place_and_route-env"></a>env |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="vivado_place_and_route-mount"></a>mount |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="vivado_place_and_route-synthesis"></a>synthesis |  The vivado_synthesis to place and route.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="vivado_program_device"></a>

## vivado_program_device

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "vivado_program_device")

vivado_program_device(<a href="#vivado_program_device-name">name</a>, <a href="#vivado_program_device-deps">deps</a>, <a href="#vivado_program_device-data">data</a>, <a href="#vivado_program_device-cable">cable</a>, <a href="#vivado_program_device-extra_args">extra_args</a>, <a href="#vivado_program_device-prog_daemon">prog_daemon</a>, <a href="#vivado_program_device-prog_daemon_args">prog_daemon_args</a>)
</pre>

Programs a bitstream into the FPGA's configuration memory.

`bazel run` it with the board attached. The configuration is lost at
power off; vivado_program_flash writes it to the board's flash instead.

Example:

```python
vivado_program_device(
    name = "blinky_prog",
    deps = [":blinky_pnr"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vivado_program_device-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vivado_program_device-deps"></a>deps |  The one vivado_place_and_route whose bitstream to program.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="vivado_program_device-data"></a>data |  More runfiles.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vivado_program_device-cable"></a>cable |  openFPGALoader's cable, `-c`. Alinx's USB downloaders are FT232-based; `openFPGALoader --list-cables` lists the rest.   | String | optional |  `"ft232"`  |
| <a id="vivado_program_device-extra_args"></a>extra_args |  More arguments for openFPGALoader.   | List of strings | optional |  `[]`  |
| <a id="vivado_program_device-prog_daemon"></a>prog_daemon |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vivado_program_device-prog_daemon_args"></a>prog_daemon_args |  Accepted for rules_vivado compatibility; no effect.   | List of strings | optional |  `[]`  |


<a id="vivado_program_flash"></a>

## vivado_program_flash

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "vivado_program_flash")

vivado_program_flash(<a href="#vivado_program_flash-name">name</a>, <a href="#vivado_program_flash-deps">deps</a>, <a href="#vivado_program_flash-data">data</a>, <a href="#vivado_program_flash-cable">cable</a>, <a href="#vivado_program_flash-extra_args">extra_args</a>, <a href="#vivado_program_flash-flash_part">flash_part</a>, <a href="#vivado_program_flash-format">format</a>, <a href="#vivado_program_flash-interface">interface</a>,
                     <a href="#vivado_program_flash-prog_daemon">prog_daemon</a>, <a href="#vivado_program_flash-prog_daemon_args">prog_daemon_args</a>, <a href="#vivado_program_flash-size">size</a>)
</pre>

Writes a bitstream to the board's SPI configuration flash.

`bazel run` it with the board attached. openFPGALoader loads its own
SPI-over-JTAG bridge into the FPGA, identifies the flash by its JEDEC id,
and writes the bitstream. rules_vivado's `flash_part`, `size`,
`interface` and `format` describe the flash to Vivado; openFPGALoader
finds these itself, so they are accepted and have no effect.

Example:

```python
vivado_program_flash(
    name = "blinky_flash",
    deps = [":blinky_pnr"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vivado_program_flash-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vivado_program_flash-deps"></a>deps |  The one vivado_place_and_route whose bitstream to program.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="vivado_program_flash-data"></a>data |  More runfiles.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vivado_program_flash-cable"></a>cable |  openFPGALoader's cable, `-c`. Alinx's USB downloaders are FT232-based; `openFPGALoader --list-cables` lists the rest.   | String | optional |  `"ft232"`  |
| <a id="vivado_program_flash-extra_args"></a>extra_args |  More arguments for openFPGALoader.   | List of strings | optional |  `[]`  |
| <a id="vivado_program_flash-flash_part"></a>flash_part |  Accepted for rules_vivado compatibility; no effect.   | String | optional |  `""`  |
| <a id="vivado_program_flash-format"></a>format |  Accepted for rules_vivado compatibility; no effect.   | String | optional |  `""`  |
| <a id="vivado_program_flash-interface"></a>interface |  Accepted for rules_vivado compatibility; no effect.   | String | optional |  `""`  |
| <a id="vivado_program_flash-prog_daemon"></a>prog_daemon |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vivado_program_flash-prog_daemon_args"></a>prog_daemon_args |  Accepted for rules_vivado compatibility; no effect.   | List of strings | optional |  `[]`  |
| <a id="vivado_program_flash-size"></a>size |  Accepted for rules_vivado compatibility; no effect.   | Integer | optional |  `0`  |


<a id="vivado_project"></a>

## vivado_project

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "vivado_project")

vivado_project(<a href="#vivado_project-name">name</a>, <a href="#vivado_project-deps">deps</a>, <a href="#vivado_project-srcs">srcs</a>, <a href="#vivado_project-hdrs">hdrs</a>, <a href="#vivado_project-defines">defines</a>, <a href="#vivado_project-env">env</a>, <a href="#vivado_project-include_dirs">include_dirs</a>, <a href="#vivado_project-mount">mount</a>, <a href="#vivado_project-part">part</a>, <a href="#vivado_project-top_level">top_level</a>, <a href="#vivado_project-xdcs">xdcs</a>)
</pre>

A design: sources, constraints, top module and part.

Takes rules_vivado's attributes. `deps` (vivado_library) is refused, and
`env` and `mount`, which configure Vivado's container, are accepted and
have no effect.

Example:

```python
vivado_project(
    name = "blinky",
    srcs = ["blinky.sv"],
    part = "xc7a200tfbg484-2",
    top_level = "up_counter",
    xdcs = ["blinky.xdc"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vivado_project-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vivado_project-deps"></a>deps |  Not supported: vivado_library dependencies.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vivado_project-srcs"></a>srcs |  Verilog and SystemVerilog sources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vivado_project-hdrs"></a>hdrs |  Files the sources include.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vivado_project-defines"></a>defines |  Preprocessor defines, NAME or NAME=VALUE.   | List of strings | optional |  `[]`  |
| <a id="vivado_project-env"></a>env |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="vivado_project-include_dirs"></a>include_dirs |  Include directories, relative to the execution root.   | List of strings | optional |  `[]`  |
| <a id="vivado_project-mount"></a>mount |  Accepted for rules_vivado compatibility; no effect.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="vivado_project-part"></a>part |  The part targeted, e.g. xc7a200tfbg484-2.   | String | required |  |
| <a id="vivado_project-top_level"></a>top_level |  Top level module name.   | String | required |  |
| <a id="vivado_project-xdcs"></a>xdcs |  Constraint files, in order.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="vivado_synthesis"></a>

## vivado_synthesis

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "vivado_synthesis")

vivado_synthesis(<a href="#vivado_synthesis-name">name</a>, <a href="#vivado_synthesis-project">project</a>)
</pre>

Synthesises a vivado_project with Yosys (`synth_xilinx`).

The output is Yosys's JSON netlist, which vivado_place_and_route reads.
The `log` output group holds Yosys's log.

Example:

```python
vivado_synthesis(
    name = "blinky_synth",
    project = ":blinky",
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vivado_synthesis-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vivado_synthesis-project"></a>project |  The vivado_project to synthesise.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="OpenXC7BitstreamInfo"></a>

## OpenXC7BitstreamInfo

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "OpenXC7BitstreamInfo")

OpenXC7BitstreamInfo(<a href="#OpenXC7BitstreamInfo-part">part</a>, <a href="#OpenXC7BitstreamInfo-bitstream">bitstream</a>)
</pre>

The result of place, route and bitstream generation.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="OpenXC7BitstreamInfo-part"></a>part |  The Xilinx part.    |
| <a id="OpenXC7BitstreamInfo-bitstream"></a>bitstream |  The .bit file.    |


<a id="OpenXC7ProjectInfo"></a>

## OpenXC7ProjectInfo

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "OpenXC7ProjectInfo")

OpenXC7ProjectInfo(<a href="#OpenXC7ProjectInfo-top_level">top_level</a>, <a href="#OpenXC7ProjectInfo-part">part</a>, <a href="#OpenXC7ProjectInfo-srcs">srcs</a>, <a href="#OpenXC7ProjectInfo-hdrs">hdrs</a>, <a href="#OpenXC7ProjectInfo-xdcs">xdcs</a>, <a href="#OpenXC7ProjectInfo-defines">defines</a>, <a href="#OpenXC7ProjectInfo-include_dirs">include_dirs</a>)
</pre>

A design: its sources, constraints and target part.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="OpenXC7ProjectInfo-top_level"></a>top_level |  The top-level module name.    |
| <a id="OpenXC7ProjectInfo-part"></a>part |  The Xilinx part, such as xc7a200tfbg484-2.    |
| <a id="OpenXC7ProjectInfo-srcs"></a>srcs |  depset of Verilog and SystemVerilog sources.    |
| <a id="OpenXC7ProjectInfo-hdrs"></a>hdrs |  depset of included files.    |
| <a id="OpenXC7ProjectInfo-xdcs"></a>xdcs |  list of XDC files, in order.    |
| <a id="OpenXC7ProjectInfo-defines"></a>defines |  list of preprocessor defines, NAME or NAME=VALUE.    |
| <a id="OpenXC7ProjectInfo-include_dirs"></a>include_dirs |  list of include directories.    |


<a id="OpenXC7SynthInfo"></a>

## OpenXC7SynthInfo

<pre>
load("@rules_openxc7//openxc7:defs.bzl", "OpenXC7SynthInfo")

OpenXC7SynthInfo(<a href="#OpenXC7SynthInfo-project">project</a>, <a href="#OpenXC7SynthInfo-netlist">netlist</a>)
</pre>

The result of synthesis.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="OpenXC7SynthInfo-project"></a>project |  The OpenXC7ProjectInfo synthesised.    |
| <a id="OpenXC7SynthInfo-netlist"></a>netlist |  The Yosys JSON netlist.    |


