# SPDX-License-Identifier: Apache-2.0
"""vivado_program_device and vivado_program_flash, with openFPGALoader."""

load(":parts.bzl", "part_info")
load(":providers.bzl", "OpenXC7BitstreamInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _runfiles_path(f):
    # An external file's short_path starts with ../<repo>/; its runfiles
    # path is <repo>/... . A main-repository file sits under _main/.
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return "_main/" + f.short_path

def _program(ctx, flash):
    if len(ctx.attr.deps) != 1:
        fail("deps must name exactly one vivado_place_and_route")
    bitstream = ctx.attr.deps[0][OpenXC7BitstreamInfo]
    part = part_info(bitstream.part)
    tc = ctx.toolchains[TOOLCHAIN_TYPE].openxc7
    args = ["-c", ctx.attr.cable, "--fpga-part", part.ofl_part]
    if flash:
        args.append("--write-flash")
    args += ctx.attr.extra_args
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = script,
        substitutions = {
            "@@OFL@@": _runfiles_path(tc.openfpgaloader.executable),
            "@@BIT@@": _runfiles_path(bitstream.bitstream),
            "@@ARGS@@": " ".join(["'%s'" % a for a in args]),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [bitstream.bitstream, tc.openfpgaloader.executable] + ctx.files.data,
        transitive_files = tc.openfpgaloader.files,
    )
    return [DefaultInfo(executable = script, runfiles = runfiles)]

_COMMON = {
    "deps": attr.label_list(
        mandatory = True,
        providers = [OpenXC7BitstreamInfo],
        doc = "The one vivado_place_and_route whose bitstream to program.",
    ),
    "cable": attr.string(
        default = "ft232",
        doc = "openFPGALoader's cable, `-c`. Alinx's USB downloaders are " +
              "FT232-based; `openFPGALoader --list-cables` lists the rest.",
    ),
    "extra_args": attr.string_list(doc = "More arguments for openFPGALoader."),
    "data": attr.label_list(allow_files = True, doc = "More runfiles."),
    "prog_daemon": attr.label(doc = "Accepted for rules_vivado compatibility; no effect."),
    "prog_daemon_args": attr.string_list(doc = "Accepted for rules_vivado compatibility; no effect."),
    "_template": attr.label(
        default = "//openxc7/private:program.sh.tpl",
        allow_single_file = True,
    ),
}

def _vivado_program_device_impl(ctx):
    return _program(ctx, flash = False)

vivado_program_device = rule(
    implementation = _vivado_program_device_impl,
    executable = True,
    doc = """Programs a bitstream into the FPGA's configuration memory.

`bazel run` it with the board attached. The configuration is lost at
power off; vivado_program_flash writes it to the board's flash instead.

Example:

```python
vivado_program_device(
    name = "blinky_prog",
    deps = [":blinky_pnr"],
)
```
""",
    attrs = _COMMON,
    toolchains = [TOOLCHAIN_TYPE],
)

def _vivado_program_flash_impl(ctx):
    return _program(ctx, flash = True)

vivado_program_flash = rule(
    implementation = _vivado_program_flash_impl,
    executable = True,
    doc = """Writes a bitstream to the board's SPI configuration flash.

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
""",
    attrs = dict(_COMMON, **{
        "flash_part": attr.string(doc = "Accepted for rules_vivado compatibility; no effect."),
        "size": attr.int(doc = "Accepted for rules_vivado compatibility; no effect."),
        "interface": attr.string(doc = "Accepted for rules_vivado compatibility; no effect."),
        "format": attr.string(doc = "Accepted for rules_vivado compatibility; no effect."),
    }),
    toolchains = [TOOLCHAIN_TYPE],
)
