# SPDX-License-Identifier: Apache-2.0
"""Makes a Xilinx .bit file reproducible by fixing its header.

A .bit file begins with a header of tagged fields: `a` the design name,
`b` the part, `c` the date and `d` the time the file was written, then `e`
the length of the configuration data that follows. xc7frames2bit and
fpga-as write the wall clock into `c` and `d`, and xc7frames2bit writes the
whole path of its input into `a`, which under Bazel names the output
directory. So two builds of one design differ, and nothing downstream can
be cached. This sets `c` and `d` to fixed values and cuts the path in `a`
to its base name. fpga-as writes 0 as the `e` length, which a loader that
trusts the header then reads as an empty bitstream, so `e` is set to the
length of the data that follows. The configuration data is not touched.

    bit_normalize in.bit out.bit
"""

import struct
import sys

# The fixed preamble every .bit header starts with: a length-prefixed
# 9-byte field, then a length-prefixed empty one.
PREAMBLE = bytes.fromhex("00090ff00ff00ff00ff0000001")
FIXED = {b"c": b"2000/01/01", b"d": b"00:00:00"}


def _design_name(value):
    # "path/to/top.frames;Generator=xc7frames2bit" -> "top.frames;Generator=..."
    head, sep, rest = value.partition(b";")
    return head.rsplit(b"/", 1)[-1] + sep + rest


def normalize(data):
    if not data.startswith(PREAMBLE):
        raise ValueError("not a .bit file: the header preamble is missing")
    out = bytearray(PREAMBLE)
    pos = len(PREAMBLE)
    while True:
        key = data[pos:pos + 1]
        if key == b"e":
            body = data[pos + 5:]
            (declared,) = struct.unpack(">I", data[pos + 1:pos + 5])
            if declared not in (0, len(body)):
                raise ValueError("the e field says %d bytes, and %d follow"
                                 % (declared, len(body)))
            out += b"e" + struct.pack(">I", len(body)) + body
            return bytes(out)
        if key not in (b"a", b"b", b"c", b"d"):
            raise ValueError("unexpected header field %r at %d" % (key, pos))
        (length,) = struct.unpack(">H", data[pos + 1:pos + 3])
        value = data[pos + 3:pos + 3 + length].rstrip(b"\0")
        if key == b"a":
            value = _design_name(value)
        value = FIXED.get(key, value) + b"\0"
        out += key + struct.pack(">H", len(value)) + value
        pos += 3 + length


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 2:
        sys.exit("usage: bit_normalize in.bit out.bit")
    with open(argv[0], "rb") as f:
        data = f.read()
    with open(argv[1], "wb") as f:
        f.write(normalize(data))


if __name__ == "__main__":
    main()
