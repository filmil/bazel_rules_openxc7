#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Checks the openFPGALoader commands the programming targets run, without
# a board: OPENXC7_DRY_RUN=1 prints the command instead.
set -euo pipefail
prog=$1 flash=$2

fail() { echo "FAIL: $*" >&2; exit 1; }

export RUNFILES_DIR="${RUNFILES_DIR:-$PWD/..}"
p=$(OPENXC7_DRY_RUN=1 "$prog")
f=$(OPENXC7_DRY_RUN=1 "$flash")
echo "program: $p"
echo "flash:   $f"

for out in "$p" "$f"; do
  [[ "$out" == *"-c ft232"* ]] || fail "no cable in: $out"
  [[ "$out" == *"--fpga-part xc7a200tfbg484 "* ]] || fail "no part in: $out"
  [[ "$out" == *blinky_pnr.bit* ]] || fail "no bitstream in: $out"
done
[[ "$p" != *--write-flash* ]] || fail "device programming writes the flash"
[[ "$f" == *--write-flash* ]] || fail "flash programming does not write the flash"

# The tool the command names is there, and runs.
ofl=$(OPENXC7_DRY_RUN=1 "$prog" | awk '{print $1}')
[[ -x "$ofl" ]] || fail "openFPGALoader is not in the runfiles: $ofl"
"$ofl" --help >/dev/null 2>&1 || fail "openFPGALoader --help failed"
echo PASS
