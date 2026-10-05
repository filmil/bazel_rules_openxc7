# SPDX-License-Identifier: Apache-2.0
"""An emulation of Vivado's batch mode, on the open 7-series tools.

rules_vivado runs `vivado -mode batch -source <script>.tcl [<project>.xpr]`
with Tcl scripts it generates. Its main rules drive a Vivado *project*:
vivado_project creates it (create_project, read_verilog, read_xdc,
set_property part/top), vivado_synthesis runs `launch_runs synth_1`, and
vivado_place_and_route runs `launch_runs impl_1 -to_step write_bitstream`
and copies the bitstream out of the run's directory. The *2 variants use
the non-project commands instead. This program runs either kind of script
in a real Tcl interpreter (Python's own), with the Vivado commands defined
here and carried out by Yosys, nextpnr and Project X-Ray's tools:

  create_project, launch_runs synth_1 / impl_1          -> as below, with
                                                           the project kept
                                                           in the .xpr file

  set_part, read_verilog, read_xdc, synth_design        -> yosys synth_xilinx
  write_checkpoint, open_checkpoint                     -> a JSON checkpoint
  opt_design, place_design                              -> recorded
  route_design                                          -> nextpnr
  write_bitstream                                       -> fpga-as, or
                                                           fasm2frames and
                                                           xc7frames2bit
  report_timing_summary, report_utilization, report_drc -> text reports

A command outside that set that would change the design (VHDL, IP, debug
cores) is an error, so a design never builds to something other than what
it asks for. Commands that only query or set properties the open flow has
no use for are accepted and logged.

The tools are named by environment variables that the runner sets from
the openxc7 toolchain: OPENXC7_YOSYS, OPENXC7_NEXTPNR, and either
OPENXC7_FPGA_AS or OPENXC7_FASM2FRAMES with OPENXC7_XC7FRAMES2BIT;
OPENXC7_CHIPDB_<die> and OPENXC7_PART_YAML_<part> give the databases.
"""

import json
import os
import re
import shlex
import subprocess
import sys
import tkinter

from openxc7.private import bit_normalize
from openxc7.private import xdc_translate

# part -> die; the part names openFPGALoader and nextpnr know.
DIES = {"xc7a200tfbg484-2": "xc7a200t"}

# Commands that query or configure things the open flow does not have:
# accepted, logged, and they return their arguments so that a nested
# [get_*] still yields a value.
PASSIVE = [
    "get_filesets", "get_drc_checks", "get_ips", "get_cells",
    "get_nets", "get_pins", "get_ports", "get_clocks", "current_design",
    "set_msg_config", "set_param", "phys_opt_design", "power_opt_design",
    "report_power", "report_clock_utilization", "report_methodology",
    "report_io", "report_route_status", "config_timing_analysis",
]


class TclError(Exception):
    pass


def env_key(name):
    return name.replace("-", "_").upper()


