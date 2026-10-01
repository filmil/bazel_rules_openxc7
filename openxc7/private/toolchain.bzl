# SPDX-License-Identifier: Apache-2.0
"""The openxc7 toolchain: every tool the rules run, from one place.

A toolchain target names the tools, prebuilt or built from source; the
rules ask for `@rules_openxc7//openxc7/toolchains:toolchain_type` and
never name a tool themselves. `--@rules_openxc7//:tools` chooses which
registered toolchain applies.
"""

TOOLCHAIN_TYPE = "@rules_openxc7//openxc7/toolchains:toolchain_type"

def _tool(attr, files):
    return struct(
        executable = attr.files_to_run.executable,
        files = depset(files),
    )

def _openxc7_toolchain_impl(ctx):
    chipdbs = {die: f for f, die in [
        (t.files.to_list()[0], die)
        for t, die in ctx.attr.chipdbs.items()
    ]}
    parts = {}
    for t, part in ctx.attr.part_files.items():
        part_yaml = t.files.to_list()[0]
        parts[part] = struct(
            part_yaml = part_yaml,
            # <db>/<family>/<part>/part.yaml: the root fasm2frames wants is
            # the family directory, two levels up.
            db_root = part_yaml.dirname.rsplit("/", 1)[0],
        )
    return [platform_common.ToolchainInfo(openxc7 = struct(
        yosys = _tool(ctx.attr.yosys, ctx.files.yosys_files),
        nextpnr = _tool(ctx.attr.nextpnr, ctx.files.nextpnr_files),
        fasm2frames = _tool(ctx.attr.fasm2frames, ctx.files.fasm2frames_files),
        xc7frames2bit = _tool(ctx.attr.xc7frames2bit, ctx.files.xc7frames2bit_files),
        openfpgaloader = _tool(ctx.attr.openfpgaloader, ctx.files.openfpgaloader_files),
        chipdbs = chipdbs,
        parts = parts,
        prjxray_db = depset(ctx.files.prjxray_db),
        # The tools' whole directories, for runners that must not expose
        # the tools' individual files (see //vivado/private:runner.bzl).
        trees = depset(ctx.files.trees),
        plugins = ctx.attr.plugins,
    ))]

_EXE = dict(executable = True, cfg = "exec", allow_files = True)

openxc7_toolchain = rule(
    implementation = _openxc7_toolchain_impl,
    doc = "The tools and databases of the open 7-series flow.",
    attrs = {
        "yosys": attr.label(mandatory = True, doc = "Yosys.", **_EXE),
        "yosys_files": attr.label_list(allow_files = True, doc = "Everything Yosys reads."),
        "nextpnr": attr.label(mandatory = True, doc = "nextpnr, himbaechel xilinx.", **_EXE),
        "nextpnr_files": attr.label_list(allow_files = True, doc = "Everything nextpnr reads, chip databases aside."),
        "fasm2frames": attr.label(mandatory = True, doc = "Project X-Ray's fasm2frames.", **_EXE),
        "fasm2frames_files": attr.label_list(allow_files = True, doc = "Everything fasm2frames reads, the database aside."),
        "xc7frames2bit": attr.label(mandatory = True, doc = "Project X-Ray's xc7frames2bit.", **_EXE),
        "xc7frames2bit_files": attr.label_list(allow_files = True, doc = "Everything xc7frames2bit reads, the database aside."),
        "openfpgaloader": attr.label(mandatory = True, doc = "openFPGALoader.", **_EXE),
        "openfpgaloader_files": attr.label_list(allow_files = True, doc = "Everything openFPGALoader reads."),
        "chipdbs": attr.label_keyed_string_dict(
            allow_files = True,
            doc = "Chip database file -> the die it describes, e.g. xc7a200t.",
        ),
        "part_files": attr.label_keyed_string_dict(
            allow_files = True,
            doc = "A part's part.yaml in the Project X-Ray database -> the part.",
        ),
        "prjxray_db": attr.label_list(allow_files = True, doc = "The Project X-Ray database files the parts need."),
        "trees": attr.label_list(
            allow_files = True,
            doc = "The directories every tool above lies in, as directory inputs.",
        ),
        "plugins": attr.string_list(
            default = [],
            doc = "Yosys plugins available in this toolchain (e.g. 'slang', 'ghdl').",
        ),
    },
)
