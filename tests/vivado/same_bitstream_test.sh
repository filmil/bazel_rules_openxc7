#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Checks that two .bit files hold the same configuration data, whatever
# their headers say.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

# The configuration data starts after the 13-byte preamble, the fields a
# to d (key, 2-byte length, value) and e (key, 4-byte length).
data_start() {
  local f=$1 off=13 key
  for key in a b c d; do
    off=$(( off + 3 + $(od -An -tu1 -j $((off + 1)) -N 1 "$f") * 256 + $(od -An -tu1 -j $((off + 2)) -N 1 "$f") ))
  done
  echo $(( off + 5 ))
}

b=$1
shift
a=""
for f in "$@"; do
  [[ "$f" == *.bit ]] && a=$f
done
[[ -n "$a" ]] || fail "no .bit among: $*"
cmp <(tail -c +$(( $(data_start "$a") + 1 )) "$a") <(tail -c +$(( $(data_start "$b") + 1 )) "$b") \
  || fail "the configuration data differs"
echo "PASS: $(stat -L -c %s "$a") and $(stat -L -c %s "$b") bytes, same configuration"
