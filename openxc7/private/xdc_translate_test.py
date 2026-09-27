# SPDX-License-Identifier: Apache-2.0
"""Tests for xdc_translate: each Vivado selector becomes one command per port."""

import unittest

from openxc7.private import xdc_translate

NETLIST = {
    "modules": {
        "top": {
            "ports": {
                "clk": {"direction": "input", "bits": [2]},
                "reset": {"direction": "input", "bits": [3]},
                "out": {"direction": "output", "bits": [4, 5]},
            }
        }
    }
}


class XdcTranslateTest(unittest.TestCase):
    def setUp(self):
        self.ports = xdc_translate.netlist_ports(NETLIST, "top")

    def tr(self, line):
        return xdc_translate.translate_line(line, self.ports)

    def test_bus_bits(self):
        self.assertEqual(list(self.ports), ["clk", "reset", "out[0]", "out[1]"])

    def test_braced_list_splits(self):
        self.assertEqual(
            self.tr("set_property IOSTANDARD LVCMOS33 [get_ports {clk reset}]"),
            [
                "set_property IOSTANDARD LVCMOS33 [get_ports clk]",
                "set_property IOSTANDARD LVCMOS33 [get_ports reset]",
            ],
        )

    def test_all_inputs_and_outputs(self):
        self.assertEqual(len(self.tr("set_property X Y [all_inputs]")), 2)
        self.assertEqual(
            self.tr("set_property X Y [all_outputs]"),
            ["set_property X Y [get_ports out[0]]", "set_property X Y [get_ports out[1]]"],
        )

    def test_bus_name_and_wildcard(self):
        self.assertEqual(len(self.tr("set_property X Y [get_ports out]")), 2)
        self.assertEqual(len(self.tr("set_property X Y [get_ports {out[*]}]")), 2)

    def test_single_braced_port(self):
        self.assertEqual(
            self.tr("set_property PACKAGE_PIN R4 [get_ports {clk}]"),
            ["set_property PACKAGE_PIN R4 [get_ports clk]"],
        )

    def test_other_lines_pass_through(self):
        for line in [
            "# a comment [all_inputs]",
            "set_property CFGBVS VCCO [current_design]",
            "create_clock -period 10 [get_ports clk]",
            "",
        ]:
            self.assertEqual(len(self.tr(line)), 1, line)

    def test_unknown_port_is_kept(self):
        self.assertEqual(
            self.tr("set_property X Y [get_ports nosuch]"),
            ["set_property X Y [get_ports nosuch]"],
        )


if __name__ == "__main__":
    unittest.main()
