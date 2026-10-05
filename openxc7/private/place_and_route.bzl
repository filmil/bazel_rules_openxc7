# SPDX-License-Identifier: Apache-2.0
"""vivado_place_and_route: nextpnr and Project X-Ray in place of Vivado's."""

load(":parts.bzl", "part_info")
load(":providers.bzl", "OpenXC7BitstreamInfo", "OpenXC7SynthInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _vivado_place_and_route_impl(ctx):
    synth = ctx.attr.synthesis[OpenXC7SynthInfo]
    project = synth.project
    part = part_info(project.part)
    tc = ctx.toolchains[TOOLCHAIN_TYPE].openxc7
    if part.die not in tc.chipdbs or project.part not in tc.parts:
        fail("the toolchain has no chip database or part data for %s" % project.part)
    chipdb = tc.chipdbs[part.die]
    part_data = tc.parts[project.part]
    name = ctx.label.name

    def out(ext):
        return ctx.actions.declare_file("%s.%s" % (name, ext))

    xdc, fasm, frames, raw_bit, bit, log = (
        out("xdc"),
        out("fasm"),
        out("frames"),
        out("raw.bit"),
        out("bit"),
        out("log"),
    )

    # nextpnr reads a subset of XDC; rewrite the design's XDC into it.
    ctx.actions.run(
        executable = ctx.executable._xdc_translate,
        arguments = [
            "--netlist",
            synth.netlist.path,
            "--top",
            project.top_level,
            "--out",
            xdc.path,
        ] + [f.path for f in project.xdcs],
        inputs = [synth.netlist] + project.xdcs,
        outputs = [xdc],
        mnemonic = "XdcTranslate",
        progress_message = "Translating the constraints of %s for nextpnr" % project.top_level,
    )
    ctx.actions.run(
        executable = tc.nextpnr.executable,
        arguments = [
            "--device",
            project.part,
            "--chipdb",
            chipdb.path,
            "--json",
            synth.netlist.path,
            "-o",
            "xdc=" + xdc.path,
            "-o",
            "fasm=" + fasm.path,
            "--log",
            log.path,
            "--quiet",
            # As Vivado's route_design: a timing violation is reported in
            # the log, not a failed build. nextpnr-xilinx does not fix hold
            # time, so without this a 0.02 ns hold miss into a block RAM
            # fails a design that Vivado routes.
            "--timing-allow-fail",
        ],
        inputs = [synth.netlist, xdc, chipdb],
        tools = [tc.nextpnr.files],
        outputs = [fasm, log],
        mnemonic = "NextpnrXilinx",
        progress_message = "Placing and routing %s with nextpnr" % project.top_level,
    )
    ctx.actions.run(
        executable = tc.fasm2frames.executable,
        arguments = [
            "--db-root",
            part_data.db_root,
            "--part",
            project.part,
            fasm.path,
            frames.path,
        ],
        inputs = depset([fasm], transitive = [tc.prjxray_db]),
        tools = [tc.fasm2frames.files],
        outputs = [frames],
        mnemonic = "Fasm2Frames",
        progress_message = "Assembling the frames of %s" % project.top_level,
    )
    ctx.actions.run(
        executable = tc.xc7frames2bit.executable,
        arguments = [
            "--part_file",
            part_data.part_yaml.path,
            "--part_name",
            project.part,
            "--frm_file",
            frames.path,
            "--output_file",
            raw_bit.path,
        ],
        inputs = [frames, part_data.part_yaml],
        tools = [tc.xc7frames2bit.files],
        outputs = [raw_bit],
        mnemonic = "Frames2Bit",
        progress_message = "Writing the bitstream of %s" % project.top_level,
    )
    ctx.actions.run(
        executable = ctx.executable._bit_normalize,
        arguments = [raw_bit.path, bit.path],
        inputs = [raw_bit],
        outputs = [bit],
        mnemonic = "BitNormalize",
        progress_message = "Fixing the header date of %s" % bit.short_path,
    )
    return [
        OpenXC7BitstreamInfo(part = project.part, bitstream = bit),
        DefaultInfo(files = depset([bit])),
        OutputGroupInfo(
            log = depset([log]),
            fasm = depset([fasm]),
            frames = depset([frames]),
            xdc = depset([xdc]),
        ),
    ]

vivado_place_and_route = rule(
    implementation = _vivado_place_and_route_impl,
    doc = """Places, routes and writes the bitstream of a vivado_synthesis.

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
""",
    attrs = {
        "synthesis": attr.label(
            mandatory = True,
            providers = [OpenXC7SynthInfo],
            doc = "The vivado_synthesis to place and route.",
        ),
        "env": attr.string_dict(doc = "Accepted for rules_vivado compatibility; no effect."),
        "mount": attr.string_dict(doc = "Accepted for rules_vivado compatibility; no effect."),
        "_xdc_translate": attr.label(
            default = "//openxc7/private:xdc_translate",
            executable = True,
            cfg = "exec",
        ),
        "_bit_normalize": attr.label(
            default = "//openxc7/private:bit_normalize",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
