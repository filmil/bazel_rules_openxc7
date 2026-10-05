<!-- SPDX-License-Identifier: Apache-2.0 -->
# Benchmark: openxc7 against Vivado

`bench.sh` times synthesis and place and route of the integration designs
with two flows:

| Flow | Targets | Tools |
|---|---|---|
| `openxc7` | `//:<design>_synth`, `//:<design>_pnr` (rules_openxc7) | Yosys, nextpnr-xilinx, prjxray, fpga-assembler |
| `vivado` | `//:<design>_emulated_synth`, `//:<design>_emulated_pnr` (rules_vivado), with `--//:emulate=false --@rules_vivado//:vivado_mode=hermetic` | Vivado 2025.2, installed by rules_vivado |

The designs:

| Design | What |
|---|---|
| `blinky` | an 8-bit counter on a LED: tool start-up, more than work |
| `picorv32` | one PicoRV32 RISC-V core with 1 KiB of RAM (`picorv32_soc.v`, `SOC_CORES=1`) |
| `picorv32_x16` | sixteen of them, the large case (`SOC_CORES=16`) |

For each flow and design, and for each of `REPEATS` repeats:

| Case | What is timed |
|---|---|
| `cold` | a new Bazel output base, an empty disk cache and no repository contents cache, so the tools are unpacked again: synthesis, then place and route on top of it |
| `noop` | the same build again, nothing changed |
| `edit_end` | one comment line appended to the design's source, then synthesis and place and route again, with the Bazel server warm. If the netlist comes out the same, Bazel reuses the earlier place and route |
| `edit_top` | one comment line put first in the source: it moves the source line numbers recorded in the netlist, so both steps run again |
| `warm` | a new output base, with the disk cache the cold run filled: what a CI job with a shared cache sees |

Downloads are not timed: every run shares one repository cache
(`REPO_CACHE`). Unpacking the tools into a new output base is timed, as
part of `cold` and `warm`: a fresh CI job pays for it too. Vivado's own installation is not timed either: it lives
in `/data/cache/vivado-install` and is made once, before the first run.

## Running it

Vivado runs need the hermetic installation that `MODULE.bazel` configures,
at the paths of the CI runners that offer `vivado` (filmil/serving#58):
the installer archive under `/data/tools/archives`, and writable
`/data/cache/vivado-install` and `/data/cache/rules_vivado`. instance-3
and eph4 have them, inside the act-bazel 1.2.2 job container.

From the integration directory, on such a machine and while it runs
nothing else:

```bash
bash bench/bench.sh /tmp/bench-out          # all flows and designs, 3 repeats
FLOWS=openxc7 DESIGNS=picorv32 REPEATS=1 bash bench/bench.sh /tmp/smoke
```

It writes `results.tsv` (one line per measurement, with the load average
before and after it), `env.txt` (the machine and the versions), and the
Bazel profile and log of every run under `profiles/`.

Machine load changes the numbers: run it on an idle machine, and read the
load columns before trusting a line.
