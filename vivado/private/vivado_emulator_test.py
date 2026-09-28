# SPDX-License-Identifier: Apache-2.0
"""Tests for the Vivado emulation, with stub tools in place of the real ones.

The three scripts rules_vivado generates for vivado_project,
vivado_synthesis and vivado_place_and_route run in turn, each in a fresh
emulator process as in the build, and the project must carry from one to
the next through the .xpr file.
"""

import json
import os
import stat
import struct
import subprocess
import sys
import tempfile
import textwrap
import unittest

EMULATOR = os.path.join(os.path.dirname(__file__), "vivado_emulator.py")

NETLIST = {"modules": {"up_counter": {"ports": {
    "clk": {"direction": "input", "bits": [2]},
    "reset": {"direction": "input", "bits": [3]},
    "out": {"direction": "output", "bits": [4]},
}}}}


def field(key, value):
    value += b"\0"
    return key + struct.pack(">H", len(value)) + value


BIT = (bytes.fromhex("00090ff00ff00ff00ff0000001") + field(b"a", b"x.frames")
       + field(b"b", b"xc7a200tfbg484-2") + field(b"c", b"2026/09/27")
       + field(b"d", b"12:00:00") + b"e" + struct.pack(">I", 4) + b"\xaa\x99\x55\x66")

XPR_TCL = """
create_project blinky -force
set_property verilog_define {FPGA_XILINX=1} [get_filesets sources_1 ]
read_verilog   -sv {blinky.sv}
set_property include_dirs [list ] [get_filesets sources_1]
read_xdc {blinky.xdc}
set_property part xc7a200tfbg484-2 [current_project]
set_property top up_counter [current_fileset]
set_property source_mgmt_mode None [current_project]
"""

SYNTH_TCL = """
launch_runs synth_1
wait_on_run synth_1
exit [regexp -nocase -- {synth_design (error|failed)} [get_property STATUS [get_runs synth_1]] match]
"""

PNR_TCL = """
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
if { [get_property PROGRESS [get_runs impl_1]] != "100%"} {
  launch_runs synth_1 -quiet
  launch_runs impl_1 -to_step write_bitstream
  wait_on_run impl_1
  puts "Bitstream generation completed"
}
if { [get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: Implementation and bitstream generation step failed."
   exit 1
}
set vivadoDefaultBitstreamFile [ get_property DIRECTORY [current_run] ]/[ get_property top [current_fileset] ].bit
file copy -force $vivadoDefaultBitstreamFile [pwd]/[current_project].bit
"""


class EmulatorTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.tools = os.path.join(self.dir, "tools")
        os.makedirs(self.tools)
        self.env = dict(os.environ)
        self.env["PYTHONPATH"] = os.pathsep.join(sys.path)
        stubs = {
            # Yosys: records its script, writes the netlist and a report.
            "OPENXC7_YOSYS": """
                cp .openxc7.synth.ys yosys.script
                echo '%s' > .openxc7.netlist.json
                echo 'Number of cells: 3' > .openxc7.utilization.txt
            """ % json.dumps(NETLIST),
            "OPENXC7_NEXTPNR": """
                cp .openxc7.pnr.xdc nextpnr.xdc
                echo 'FASM_FEATURE' > .openxc7.fasm
                echo 'Info: Max frequency for clock: 300 MHz' > .openxc7.nextpnr.log
            """,
            "OPENXC7_FASM2FRAMES": 'echo frames > "${@: -1}"',
            "OPENXC7_XC7FRAMES2BIT": """
                while [ $# -gt 0 ]; do
                  [ "$1" = --output_file ] && out=$2; shift
                done
                printf '""" + "".join("\\%03o" % b for b in BIT) + """' > "$out"
            """,
        }
        for var, body in stubs.items():
            path = os.path.join(self.tools, var.lower())
            with open(path, "w") as f:
                f.write("#!/usr/bin/env bash\nset -e\n" + textwrap.dedent(body))
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
            self.env[var] = path
        self.env["OPENXC7_CHIPDB_XC7A200T"] = "chipdb.bin"
        self.env["OPENXC7_PART_YAML_XC7A200TFBG484_2"] = "db/artix7/xc7a200tfbg484-2/part.yaml"
        for name, text in {
            "blinky.sv": "module up_counter(); endmodule\n",
            "blinky.xdc": "set_property IOSTANDARD LVCMOS33 [get_ports {clk reset}]\n",
            "xpr.tcl": XPR_TCL, "synth.tcl": SYNTH_TCL, "pnr.tcl": PNR_TCL,
        }.items():
            with open(os.path.join(self.dir, name), "w") as f:
                f.write(text)

    def vivado(self, *args):
        return subprocess.run(
            [sys.executable, EMULATOR, "-notrace", "-mode", "batch"] + list(args),
            cwd=self.dir, env=self.env, capture_output=True, text=True)

    def path(self, name):
        return os.path.join(self.dir, name)

    def test_project_synthesis_and_implementation(self):
        r = self.vivado("-source", "xpr.tcl")
        self.assertEqual(r.returncode, 0, r.stderr)
        for d in ("blinky.xpr", "blinky.cache", "blinky.hw", "blinky.ip_user_files",
                  "vivado.jou", "vivado.log"):
            self.assertTrue(os.path.exists(self.path(d)), d)

        r = self.vivado("-source", "synth.tcl", "blinky.xpr")
        self.assertEqual(r.returncode, 0, r.stderr)
        script = open(self.path("yosys.script")).read()
        self.assertIn("-DFPGA_XILINX=1", script)
        self.assertIn("blinky.sv", script)
        self.assertIn("synth_xilinx -flatten -abc9 -arch xc7 -top up_counter", script)
        project = json.load(open(self.path("blinky.xpr")))
        self.assertEqual(project["runs"]["synth_1"]["PROGRESS"], "100%")

        r = self.vivado("-source", "pnr.tcl", "blinky.xpr")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Bitstream generation completed", r.stdout)
        bit = open(self.path("blinky.bit"), "rb").read()
        self.assertIn(b"2000/01/01", bit)  # the header was fixed
        xdc = open(self.path("nextpnr.xdc")).read()
        self.assertIn("[get_ports clk]", xdc)
        self.assertNotIn("{clk reset}", xdc)

    def test_a_failed_synthesis_exits_nonzero(self):
        self.assertEqual(self.vivado("-source", "xpr.tcl").returncode, 0)
        os.chmod(self.env["OPENXC7_YOSYS"], 0o755)
        with open(self.env["OPENXC7_YOSYS"], "w") as f:
            f.write("#!/usr/bin/env bash\nexit 3\n")
        r = self.vivado("-source", "synth.tcl", "blinky.xpr")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("yosys failed", r.stderr)

    def test_vhdl_is_refused(self):
        with open(self.path("v.tcl"), "w") as f:
            f.write("read_vhdl {a.vhd}\n")
        r = self.vivado("-source", "v.tcl")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("VHDL is not supported", r.stderr)

    def test_other_tools_are_not_emulated(self):
        r = subprocess.run([sys.executable, EMULATOR, "-mode", "tcl"],
                           capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
