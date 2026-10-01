# SPDX-License-Identifier: Apache-2.0
"""Providers passed between the rules."""

OpenXC7ProjectInfo = provider(
    doc = "A design: its sources, constraints and target part.",
    fields = {
        "top_level": "The top-level module name.",
        "part": "The Xilinx part, such as xc7a200tfbg484-2.",
        "srcs": "depset of Verilog and SystemVerilog sources.",
        "hdrs": "depset of included files.",
        "xdcs": "list of XDC files, in order.",
        "defines": "list of preprocessor defines, NAME or NAME=VALUE.",
        "include_dirs": "list of include directories.",
        "systemverilog_parser": "Parser for SystemVerilog: 'yosys' or 'slang'.",
    },
)

OpenXC7SynthInfo = provider(
    doc = "The result of synthesis.",
    fields = {
        "project": "The OpenXC7ProjectInfo synthesised.",
        "netlist": "The Yosys JSON netlist.",
    },
)

OpenXC7BitstreamInfo = provider(
    doc = "The result of place, route and bitstream generation.",
    fields = {
        "part": "The Xilinx part.",
        "bitstream": "The .bit file.",
    },
)
