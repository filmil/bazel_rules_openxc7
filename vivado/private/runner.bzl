# SPDX-License-Identifier: Apache-2.0
"""The runner of the emulated Vivado toolchain, bound to the openxc7 tools.

The emulation is Python, and its Tcl interpreter is Python's own, whose
library is a directory of .tcl files. rules_vivado's synthesis action runs
`find . -name '*.tcl'` over its whole working directory, the runner's
runfiles included, and copies every match into one directory, where two
files named pkgIndex.tcl collide and the action fails. So the runner's
runfiles hold the Python runtime and the emulation as one tar file, which
the runner unpacks into a temporary directory to run. The tools come in
as whole directories for the same reason: their .v and .tcl files would be
found otherwise.
"""

load("//openxc7/private:toolchain.bzl", "TOOLCHAIN_TYPE")

_PY_TOOLCHAIN = "@rules_python//python:toolchain_type"

def _runfiles_path(f):
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return "_main/" + f.short_path

def _repo_path(f):
    # The path inside its own repository, the same whether this module is
    # the root or a dependency; the emulation imports its sources by it.
    if f.short_path.startswith("../"):
        return f.short_path.split("/", 2)[2]
    return f.short_path

def _env_key(name):
    return name.replace("-", "_").upper()

def _openxc7_vivado_runner_impl(ctx):
    tc = ctx.toolchains[TOOLCHAIN_TYPE].openxc7
    exports = {
        "OPENXC7_YOSYS": tc.yosys.executable,
        "OPENXC7_NEXTPNR": tc.nextpnr.executable,
        "OPENXC7_FASM2FRAMES": tc.fasm2frames.executable,
        "OPENXC7_XC7FRAMES2BIT": tc.xc7frames2bit.executable,
    }
    for die, f in tc.chipdbs.items():
        exports["OPENXC7_CHIPDB_" + _env_key(die)] = f
    for part, data in tc.parts.items():
        exports["OPENXC7_PART_YAML_" + _env_key(part)] = data.part_yaml

    # The paths are named, not added to the runfiles: the tools come in as
    # whole directories (tc.trees), which hold them.
    lines = [
        'export %s="$runfiles/%s"' % (k, _runfiles_path(f))
        for k, f in sorted(exports.items())
    ]
    py = ctx.toolchains[_PY_TOOLCHAIN].py3_runtime
    root = py.interpreter.dirname.rsplit("/", 1)[0]  # <runtime>/bin/python3
    entries = []
    for f in py.files.to_list() + [py.interpreter]:
        if f.path.startswith(root + "/"):
            entries.append(("python/" + f.path[len(root) + 1:], f))
    for f in ctx.files._emulator_srcs:
        entries.append(("src/" + _repo_path(f), f))
    manifest = ctx.actions.declare_file(ctx.label.name + ".tar.manifest")
    ctx.actions.write(manifest, "".join(["%s\t%s\n" % (d, f.path) for d, f in entries]))
    archive = ctx.actions.declare_file(ctx.label.name + ".emulator.tar")
    ctx.actions.run_shell(
        inputs = depset([manifest] + [f for _, f in entries]),
        outputs = [archive],
        command = """
set -euo pipefail
stage=$(mktemp -d)
while IFS=$'\\t' read -r dest src; do
  mkdir -p "$stage/$(dirname "$dest")"
  cp -L "$src" "$stage/$dest"
done < "$1"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$2" -C "$stage" .
rm -rf "$stage"
""",
        arguments = [manifest.path, archive.path],
        mnemonic = "EmulatorTar",
        progress_message = "Packing the Vivado emulation",
    )
    interpreter = "python/" + py.interpreter.path[len(root) + 1:]

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = script,
        substitutions = {
            "@@EXPORTS@@": "\n".join(lines),
            "@@ARCHIVE@@": _runfiles_path(archive),
            "@@INTERPRETER@@": interpreter,
        },
        is_executable = True,
    )
    if not tc.trees:
        fail("the openxc7 toolchain gives no `trees`, which the Vivado runner needs")
    runfiles = ctx.runfiles(
        files = [archive],
        transitive_files = tc.trees,
    )
    return [DefaultInfo(executable = script, runfiles = runfiles)]

openxc7_vivado_runner = rule(
    implementation = _openxc7_vivado_runner_impl,
    executable = True,
    doc = "A rules_vivado runner that runs the Vivado emulation with the openxc7 tools.",
    attrs = {
        "_template": attr.label(
            default = "//vivado/private:runner.sh.tpl",
            allow_single_file = True,
        ),
        "_emulator_srcs": attr.label_list(
            default = [
                "//vivado/private:vivado_emulator.py",
                "//openxc7/private:xdc_translate.py",
                "//openxc7/private:bit_normalize.py",
            ],
            allow_files = [".py"],
        ),
    },
    toolchains = [TOOLCHAIN_TYPE, _PY_TOOLCHAIN],
)
