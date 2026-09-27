#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Checks the bitstream the open flow wrote for blinky. A frame file that
# came out empty still gives a .bit of normal size, so the frames are
# checked as well as the .bit.
set -euo pipefail
bit=$1 frames=$2 xdc=$3

fail() { echo "FAIL: $*" >&2; exit 1; }

size=$(stat -L -c %s "$bit")
# The header's `e` field gives the length of the configuration data that
# follows it: for any xc7a200t, the full configuration, 9,730,652 bytes.
byte() { od -An -tu1 -j "$1" -N 1 "$bit" | tr -d ' '; }
# Walk the header: after the 13-byte preamble come the fields a, b, c and
# d, each a key byte and a 2-byte big-endian length, then `e`.
off=13
for key in a b c d; do
  [[ "$(byte "$off")" == "$(printf '%d' "'$key")" ]] || fail "header field $key is not at $off"
  off=$(( off + 3 + $(byte $((off + 1))) * 256 + $(byte $((off + 2))) ))
done
[[ "$(byte "$off")" == "$(printf '%d' "'e")" ]] || fail "no configuration length field at $off"
e=$off
length=$(( $(byte $((e + 1))) * 16777216 + $(byte $((e + 2))) * 65536 + $(byte $((e + 3))) * 256 + $(byte $((e + 4))) ))
[[ "$length" == 9730652 ]] || fail "configuration is $length bytes, not 9730652"
[[ "$size" == $((e + 5 + length)) ]] || fail "file is $size bytes; header and data say $((e + 5 + length))"
[[ "$(head -c 13 "$bit" | od -An -tx1 | tr -d ' \n')" == 00090ff00ff00ff00ff0000001 ]] \
  || fail "the .bit header preamble is missing"
grep -aq "xc7a200tfbg484-2" "$bit" || fail "the part is not named in the header"
grep -aq "2000/01/01" "$bit" || fail "the header date was not fixed"
grep -aq "bazel-out" "$bit" && fail "the header names the output directory"
od -An -tx1 "$bit" | tr -d ' \n' | grep -q aa995566 || fail "no sync word"

lines=$(grep -c . "$(readlink -f "$frames")" || true)
(( lines > 1000 )) || fail "only $lines frame lines: the frames look empty"

# The translated constraints name each port on its own.
grep -q '^set_property IOSTANDARD LVCMOS33 \[get_ports reset\]$' "$xdc" \
  || fail "all_inputs was not expanded"
grep -q 'get_ports {' "$xdc" && fail "a braced port list survived translation"

echo "PASS: $size bytes, $lines frame lines"
