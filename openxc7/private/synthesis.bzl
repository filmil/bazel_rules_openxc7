# SPDX-License-Identifier: Apache-2.0
"""vivado_synthesis: Yosys synth_xilinx in place of Vivado's synthesis."""

load(":providers.bzl", "OpenXC7ProjectInfo", "OpenXC7SynthInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _vivado_synthesis_impl(ctx):
    project = ctx.attr.project[OpenXC7ProjectInfo]
    tc = ctx.toolchains[TOOLCHAIN_TYPE].openxc7
    netlist = ctx.actions.declare_file(ctx.label.name + ".json")
    log = ctx.actions.declare_file(ctx.label.name + ".log")
    script = ctx.actions.declare_file(ctx.label.name + ".ys")

    hdrs = project.hdrs.to_list()
    include_dirs = project.include_dirs + sorted({h.dirname: None for h in hdrs}.keys())
    read = ["read_verilog", "-sv"]
    read += ["-D" + d for d in project.defines]
    read += ["-I" + d for d in include_dirs]
    read += [f.path for f in project.srcs.to_list()]
    ctx.actions.write(script, "\n".join([
        " ".join(read),
        "synth_xilinx -flatten -abc9 -arch xc7 -top %s" % project.top_level,
        "write_json %s" % netlist.path,
        "",
    ]))
    ctx.actions.run(
        executable = tc.yosys.executable,
        arguments = ["-q", "-l", log.path, "-s", script.path],
        inputs = depset([script] + hdrs, transitive = [project.srcs]),
        tools = [tc.yosys.files],
        outputs = [netlist, log],
        mnemonic = "YosysSynth",
        progress_message = "Synthesising %s with Yosys" % project.top_level,
    )
    return [
        OpenXC7SynthInfo(project = project, netlist = netlist),
        DefaultInfo(files = depset([netlist])),
        OutputGroupInfo(log = depset([log])),
    ]

vivado_synthesis = rule(
    implementation = _vivado_synthesis_impl,
    doc = """Synthesises a vivado_project with Yosys (`synth_xilinx`).

The output is Yosys's JSON netlist, which vivado_place_and_route reads.
The `log` output group holds Yosys's log.

Example:

```python
vivado_synthesis(
    name = "blinky_synth",
    project = ":blinky",
)
```
""",
    attrs = {
        "project": attr.label(
            mandatory = True,
            providers = [OpenXC7ProjectInfo],
            doc = "The vivado_project to synthesise.",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
