# SPDX-License-Identifier: Apache-2.0
"""Tests for bit_normalize: only the date and time fields change."""

import struct
import unittest

from openxc7.private import bit_normalize


def field(key, value):
    value = value + b"\0"
    return key + struct.pack(">H", len(value)) + value


def bit(date, time, name=b"top.frames"):
    return (
        bit_normalize.PREAMBLE
        + field(b"a", name + b";Generator=xc7frames2bit")
        + field(b"b", b"xc7a200tfbg484-2")
        + field(b"c", date)
        + field(b"d", time)
        + b"e" + struct.pack(">I", 4) + b"\xaa\x99\x55\x66"
    )


class BitNormalizeTest(unittest.TestCase):
    def test_two_builds_agree(self):
        one = bit_normalize.normalize(bit(b"2026/09/27", b"15:34:10"))
        two = bit_normalize.normalize(bit(b"2027/01/02", b"08:00:59"))
        self.assertEqual(one, two)

    def test_output_directory_is_dropped(self):
        one = bit_normalize.normalize(bit(b"2026/09/27", b"15:34:10", b"top.frames"))
        two = bit_normalize.normalize(
            bit(b"2026/09/27", b"15:34:10", b"bazel-out/k8-opt/bin/x/top.frames"))
        self.assertEqual(one, two)
        self.assertIn(b"top.frames;Generator=xc7frames2bit", one)

    def test_only_date_and_time_change(self):
        raw = bit(b"2026/09/27", b"15:34:10")
        out = bit_normalize.normalize(raw)
        self.assertEqual(len(raw), len(out))
        self.assertIn(b"2000/01/01", out)
        self.assertIn(b"00:00:00", out)
        self.assertTrue(out.endswith(b"\xaa\x99\x55\x66"))
        self.assertIn(b"xc7a200tfbg484-2", out)

    def test_refuses_other_files(self):
        with self.assertRaises(ValueError):
            bit_normalize.normalize(b"not a bitstream")


if __name__ == "__main__":
    unittest.main()
