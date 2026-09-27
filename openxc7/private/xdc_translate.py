# SPDX-License-Identifier: Apache-2.0
"""Translates Vivado XDC into the subset nextpnr's Xilinx reader accepts.

nextpnr (openXC7, himbaechel xilinx) reads `get_ports` and `get_cells`
selectors only, and asserts on a braced list of several names:
`[get_ports {clk reset}]` aborts it with `str.back() == '}'`. Vivado XDC
uses both, and also `[all_inputs]`, `[all_outputs]`, `[all_ports]` and
wildcards. This rewrites each command that selects ports into one command
per port, using the synthesised netlist's port list, and passes every
other line through unchanged.

    xdc_translate --netlist top.json --top up_counter --out out.xdc a.xdc b.xdc
"""

import argparse
import fnmatch
import json
import re
import sys

# A port selector inside a command: [get_ports ...], [all_inputs] and so on.
SELECTOR = re.compile(
    r"\[\s*(get_ports\s+(?:\{[^}]*\}|[^\]]+)|all_inputs|all_outputs|all_ports)\s*\]"
)


def netlist_ports(netlist, top):
    """Returns {bit name: direction} for the top module, one entry per bit.

    A port of width 1 is named as it is (`clk`); a wider one gives one name
    per bit, as XDC names them (`out[0]`, `out[1]`, ...).
    """
    modules = netlist["modules"]
    if top not in modules:
        sys.exit("xdc_translate: top module %r is not in the netlist" % top)
    ports = {}
    for name, port in modules[top]["ports"].items():
        width = len(port["bits"])
        offset = port.get("offset", 0)
        if width == 1 and not port.get("upto"):
            ports[name] = port["direction"]
        else:
            for i in range(width):
                ports["%s[%d]" % (name, offset + i)] = port["direction"]
    return ports


def _xdc_glob(pattern):
    """Turns an XDC name pattern into an fnmatch one.

    In XDC only `*` and `?` are wildcards, and brackets are part of a bit
    name (`out[*]` is every bit of `out`). In fnmatch brackets make a
    character class, so they are escaped.
    """
    return "".join("[[]" if c == "[" else "[]]" if c == "]" else c for c in pattern)


def select(selector, ports):
    """Returns the port names one selector names, in netlist order."""
    if selector == "all_inputs":
        return [p for p, d in ports.items() if d == "input"]
    if selector == "all_outputs":
        return [p for p, d in ports.items() if d == "output"]
    if selector == "all_ports":
        return list(ports)
    arg = selector[len("get_ports"):].strip()
    if arg.startswith("{") and arg.endswith("}"):
        arg = arg[1:-1]
    names = []
    for pattern in arg.split():
        glob = _xdc_glob(pattern)
        # A bus name alone (`out`) names every bit of it.
        matched = [p for p in ports if fnmatch.fnmatchcase(p, glob)
                   or p.startswith(pattern + "[")]
        if not matched:
            # Keep a name the netlist does not have, so that nextpnr's own
            # message about it still appears.
            matched = [pattern]
        names.extend(m for m in matched if m not in names)
    return names


def translate_line(line, ports):
    """Returns the lines one XDC line becomes."""
    code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
    match = SELECTOR.search(code)
    if not match:
        return [line]
    names = select(match.group(1), ports)
    return [
        code[: match.start()] + "[get_ports %s]" % name + code[match.end():]
        for name in names
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--netlist", required=True, help="Yosys JSON netlist")
    parser.add_argument("--top", required=True, help="top module name")
    parser.add_argument("--out", required=True, help="translated XDC to write")
    parser.add_argument("xdcs", nargs="*", help="Vivado XDC files, in order")
    args = parser.parse_args(argv)

    with open(args.netlist) as f:
        ports = netlist_ports(json.load(f), args.top)
    lines = []
    for path in args.xdcs:
        lines.append("# from %s" % path)
        with open(path) as f:
            for line in f.read().splitlines():
                lines.extend(translate_line(line, ports))
    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
