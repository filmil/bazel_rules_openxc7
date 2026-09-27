# SPDX-License-Identifier: Apache-2.0
"""vivado_project: a design, as rules_vivado declares one."""

load(":parts.bzl", "part_info")
load(":providers.bzl", "OpenXC7ProjectInfo")

_HDL = [".v", ".sv", ".vh", ".svh"]

def _vivado_project_impl(ctx):
    part_info(ctx.attr.part)  # fails early on an unsupported part
    for f in ctx.files.srcs:
        if f.extension in ("vhd", "vhdl"):
            fail("%s: VHDL is not supported by the open flow, which reads " % f.short_path +
                 "Verilog and SystemVerilog only")
    if ctx.attr.deps:
        fail("deps (vivado_library) is not supported by rules_openxc7 yet; " +
             "list the sources in srcs")
    return [
        OpenXC7ProjectInfo(
            top_level = ctx.attr.top_level,
            part = ctx.attr.part,
            srcs = depset(ctx.files.srcs),
            hdrs = depset(ctx.files.hdrs),
            xdcs = ctx.files.xdcs,
            defines = ctx.attr.defines,
            include_dirs = ctx.attr.include_dirs,
        ),
        DefaultInfo(files = depset(ctx.files.srcs + ctx.files.xdcs)),
    ]

vivado_project = rule(
    implementation = _vivado_project_impl,
    doc = """A design: sources, constraints, top module and part.

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
""",
    attrs = {
        "top_level": attr.string(mandatory = True, doc = "Top level module name."),
        "part": attr.string(mandatory = True, doc = "The part targeted, e.g. xc7a200tfbg484-2."),
        "srcs": attr.label_list(allow_files = _HDL, doc = "Verilog and SystemVerilog sources."),
        "hdrs": attr.label_list(allow_files = True, doc = "Files the sources include."),
        "xdcs": attr.label_list(allow_files = [".xdc"], doc = "Constraint files, in order."),
        "defines": attr.string_list(doc = "Preprocessor defines, NAME or NAME=VALUE."),
        "include_dirs": attr.string_list(doc = "Include directories, relative to the execution root."),
        "deps": attr.label_list(doc = "Not supported: vivado_library dependencies."),
        "env": attr.string_dict(doc = "Accepted for rules_vivado compatibility; no effect."),
        "mount": attr.string_dict(doc = "Accepted for rules_vivado compatibility; no effect."),
    },
)
