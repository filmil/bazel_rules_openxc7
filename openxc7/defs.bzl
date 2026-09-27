# SPDX-License-Identifier: Apache-2.0
"""Public API of rules_openxc7.

The rules take the names and attributes of
[rules_vivado](https://github.com/filmil/bazel_rules_vivado), so that a
project can move between the two by changing its `load` line:

```python
load("@rules_openxc7//openxc7:defs.bzl", "vivado_project", "vivado_synthesis")
```

The flow is Yosys (`synth_xilinx`), nextpnr (himbaechel xilinx),
Project X-Ray's fasm2frames and xc7frames2bit, and openFPGALoader. See
README.md for what the open flow does not do that Vivado does.
"""

load("//openxc7/private:parts.bzl", "PARTS")
load(
    "//openxc7/private:place_and_route.bzl",
    _vivado_place_and_route = "vivado_place_and_route",
)
load(
    "//openxc7/private:program.bzl",
    _vivado_program_device = "vivado_program_device",
    _vivado_program_flash = "vivado_program_flash",
)
load("//openxc7/private:project.bzl", _vivado_project = "vivado_project")
load(
    "//openxc7/private:providers.bzl",
    _OpenXC7BitstreamInfo = "OpenXC7BitstreamInfo",
    _OpenXC7ProjectInfo = "OpenXC7ProjectInfo",
    _OpenXC7SynthInfo = "OpenXC7SynthInfo",
)
load("//openxc7/private:synthesis.bzl", _vivado_synthesis = "vivado_synthesis")

vivado_project = _vivado_project
vivado_synthesis = _vivado_synthesis
vivado_place_and_route = _vivado_place_and_route
vivado_program_device = _vivado_program_device
vivado_program_flash = _vivado_program_flash

OpenXC7ProjectInfo = _OpenXC7ProjectInfo
OpenXC7SynthInfo = _OpenXC7SynthInfo
OpenXC7BitstreamInfo = _OpenXC7BitstreamInfo

OPENXC7_PARTS = sorted(PARTS.keys())
"""The parts the rules are built and tested for.

Each part needs its die's chip database and its Project X-Ray part
directory. A part not in this list is refused rather than guessed at.
"""
