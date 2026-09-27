# SPDX-License-Identifier: Apache-2.0
"""The parts the rules support, and what each needs from the toolchain."""

# part -> (die, family, openFPGALoader's part name).
# The die names the chip database; the family names the Project X-Ray
# database directory; openFPGALoader names a part without its speed grade.
PARTS = {
    "xc7a200tfbg484-2": struct(
        die = "xc7a200t",
        family = "artix7",
        ofl_part = "xc7a200tfbg484",
    ),
}

def part_info(part):
    """Returns the struct for `part`, or fails naming the supported parts.

    Args:
      part: a Xilinx part name, such as "xc7a200tfbg484-2".

    Returns:
      A struct with `die`, `family` and `ofl_part`.
    """
    if part not in PARTS:
        fail("part %r is not supported by rules_openxc7; supported: %s" % (
            part,
            ", ".join(sorted(PARTS.keys())),
        ))
    return PARTS[part]