class Vivado:
    def __init__(self, log):
        self.log = log
        self.part = None
        self.top = None
        self.verilog = []  # (path, is_sv)
        self.vhdl = []  # path
        self.xdcs = []
        self.include_dirs = []
        self.defines = []
        self.parameters = []
        self.generics = []
        self.systemverilog_parser = os.environ.get("OPENXC7_SYSTEMVERILOG_PARSER", "yosys")
        self.netlist = None  # text of the Yosys JSON netlist
        self.fasm = None  # text of the routed FASM
        self.reports = {}
        self.project = None  # name, when a project is open
        self.runs = {
            "synth_1": {"PROGRESS": "0%", "STATUS": "Not started"},
            "impl_1": {"PROGRESS": "0%", "STATUS": "Not started"},
        }
        self.active_run = "synth_1"

    # --- helpers -----------------------------------------------------------

    def note(self, msg):
        print("openxc7-vivado: " + msg, file=self.log, flush=True)

    def tool(self, var):
        path = os.environ.get(var)
        if not path:
            raise TclError("the runner did not set %s" % var)
        return path

    def run(self, argv, what, stdin=None, stdout=None):
        self.note("running %s: %s" % (what, " ".join(shlex.quote(a) for a in argv)))
        result = subprocess.run(argv, stdin=stdin, stdout=stdout or self.log,
                                stderr=self.log)
        if result.returncode != 0:
            raise TclError("%s failed with exit code %d" % (what, result.returncode))

    @staticmethod
    def options(args, flags=(), values=()):
        """Splits Vivado-style arguments into options and positionals."""
        opts, rest, i = {}, [], 0
        while i < len(args):
            a = args[i]
            if a in values and i + 1 < len(args):
                opts.setdefault(a, []).append(args[i + 1])
                i += 2
            elif a in flags or (a.startswith("-") and len(a) > 1 and not a[1].isdigit()):
                opts.setdefault(a, []).append(True)
                i += 1
            else:
                rest.append(a)
                i += 1
        return opts, rest

    # --- synthesis ---------------------------------------------------------

    def set_part(self, *args):
        self.part = args[0]
        return ""

    def read_verilog(self, *args):
        opts, files = self.options(args, flags=("-sv",), values=("-library",))
        for f in files:
            for name in f.split():
                entry = (name, "-sv" in opts or name.endswith(".sv"))
                if entry not in self.verilog:
                    self.verilog.append(entry)
        return ""

    def read_vhdl(self, *args):
        opts, files = self.options(args, flags=("-vhdl2008", "-vhdl93", "-v93"),
                                   values=("-library",))
        for f in files:
            for name in f.split():
                if name not in self.vhdl:
                    self.vhdl.append(name)
        return ""

    def read_xdc(self, *args):
        _, files = self.options(args, values=("-ref", "-cells", "-mode"))
        for name in (n for f in files for n in f.split()):
            if name not in self.xdcs:
                self.xdcs.append(name)
        return ""

    def set_property(self, *args):
        if len(args) >= 2 and args[0] == "include_dirs":
            self.include_dirs = args[1].split()
        elif len(args) >= 2 and args[0] == "verilog_define":
            self.defines = args[1].split()
        elif len(args) >= 2 and args[0] == "part":
            self.part = args[1]
        elif len(args) >= 2 and args[0] == "top":
            self.top = args[1]
        else:
            self.note("set_property %s: accepted, no effect" % " ".join(args))
        return ""

    def synth_design(self, *args):
        opts, _ = self.options(args, values=("-top", "-part", "-generic",
                                             "-parameter", "-flatten_hierarchy",
                                             "-directive", "-mode",
                                             "-include_dirs", "-verilog_define"))
        self.top = opts.get("-top", [self.top])[0]
        self.part = opts.get("-part", [self.part])[0]
        if not self.top or not self.part:
            raise TclError("synth_design needs -top and a part")
        self.generics = opts.get("-generic", self.generics)
        self.parameters = opts.get("-parameter", self.parameters)
        if self.part not in DIES:
            raise TclError("part %s is not supported; supported: %s"
                           % (self.part, ", ".join(sorted(DIES))))

        use_slang = (
            self.systemverilog_parser == "slang"
            or os.environ.get("OPENXC7_SYSTEMVERILOG_PARSER") == "slang"
            or os.environ.get("OPENXC7_SLANG") == "1"
            or "OPENXC7_SLANG=1" in self.defines
            or "OPENXC7_SLANG" in self.defines
        )

        defines = ["-D" + d for d in self.defines]
        inc_dirs = ["-I" + d for d in self.include_dirs]

        v_files = [f for f, is_sv in self.verilog if not is_sv]
        sv_files = [f for f, is_sv in self.verilog if is_sv]

        script = []
        if use_slang:
            if v_files:
                script.append(" ".join(["read_verilog"] + defines + inc_dirs + [shlex.quote(f) for f in v_files]))
            if sv_files:
                script.append(" ".join(["read_slang"] + defines + inc_dirs + [shlex.quote(f) for f in sv_files]))
        else:
            verilog_all = [f for f, _ in self.verilog]
            if verilog_all:
                script.append(" ".join(["read_verilog", "-sv"] + defines + inc_dirs + [shlex.quote(f) for f in verilog_all]))

        if self.vhdl:
            generic_args = ["-g" + g for g in self.generics]
            top_is_vhdl = not self.verilog
            if not top_is_vhdl:
                top_pat = re.compile(r"\bentity\s+" + re.escape(self.top) + r"\b", re.IGNORECASE)
                for f in self.vhdl:
                    if os.path.exists(f):
                        with open(f, errors="ignore") as fh:
                            if top_pat.search(fh.read()):
                                top_is_vhdl = True
                                break
            if top_is_vhdl:
                script.append(" ".join(["ghdl", "--std=08"] + generic_args + [shlex.quote(f) for f in self.vhdl] + ["-e", self.top]))
            else:
                script.append(" ".join(["ghdl", "-read", "--std=08"] + [shlex.quote(f) for f in self.vhdl]))
                script.append("hierarchy -top %s" % self.top)

        for p in self.parameters:
            name, _, value = p.partition("=")
            script.append("chparam -set %s %s %s" % (name, value, self.top))
        script += [
            "synth_xilinx -flatten -abc9 -arch xc7 -top %s" % self.top,
            # A $buf that synth_xilinx leaves has no BEL in nextpnr-xilinx;
            # openxc7/private/synthesis.bzl says more.
            "techmap -map +/techmap.v t:$buf",
            "opt_clean",
            "tee -o .openxc7.utilization.txt stat",
            "write_json .openxc7.netlist.json",
        ]
        with open(".openxc7.synth.ys", "w") as f:
            f.write("\n".join(script) + "\n")

        plugins = []
        if use_slang and sv_files:
            plugins.extend(["-m", "slang"])
        if self.vhdl:
            plugins.extend(["-m", "ghdl"])

        self.run([self.tool("OPENXC7_YOSYS")] + plugins + ["-q", "-s", ".openxc7.synth.ys"], "yosys")
        with open(".openxc7.netlist.json") as f:
            self.netlist = f.read()
        with open(".openxc7.utilization.txt") as f:
            self.reports["utilization"] = f.read()
        self.reports["timing"] = "Timing is analysed at place and route (nextpnr).\n"
        return ""

    # --- checkpoints -------------------------------------------------------

    def write_checkpoint(self, *args):
        _, files = self.options(args, flags=("-force", "-incremental_synth"))
        state = {
            "format": "openxc7-checkpoint-1",
            "part": self.part,
            "top": self.top,
            "xdcs": [[p, open(p).read()] for p in self.xdcs],
            "netlist": self.netlist,
            "fasm": self.fasm,
            "reports": self.reports,
        }
        with open(files[0], "w") as f:
            json.dump(state, f)
        return ""

    def open_checkpoint(self, *args):
        _, files = self.options(args)
        with open(files[0]) as f:
            state = json.load(f)
        if state.get("format") != "openxc7-checkpoint-1":
            raise TclError("%s is not a checkpoint this emulation wrote" % files[0])
        self.part, self.top = state["part"], state["top"]
        self.netlist, self.fasm = state["netlist"], state["fasm"]
        self.reports = state["reports"]
        # The synthesis run's constraints, as they were; pnr reads its own
        # with read_xdc as well, and a file read twice is read once.
        os.makedirs(".openxc7.xdc", exist_ok=True)
        for i, (path, text) in enumerate(state["xdcs"]):
            copy = os.path.join(".openxc7.xdc", "%d_%s" % (i, os.path.basename(path)))
            with open(copy, "w") as f:
                f.write(text)
            self.xdcs.append(copy)
        return ""

    # --- implementation ----------------------------------------------------

    def opt_design(self, *args):
        return ""

    def place_design(self, *args):
        return ""

    def _unique_xdcs(self):
        seen, out = set(), []
        for p in self.xdcs:
            text = open(p).read()
            if text not in seen:
                seen.add(text)
                out.append(p)
        return out

    def route_design(self, *args):
        if self.netlist is None:
            raise TclError("route_design: no synthesised design is open")
        with open(".openxc7.netlist.json", "w") as f:
            f.write(self.netlist)
        xdc_translate.main([
            "--netlist", ".openxc7.netlist.json", "--top", self.top,
            "--out", ".openxc7.pnr.xdc",
        ] + self._unique_xdcs())
        die = DIES[self.part]
        self.run([
            self.tool("OPENXC7_NEXTPNR"),
            "--device", self.part,
            "--chipdb", self.tool("OPENXC7_CHIPDB_" + env_key(die)),
            "--json", ".openxc7.netlist.json",
            "-o", "xdc=.openxc7.pnr.xdc",
            "-o", "fasm=.openxc7.fasm",
            "--log", ".openxc7.nextpnr.log",
            "--quiet",
            # Timing is reported, not fatal, as in Vivado's route_design;
            # openxc7/private/place_and_route.bzl says why.
            "--timing-allow-fail",
        ], "nextpnr")
        with open(".openxc7.fasm") as f:
            self.fasm = f.read()
        log = open(".openxc7.nextpnr.log").read()
        self.reports["timing"] = "".join(
            l for l in log.splitlines(True) if "Max frequency" in l or "Slack" in l
        ) or "nextpnr reported no timing.\n"
        self.reports["drc"] = "".join(
            l for l in log.splitlines(True) if l.startswith(("Warning", "ERROR"))
        ) or "nextpnr reported no warnings.\n"
        return ""

    def write_bitstream(self, *args):
        _, files = self.options(args, flags=("-force", "-bin_file", "-no_partial_bitfile"),
                                values=("-cell", "-file"))
        out = files[0]
        if not out.endswith(".bit"):
            out += ".bit"
        if self.fasm is None:
            raise TclError("write_bitstream: the design is not routed")
        with open(".openxc7.fasm", "w") as f:
            f.write(self.fasm)
        part_yaml = self.tool("OPENXC7_PART_YAML_" + env_key(self.part))
        db_root = os.path.dirname(os.path.dirname(part_yaml))
        raw = ".openxc7.raw.bit"
        if os.environ.get("OPENXC7_FPGA_AS"):
            with open(".openxc7.fasm") as fin, open(raw, "wb") as fout:
                self.run([self.tool("OPENXC7_FPGA_AS"),
                          "--prjxray_db_path=" + db_root,
                          "--part=" + self.part], "fpga-as",
                         stdin=fin, stdout=fout)
        else:
            self.run([self.tool("OPENXC7_FASM2FRAMES"), "--db-root", db_root,
                      "--part", self.part, ".openxc7.fasm", ".openxc7.frames"],
                     "fasm2frames")
            self.run([self.tool("OPENXC7_XC7FRAMES2BIT"),
                      "--part_file", part_yaml, "--part_name", self.part,
                      "--frm_file", ".openxc7.frames", "--output_file", raw],
                     "xc7frames2bit")
        bit_normalize.main([raw, out])
        return ""

    def write_debug_probes(self, *args):
        raise TclError("write_debug_probes: the open flow has no debug cores")


    # --- project mode ------------------------------------------------------

    def xpr_path(self):
        return "%s.xpr" % self.project

    def save_project(self):
        if not self.project:
            return
        state = {
            "format": "openxc7-project-1",
            "project": self.project,
            "part": self.part,
            "top": self.top,
            "verilog": self.verilog,
            "vhdl": self.vhdl,
            "xdcs": self.xdcs,
            "include_dirs": self.include_dirs,
            "defines": self.defines,
            "generics": self.generics,
            "systemverilog_parser": self.systemverilog_parser,
            "runs": self.runs,
        }
        with open(self.xpr_path(), "w") as f:
            json.dump(state, f, indent=1)
        for d in ("runs", "hw", "cache", "ip_user_files", "gen/sources_1"):
            os.makedirs("%s.%s" % (self.project, d), exist_ok=True)

    def open_project(self, path):
        with open(path) as f:
            state = json.load(f)
        if state.get("format") != "openxc7-project-1":
            raise TclError("%s is not a project this emulation wrote" % path)
        self.project = state["project"]
        self.part, self.top = state["part"], state["top"]
        self.verilog = [tuple(v) for v in state["verilog"]]
        self.vhdl = list(state.get("vhdl", []))
        self.generics = list(state.get("generics", []))
        self.systemverilog_parser = state.get("systemverilog_parser", self.systemverilog_parser)
        self.xdcs, self.include_dirs = state["xdcs"], state["include_dirs"]
        self.defines, self.runs = state["defines"], state["runs"]
        self.note("opened project %s" % self.project)

    def create_project(self, *args):
        opts, rest = self.options(args, flags=("-force", "-in_memory"),
                                  values=("-part",))
        self.project = rest[0] if rest else "project_1"
        if "-part" in opts:
            self.part = opts["-part"][0]
        self.save_project()
        return self.project

    def current_project(self, *args):
        return self.project or ""

    def current_fileset(self, *args):
        return "sources_1"

    def get_runs(self, *args):
        _, rest = self.options(args, flags=("-quiet",), values=("-filter",))
        return " ".join(rest) or " ".join(self.runs)

    def current_run(self, *args):
        return self.active_run

    def run_dir(self, run):
        return os.path.abspath(os.path.join("%s.runs" % self.project, run))

    def get_property(self, *args):
        _, rest = self.options(args, flags=("-quiet",))
        name, obj = rest[0], rest[1] if len(rest) > 1 else ""
        if obj in self.runs:
            if name == "DIRECTORY":
                return self.run_dir(obj)
            return self.runs[obj].get(name, "")
        if name == "top":
            return self.top or ""
        if name == "part":
            return self.part or ""
        self.note("get_property %s %s: no value" % (name, obj))
        return ""

    def launch_runs(self, *args):
        opts, rest = self.options(args, flags=("-quiet", "-force"),
                                  values=("-to_step", "-jobs", "-next_step"))
        for run in " ".join(rest).split():
            if run == "synth_1":
                self.run_synthesis()
            elif run == "impl_1":
                if self.runs["synth_1"]["PROGRESS"] != "100%":
                    self.run_synthesis()
                self.run_implementation(opts.get("-to_step", ["write_bitstream"])[0])
            else:
                raise TclError("launch_runs: unknown run %s" % run)
        return ""

    def wait_on_run(self, *args):
        return ""

    def run_synthesis(self):
        self.active_run = "synth_1"
        run = self.runs["synth_1"]
        try:
            self.synth_design("-top", self.top, "-part", self.part)
            os.makedirs(self.run_dir("synth_1"), exist_ok=True)
            with open(os.path.join(self.run_dir("synth_1"), self.top + ".json"), "w") as f:
                f.write(self.netlist)
            run.update(PROGRESS="100%", STATUS="synth_design Complete!")
        except TclError:
            run.update(PROGRESS="0%", STATUS="synth_design ERROR")
            raise

    def run_implementation(self, to_step):
        self.active_run = "impl_1"
        run = self.runs["impl_1"]
        if self.netlist is None:
            path = os.path.join(self.run_dir("synth_1"), self.top + ".json")
            with open(path) as f:
                self.netlist = f.read()
        try:
            self.route_design()
            if to_step == "write_bitstream":
                os.makedirs(self.run_dir("impl_1"), exist_ok=True)
                self.write_bitstream(os.path.join(self.run_dir("impl_1"), self.top + ".bit"))
            run.update(PROGRESS="100%", STATUS="%s Complete!" % to_step)
        except TclError:
            run.update(PROGRESS="0%", STATUS="%s ERROR" % to_step)
            raise

    def report(self, key, default):
        def command(*args):
            opts, _ = self.options(args, values=("-file", "-name", "-max_paths"))
            text = self.reports.get(key, default)
            if "-file" in opts:
                with open(opts["-file"][0], "w") as f:
                    f.write(text)
                return ""
            return text
        return command

    def unsupported(self, name):
        def command(*args):
            raise TclError("%s: not supported by the open flow" % name)
        return command

    def passive(self, name):
        def command(*args):
            self.note("%s %s: accepted, no effect" % (name, " ".join(args)))
            return " ".join(args)
        return command


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    script, i = None, 0
    while i < len(argv):
        if argv[i] == "-source" and i + 1 < len(argv):
            script = argv[i + 1]
            i += 2
        elif argv[i] in ("-mode", "-log", "-journal", "-tclargs"):
            i += 2
        else:
            i += 1
    if script is None:
        sys.exit("openxc7-vivado: only `vivado -mode batch -source <script>` is emulated")

    # Vivado writes a journal and a log in its working directory, and
    # vivado_project copies both.
    for name in ("vivado.jou", "vivado.log"):
        with open(name, "a") as f:
            f.write("# openxc7 Vivado emulation: %s\n" % " ".join(argv))

    vivado = Vivado(sys.stderr)
    for xpr in (a for a in argv if a.endswith(".xpr")):
        try:
            vivado.open_project(xpr)
        except (TclError, OSError, ValueError) as e:
            print("openxc7-vivado: ERROR: %s" % e, file=sys.stderr)
            sys.exit(1)

    tcl = tkinter.Tcl()

    def wrap(fn):
        def command(*args):
            try:
                return fn(*args)
            except TclError as e:
                vivado.note("ERROR: %s" % e)
                raise tkinter.TclError(str(e))
            except (Exception, SystemExit) as e:  # noqa: BLE001, reported below
                # Anything else is a fault here or in a file, and says so
                # rather than failing the command with an empty message.
                msg = "%s: %s: %s" % (getattr(fn, "__name__", fn), type(e).__name__, e)
                vivado.note("ERROR: %s" % msg)
                raise tkinter.TclError(msg)
        return command

    commands = {
        "set_part": vivado.set_part,
        "read_verilog": vivado.read_verilog,
        "read_vhdl": vivado.read_vhdl,
        "read_xdc": vivado.read_xdc,
        "set_property": vivado.set_property,
        "synth_design": vivado.synth_design,
        "write_checkpoint": vivado.write_checkpoint,
        "open_checkpoint": vivado.open_checkpoint,
        "opt_design": vivado.opt_design,
        "place_design": vivado.place_design,
        "route_design": vivado.route_design,
        "write_bitstream": vivado.write_bitstream,
        "write_debug_probes": vivado.write_debug_probes,
        "report_timing_summary": vivado.report("timing", "No timing report.\n"),
        "report_utilization": vivado.report("utilization", "No utilization report.\n"),
        "report_drc": vivado.report("drc", "No DRC report.\n"),
        "create_project": vivado.create_project,
        "current_project": vivado.current_project,
        "current_fileset": vivado.current_fileset,
        "current_run": vivado.current_run,
        "get_runs": vivado.get_runs,
        "get_property": vivado.get_property,
        "launch_runs": vivado.launch_runs,
        "wait_on_run": vivado.wait_on_run,
    }
    for name in ("read_ip", "synth_ip", "generate_target", "create_ip",
                 "add_files", "import_ip", "create_debug_core"):
        commands[name] = vivado.unsupported(name)
    for name in PASSIVE:
        commands[name] = vivado.passive(name)
    for name, fn in commands.items():
        tcl.createcommand(name, wrap(fn))

    # Tcl's own exit would end the process before the project is saved.
    # A SystemExit inside a Tcl callback becomes a Tcl error, so this ends
    # the process itself once the project is saved and output flushed.
    def tcl_exit(*args):
        vivado.save_project()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(int(args[0]) if args else 0)

    tcl.createcommand("exit", tcl_exit)

    try:
        tcl.eval("source {%s}" % script)
    except tkinter.TclError as e:
        vivado.save_project()
        # Tcl's errorInfo names the command and the line that failed.
        info = tcl.eval("set ::errorInfo")
        print("openxc7-vivado: ERROR: %s\n%s" % (e, info), file=sys.stderr)
        sys.exit(1)
    vivado.save_project()


if __name__ == "__main__":
    main()
