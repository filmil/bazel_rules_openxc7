#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Compares fpga-as's bitstream with xc7frames2bit's for the same FASM. The
# configuration data must match except in the low 13 bits of a word, where
# a 7-series frame keeps its ECC: xc7frames2bit computes it and fpga-as
# leaves it zero. Anything else is a real difference.
set -euo pipefail
fa=$1 ref=$2

fail() { echo "FAIL: $*" >&2; exit 1; }

# Where the configuration data starts: after the 13-byte preamble, the
# fields a to d (key, 2-byte length, value), and e (key, 4-byte length).
data_start() {
  local f=$1 off=13 key
  for key in a b c d; do
    off=$(( off + 3 + $(od -An -tu1 -j $((off + 1)) -N 1 "$f") * 256 + $(od -An -tu1 -j $((off + 2)) -N 1 "$f") ))
  done
  echo $(( off + 5 ))
}

fs=$(data_start "$fa") rs=$(data_start "$ref")
fsize=$(stat -L -c %s "$fa") rsize=$(stat -L -c %s "$ref")
(( fsize - fs == rsize - rs )) || fail "configuration lengths differ: $((fsize - fs)) and $((rsize - rs))"

# Compare the data only, byte by byte; cmp -l prints 1-based offsets and
# octal values. Each difference must be in the last two bytes of a word,
# and in the next-to-last byte, only in its low 5 bits.
# cmp exits 1 when the files differ, which they are expected to.
report=$({ cmp -l <(tail -c +$((fs + 1)) "$fa") <(tail -c +$((rs + 1)) "$ref") || true; } | awk '
  { pos = $1 - 1; a = strtonum("0" $2); b = strtonum("0" $3); n++
    if (pos % 4 == 3) next
    if (pos % 4 == 2 && int(a / 32) == int(b / 32)) next
    bad++; if (bad <= 5) printf "byte %d: %o vs %o\n", pos, a, b }
  END { printf "differing bytes: %d, outside the ECC bits: %d\n", n, bad + 0 }')
echo "$report"
grep -q "outside the ECC bits: 0$" <<<"$report" || fail "fpga-as differs outside the ECC bits"
echo PASS
