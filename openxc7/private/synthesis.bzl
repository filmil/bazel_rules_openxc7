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

    available_plugins = getattr(tc, "plugins", [])

    v_srcs = []
    sv_srcs = []
    vhdl_srcs = []
    for f in project.srcs.to_list():
        if f.extension in ("vhd", "vhdl"):
            vhdl_srcs.append(f)
        elif f.extension in ("sv", "svh"):
            sv_srcs.append(f)
        else:
            v_srcs.append(f)

    use_slang = (project.systemverilog_parser == "slang") and len(sv_srcs) > 0
    use_ghdl = len(vhdl_srcs) > 0

    if use_slang and "slang" not in available_plugins:
        fail("The openxc7 toolchain does not provide the 'slang' plugin required for SystemVerilog (slang)")
    if use_ghdl and "ghdl" not in available_plugins:
        fail("The openxc7 toolchain does not provide the 'ghdl' plugin required for VHDL")

    hdrs = project.hdrs.to_list()
    include_dirs = project.include_dirs + sorted({h.dirname: None for h in hdrs}.keys())
    defines = ["-D" + d for d in project.defines]
    inc_dirs = ["-I" + d for d in include_dirs]

    script_lines = []

    # Verilog and SystemVerilog
    if use_slang:
        if v_srcs:
            read_v = ["read_verilog"] + defines + inc_dirs + [f.path for f in v_srcs]
            script_lines.append(" ".join(read_v))
        if sv_srcs:
            read_sv = ["read_slang"] + defines + inc_dirs + [f.path for f in sv_srcs]
            script_lines.append(" ".join(read_sv))
    else:
        verilog_files = v_srcs + sv_srcs
        if verilog_files:
            read_v = ["read_verilog", "-sv"] + defines + inc_dirs + [f.path for f in verilog_files]
            script_lines.append(" ".join(read_v))

    # VHDL
    if vhdl_srcs:
        if not v_srcs and not sv_srcs:
            script_lines.append(" ".join(["ghdl", "--std=08"] + [f.path for f in vhdl_srcs] + ["-e", project.top_level]))
        else:
            script_lines.append(" ".join(["ghdl", "-read", "--std=08"] + [f.path for f in vhdl_srcs]))
            script_lines.append("hierarchy -top %s" % project.top_level)

    script_lines.append("synth_xilinx -flatten -abc9 -arch xc7 -top %s" % project.top_level)
    script_lines.append("write_json %s" % netlist.path)
    script_lines.append("")

    ctx.actions.write(script, "\n".join(script_lines))

    yosys_args = ["-q", "-l", log.path]
    if use_slang:
        yosys_args.extend(["-m", "slang"])
    if use_ghdl:
        yosys_args.extend(["-m", "ghdl"])
    yosys_args.extend(["-s", script.path])

    ctx.actions.run(
        executable = tc.yosys.executable,
        arguments = yosys_args,
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
