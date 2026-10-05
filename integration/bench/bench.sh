#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Times synthesis and place and route of the integration designs with the
# open toolchain (rules_openxc7) and with Vivado (rules_vivado, hermetic),
# from cold and warm caches. README.md in this directory says how to run it
# and what each case means.
#
# Run from the integration directory, on a machine with the hermetic Vivado
# of MODULE.bazel (the /data paths of filmil/serving#58):
#
#   bash bench/bench.sh OUT_DIR
#
# It drives Bazel itself, once per measurement, each time with an output
# base of its own, so it is run with bash rather than `bazel run`.
#
# Environment:
#   FLOWS     flows to measure, default "openxc7 vivado"
#   DESIGNS   designs, default "blinky picorv32 picorv32_x16"
#   REPEATS   runs of each case, default 3
#   REPO_CACHE  Bazel repository cache to share between runs, so that
#             downloads are not timed; default /data/cache/bazel/repo
#   BAZEL_FLAGS extra flags for every build, for example
#             --override_module=rules_vivado=/path/to/a/checkout
#
# Output, in OUT_DIR: results.tsv (one line per measurement), env.txt (the
# machine and the tool versions), and the Bazel profile of each run.

set -euo pipefail

out="${1:?usage: bench.sh OUT_DIR}"
flows="${FLOWS:-openxc7 vivado}"
designs="${DESIGNS:-blinky picorv32 picorv32_x16}"
repeats="${REPEATS:-3}"
repo_cache="${REPO_CACHE:-/data/cache/bazel/repo}"
read -r -a bazel_flags <<< "${BAZEL_FLAGS:-}"

[[ -f MODULE.bazel && -f BUILD.bazel && -d bench ]] \
    || { echo "run from the integration directory" >&2; exit 1; }

mkdir -p "$out/profiles"
out="$(cd "$out" && pwd)"
results="$out/results.tsv"
work="$out/work"
mkdir -p "$work"

# The design's source file, edited for the "edit" case.
source_of() {
    case "$1" in
        blinky) echo blinky.sv ;;
        picorv32*) echo picorv32_soc.v ;;
        *) echo "unknown design $1" >&2; return 1 ;;
    esac
}

# The flags and target prefix of a flow.
flags_of() {
    case "$1" in
        openxc7) echo "" ;;
        vivado) echo "--//:emulate=false --@rules_vivado//:vivado_mode=hermetic" ;;
        *) echo "unknown flow $1" >&2; return 1 ;;
    esac
}
target_of() {  # flow design step
    case "$1" in
        openxc7) echo "//:$2_$3" ;;
        vivado) echo "//:$2_emulated_$3" ;;
    esac
}

{
    echo "date: $(date -u +%FT%TZ)"
    echo "host: $(hostname)"
    echo "cpus: $(nproc)"
    echo "memory: $(awk '/MemTotal/ {printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
    echo "kernel: $(uname -r)"
    echo "bazel: $(bazel --version 2>/dev/null)"
    echo "commit: $(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
    echo "flows: $flows"
    echo "designs: $designs"
    echo "repeats: $repeats"
    echo "bazel flags: ${BAZEL_FLAGS:-}"
} > "$out/env.txt"

printf 'flow\tdesign\tcase\trepeat\tstep\tseconds\texit\tload1_before\tload1_after\n' > "$results"

# One timed `bazel build` with its own output base. Appends a results line.
# Args: flow design case repeat step output_base disk_cache_or_empty
timed_build() {
    local flow="$1" design="$2" case="$3" rep="$4" step="$5" ob="$6" dc="$7"
    local target; target="$(target_of "$flow" "$design" "$step")"
    local -a extra=()
    [[ -n "$dc" ]] && extra+=("--disk_cache=$dc")
    # Bazel keeps unpacked repositories next to the repository cache, and
    # would reuse them across output bases. A cold build unpacks its tools.
    [[ "$case" == cold ]] && extra+=("--repo_contents_cache=")
    local profile="$out/profiles/${flow}.${design}.${case}.${rep}.${step}.json.gz"
    local load_before load_after start end rc
    load_before="$(cut -d' ' -f1 /proc/loadavg)"
    start="$(date +%s.%N)"
    set +e
    # shellcheck disable=SC2046
    bazel --output_base="$ob" build $(flags_of "$flow") \
        --repository_cache="$repo_cache" \
        "${bazel_flags[@]}" "${extra[@]}" \
        --profile="$profile" \
        "$target" > "$out/profiles/${flow}.${design}.${case}.${rep}.${step}.log" 2>&1
    rc=$?
    set -e
    end="$(date +%s.%N)"
    load_after="$(cut -d' ' -f1 /proc/loadavg)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$flow" "$design" "$case" "$rep" "$step" \
        "$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }')" \
        "$rc" "$load_before" "$load_after" >> "$results"
    return $rc
}

for flow in $flows; do
    for design in $designs; do
        src="$(source_of "$design")"
        for rep in $(seq "$repeats"); do
            tag="${flow}.${design}.${rep}"
            dc="$work/disk.$tag"
            rm -rf "$dc"

            # cold: a new output base and an empty disk cache. Synthesis
            # first, then place and route, which reuses the synthesis.
            ob="$work/ob.$tag.cold"
            timed_build "$flow" "$design" cold "$rep" synth "$ob" "$dc" || true
            timed_build "$flow" "$design" cold "$rep" pnr "$ob" "$dc" || true

            # noop: the same output base again, nothing changed.
            timed_build "$flow" "$design" noop "$rep" pnr "$ob" "$dc" || true

            # edit_end: a comment line appended to the design. The netlist
            # may come out the same, and then Bazel reuses the place and
            # route from before.
            cp "$src" "$work/$src.orig"
            echo "// bench edit $tag" >> "$src"
            timed_build "$flow" "$design" edit_end "$rep" synth "$ob" "$dc" || true
            timed_build "$flow" "$design" edit_end "$rep" pnr "$ob" "$dc" || true
            cp "$work/$src.orig" "$src"

            # edit_top: a comment line put first. It moves every source line
            # number recorded in the netlist, so both steps run again.
            { echo "// bench edit $tag"; cat "$work/$src.orig"; } > "$src"
            timed_build "$flow" "$design" edit_top "$rep" synth "$ob" "$dc" || true
            timed_build "$flow" "$design" edit_top "$rep" pnr "$ob" "$dc" || true
            cp "$work/$src.orig" "$src"
            bazel --output_base="$ob" shutdown >/dev/null 2>&1 || true
            rm -rf "$ob"

            # warm: a new output base, with the disk cache the cold run
            # filled (the original source again, so its entries match).
            ob="$work/ob.$tag.warm"
            timed_build "$flow" "$design" warm "$rep" synth "$ob" "$dc" || true
            timed_build "$flow" "$design" warm "$rep" pnr "$ob" "$dc" || true
            bazel --output_base="$ob" shutdown >/dev/null 2>&1 || true
            rm -rf "$ob" "$dc"
        done
    done
done

echo "results: $results"
