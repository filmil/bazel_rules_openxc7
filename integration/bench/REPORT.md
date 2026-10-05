<!-- SPDX-License-Identifier: Apache-2.0 -->
# Report: openxc7 against Vivado

This report answers issue #11: how long synthesis and place and route take
with the open toolchain (rules_openxc7) and with Vivado (rules_vivado), on
the same designs, from cold and warm caches. It also compares what the two
flows produce. `NOTES.md` records each problem found on the way; this
report cites it by number.

## Summary

* **Small designs build 2 to 3 times faster with openxc7.** From a cold
  cache, blinky takes 80 s with openxc7 and 194 s with Vivado; one
  PicoRV32 core takes 92 s and 222 s. Vivado has a fixed cost of about
  three minutes per build, whatever the design's size.
* **Large designs build faster with Vivado.** Sixteen PicoRV32 cores take
  587 s with openxc7 and 334 s with Vivado. nextpnr's place and route
  grows fastest: 37 s for blinky, 56 s for one core, 483 s for sixteen.
* **After an edit, openxc7 is faster at every size measured, except a
  large design edited so that its netlist changes.** Bazel reuses
  openxc7's place and route when the netlist is unchanged, for example
  after a comment at the end of a file: 7 to 76 s against Vivado's 150 to
  290 s. Vivado's place and route reruns after any change to the
  sources.
* **With a warm disk cache, both flows rebuild in about 8 to 10 s.** A
  no-op build takes under a second with either.
* **Vivado produces the better circuit.** For the same design it uses
  about half the LUTs (14,216 against 26,668 for sixteen cores), meets
  hold time where nextpnr leaves small violations, and reaches a somewhat
  higher clock (about 144 MHz against nextpnr's estimate of 131 MHz for
  sixteen cores).
* **Three defects were fixed to run the benchmark**, two in rules_openxc7
  and one in rules_vivado (`NOTES.md`, 1 to 3), and the benchmark design
  was fixed once, after Vivado removed it as constant (`NOTES.md`, 4).

## Setup

Every measurement in this report ran on one machine, in one container,
one at a time.

### Machine

| | |
|---|---|
| Host | instance-3, a Google Compute Engine VM |
| Machine type | `e2-custom-20-49152`, zone `us-central1-c` |
| CPU | AMD EPYC 7B12, 20 vCPUs (10 cores, 2 threads each) |
| Memory | 47.0 GiB |
| Kernel | 6.8.0-1069-gcp |
| Disk for builds and caches | a 1,000 GB pd-balanced persistent disk, ext4. It holds the output bases, the disk caches, the repository cache and the Vivado installation |
| Disk for the container and the Vivado installer archive | the boot disk, a persistent disk of a type not visible from the VM |
| Docker | 29.1.3, rootful |

### Container

Each pass ran in a fresh container of `docker.io/filipfilmar/act-bazel:1.2.2`,
the image of the CI jobs that run Vivado (filmil/serving#56), as root,
without `--privileged` and without CPU or memory limits. The mounts were
those of the CI runner's job containers, plus a scratch directory:

| Container path | What | Mode |
|---|---|---|
| `/data/cache/bazel` | Bazel's caches; `/data/cache/bazel/repo` is the repository cache | read-write |
| `/etc/bazel.bazelrc` | the CI bazelrc, below | read-only |
| `/data/cache/rules_vivado` | rules_vivado's cache, also mounted read-only at its host path | read-write |
| `/data/cache/vivado-install` | rules_vivado's Vivado install cache | read-write |
| `/data/tools/archives/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_1.tar` | the Vivado 2025.2 installer archive, 103 GB | read-only |
| `/bench` | the clone of this repository and the output | read-write |

`/etc/bazel.bazelrc` held:

```
build --disk_cache=/data/cache/bazel/disk
build --repository_cache=/data/cache/bazel/repo
build --experimental_disk_cache_gc_max_size=250G
build --experimental_disk_cache_gc_max_age=15d
```

`bench.sh` overrides the first two lines on every command line, so only
the garbage collection limits applied. Each measurement's disk cache was
new and far smaller than the 250 GB limit.

### Software

| | Version |
|---|---|
| Bazel | 9.2.0 |
| rules_openxc7 | this repository, at the commit of each pass (below) |
| Yosys | 0.69+154, from OSS CAD Suite 2026-09-27 |
| nextpnr-xilinx, prjxray, fasm2frames | the openXC7 prebuilt tools of 2026-09-27 (FPGAwars tools-openxc7); nextpnr-xilinx e860c9c8 |
| rules_vivado | 3.16.2 |
| Vivado | 2025.2 (64-bit), Artix-7 only, installed by rules_vivado |
| Part | `xc7a200tfbg484-2` (Artix-7 200T), every design |
| Constraints | `alinx-a200t-b.xdc`: one 100 MHz clock, three pins |

### Designs

| Design | Source | Logic |
|---|---|---|
| `blinky` | `blinky.sv` | an 8-bit counter on a LED |
| `picorv32` | `picorv32_soc.v`, `SOC_CORES=1` | one PicoRV32 RV32I core with 1 KiB of RAM and a LED register |
| `picorv32_x16` | `picorv32_soc.v`, `SOC_CORES=16` | sixteen of those, core i counting in steps of i + 1 |

PicoRV32 is `third_party/picorv32`, unchanged, at commit `ef203c2b`.

### Passes

| Pass | Commit | Started (UTC) | Designs | Repeats | Used in this report |
|---|---|---|---|---|---|
| 1 | `c0dd902` | 2026-10-05 04:39 | all three | 1 | blinky and one core. Not its `vivado blinky cold synth`, which includes the one-off Vivado installation (`NOTES.md`, 5). Not its sixteen-core lines (old design) |
| 2 | `9cdc7fa` | 2026-10-05 07:24 | all three | 2 | blinky and one core. Not its sixteen-core lines (old design) |
| 3 | `d42c18b` | 2026-10-05 10:05 | `picorv32_x16` | 3 | sixteen cores |

Between the commits, the designs used here did not change: `d42c18b`
changed only the step of cores 1 to 15, and core 0, the only core of
`picorv32`, kept its program word. Pass 1 had no separate install step;
passes 2 and 3 began with it (8.7 s and 9.3 s: the installation was
cached).

The CI runner was stopped during every pass. The machine also ran a remote
desktop session (15 to 20 % of one CPU), monitoring and network agents,
and the session that drove the benchmark, which polled the run every 20 s.
The one-minute load average, recorded before and after each measurement,
stayed between 1.1 and 9.2 on 20 vCPUs. `data/` holds every line.

### How each measurement ran

`bench.sh` runs one `bazel build` per measurement and times it with the
wall clock, from the start of the command to its end, including the Bazel
server's start where there is one. For flow F, design D, repeat r:

```
bazel --output_base=<out>/work/ob.F.D.r.<cold|warm> build \
    <flow flags> \
    --repository_cache=/data/cache/bazel/repo \
    --disk_cache=<out>/work/disk.F.D.r \
    [--repo_contents_cache=]          # cold only
    --profile=<out>/profiles/F.D.<case>.r.<step>.json.gz \
    <target>
```

| Flow | Flow flags | Synthesis target | Place and route target |
|---|---|---|---|
| openxc7 | none | `//:D_synth` | `//:D_pnr` |
| Vivado | `--//:emulate=false --@rules_vivado//:vivado_mode=hermetic` | `//:D_emulated_synth` | `//:D_emulated_pnr` |

The place and route target ends in the bitstream, so its time includes
bitstream generation. Downloads were never timed: the repository cache
already held every archive.

The cases, in the order they ran for each flow, design and repeat:

| Case | Output base | Disk cache | Server | Change to the sources | Steps timed |
|---|---|---|---|---|---|
| `cold` | new | new, empty | started by the first command | none | synthesis, then place and route on top of it |
| `noop` | the cold one | the cold one | running | none | place and route |
| `edit_end` | the cold one | the cold one | running | one comment line appended to the design's source | synthesis, then place and route |
| `edit_top` | the cold one | the cold one | running | the same file, with the comment line first instead | synthesis, then place and route |
| `warm` | new | the one the cold run filled, original source | started by the first command | none | synthesis, then place and route |

* **Cold** passes `--repo_contents_cache=`, so the tools are unpacked into
  the new output base again; with Bazel 9's default it reuses an earlier
  unpacking (`NOTES.md`, Method). Vivado's installation is the exception:
  rules_vivado keeps it outside every output base, so no cold build
  installs it.
* **Warm** keeps the repository contents cache and gets the cold run's
  disk cache: what a CI job sees with shared caches. The first warm run in
  a pass also filled the repository contents cache (`NOTES.md`, 6).
* **The edit cases** change the design's own source file: `blinky.sv` or
  `picorv32_soc.v`. A comment at the end leaves Yosys's netlist the same,
  so Bazel reuses the place and route; a comment first moves the source
  line numbers recorded in the netlist, so both steps run.
* After the edit cases the script restores the source, shuts the server
  down and deletes the output base. After the warm case it deletes the
  output base and the disk cache.

The result quality figures come from separate, untimed builds of the same
commits on the same machine, with a default output base.

## Results: build time

Seconds, wall clock. Each cell is the median, with the range of the
repeats in parentheses. "Total" is synthesis plus place and route of the
same repeat: the time from source to bitstream. `noop` has no synthesis
step.

### blinky

| Case | openxc7 synth | openxc7 PnR | openxc7 total | Vivado synth | Vivado PnR | Vivado total | n (openxc7/Vivado) |
|---|---|---|---|---|---|---|---|
| cold | 41.2 (30.3–44.6) | 36.9 (30.7–38.3) | 79.5 (61.0–81.5) | 102.0 (98.5–105.5) | 94.2 (90.7–132.9) | 194.4 (189.2–199.7) | 3/3 |
| warm | 7.4 (7.1–30.9) | 2.7 (2.4–4.2) | 10.1 (9.5–35.1) | 7.0 (7.0–18.3) | 0.8 (0.8–1.2) | 7.8 (7.8–19.5) | 3/3 |
| edit_top | 6.6 (6.2–8.3) | 16.2 (15.3–17.4) | 22.4 (21.9–25.7) | 54.3 (52.0–57.7) | 95.7 (95.7–109.4) | 150.0 (147.7–167.1) | 3/3 |
| edit_end | 6.3 (6.2–6.6) | 0.4 (0.4–0.4) | 6.7 (6.6–7.0) | 54.4 (52.0–59.6) | 95.1 (90.5–103.3) | 149.5 (142.5–162.9) | 3/3 |
| noop | – | 0.7 (0.4–0.9) | 0.7 (0.4–0.9) | – | 0.3 (0.2–0.4) | 0.3 (0.2–0.4) | 3/3 |

### PicoRV32, one core

| Case | openxc7 synth | openxc7 PnR | openxc7 total | Vivado synth | Vivado PnR | Vivado total | n (openxc7/Vivado) |
|---|---|---|---|---|---|---|---|
| cold | 35.4 (34.5–35.5) | 56.2 (51.3–60.7) | 91.7 (85.8–96.1) | 109.0 (108.8–123.0) | 112.6 (104.2–164.0) | 221.6 (213.0–287.0) | 3/3 |
| warm | 7.6 (7.1–14.6) | 2.2 (2.1–4.3) | 9.8 (9.2–18.9) | 7.5 (7.3–11.0) | 0.9 (0.8–1.4) | 8.4 (8.1–12.4) | 3/3 |
| edit_top | 12.7 (10.8–12.8) | 39.6 (33.0–65.7) | 52.3 (43.8–78.5) | 65.6 (63.8–70.2) | 107.1 (106.4–139.8) | 172.7 (170.2–210.0) | 3/3 |
| edit_end | 13.1 (10.7–13.4) | 0.4 (0.4–0.5) | 13.5 (11.1–13.9) | 65.5 (63.9–78.7) | 113.3 (109.1–119.7) | 178.8 (173.0–198.4) | 3/3 |
| noop | – | 0.5 (0.4–0.5) | 0.5 (0.4–0.5) | – | 0.3 (0.3–0.4) | 0.3 (0.3–0.4) | 3/3 |

### PicoRV32, sixteen cores

| Case | openxc7 synth | openxc7 PnR | openxc7 total | Vivado synth | Vivado PnR | Vivado total | n (openxc7/Vivado) |
|---|---|---|---|---|---|---|---|
| cold | 104.4 (102.6–119.5) | 482.7 (459.3–491.9) | 587.1 (578.8–594.5) | 135.2 (134.0–139.7) | 200.2 (191.7–205.2) | 334.2 (326.9–344.9) | 3/3 |
| warm | 7.6 (7.4–20.2) | 2.6 (2.3–3.2) | 10.2 (9.7–23.4) | 8.1 (7.5–8.8) | 1.0 (0.9–1.1) | 9.0 (8.5–9.9) | 3/3 |
| edit_top | 76.1 (72.0–114.9) | 437.1 (417.2–457.3) | 513.2 (489.2–572.2) | 84.2 (82.2–84.4) | 198.3 (196.4–199.4) | 280.6 (280.5–283.8) | 3/3 |
| edit_end | 76.0 (72.2–82.4) | 0.3 (0.3–0.4) | 76.3 (72.5–82.8) | 83.2 (82.5–129.6) | 205.0 (196.3–206.3) | 289.5 (278.8–334.6) | 3/3 |
| noop | – | 0.4 (0.3–1.0) | 0.4 (0.3–1.0) | – | 0.3 (0.3–0.5) | 0.3 (0.3–0.5) | 3/3 |

### What the numbers show

* **Vivado's fixed cost.** blinky, eight flip-flops, takes Vivado 102 s
  to synthesise and 94 s to place and route. Sixteen cores take 135 s and
  200 s. Most of Vivado's time at these sizes is the cost of starting it,
  creating a project and writing reports.
* **openxc7 scales with the design.** Its cold place and route grows from
  37 s (blinky) to 56 s (one core) to 483 s (sixteen cores), and its
  synthesis from 41 s to 104 s.
* **The crossover** is between one core (890 LUTs in Vivado's terms) and
  sixteen (14,216).
* **Edits.** openxc7's reuse of place and route after a comment at the end
  is an effect of Bazel's caching, not of either tool: the synthesis
  output is the same, so its consumers do not run. rules_vivado's place
  and route depends on a directory that holds copies of the sources, so
  it runs after any edit. A real edit changes the logic and behaves like
  `edit_top`.
* **Repeatability.** Most of Vivado's times varied by a few percent
  between repeats, with single slow runs up to 50 % longer (blinky's cold
  place and route: 90.7 s to 132.9 s). openxc7's varied more: its sixteen-core place and route ranged
  from 459 s to 492 s here, and from 431 s to 653 s for the old design in
  pass 2. nextpnr's runtime depends on its placement.

## Results: what the flows produce

From the untimed builds: Vivado's `report_utilization` after placement
and `report_timing_summary` after routing, and nextpnr's and Yosys's logs.

| | openxc7, 1 core | Vivado, 1 core | openxc7, 16 cores | Vivado, 16 cores |
|---|---|---|---|---|
| LUTs | 1,671 | 890 | 26,668 | 14,216 |
| Registers | 553 | 555 | 8,852 | 8,880 |
| Block RAM (RAMB18) | 1 | 1 | 16 | 16 |
| Speed at the 100 MHz constraint | 147 MHz (nextpnr, after routing) | about 165 MHz (setup slack 3.955 ns) | 131 MHz (nextpnr, after routing) | about 144 MHz (setup slack 3.063 ns) |
| Hold | one violation, −0.02 ns | met (+0.058 ns) | seven violations, worst −0.05 ns | met (+0.057 ns) |

* Vivado's netlist uses about half the LUTs. The registers and RAMs
  match, so the difference is in logic optimisation and LUT mapping.
* The speeds come from different timing models, nextpnr's timing analysis
  and Vivado's signoff analysis, so they compare only roughly. nextpnr
  also prints a figure after placement (180 MHz for one core, 150 MHz for
  sixteen); the table gives the one after routing, which was the same in
  every build.
* nextpnr does not repair hold time (`NOTES.md`, 2). Its bitstreams were
  not tried on a board, so whether its hold violations fail in silicon is
  not known.
* Vivado proved the old sixteen-core design's output constant and removed
  all of it; Yosys did not (`NOTES.md`, 4). Vivado optimises further.

## Problems found

`NOTES.md` has the details of each.

1. Yosys left a `$buf` cell that nextpnr cannot place. Fixed in
   rules_openxc7: a techmap after synthesis.
2. nextpnr failed the build on a timing violation; Vivado reports one and
   goes on. rules_openxc7 now passes `--timing-allow-fail`.
3. rules_vivado's place and route wrote through symlinks into the design's
   sources and made them read-only. Fixed in rules_vivado 3.16.2
   (filmil/bazel_rules_vivado#149).
4. Vivado removed the first sixteen-core design as constant. The design
   now gives each core a different step.
5. The one-off Vivado installation took 6,034.6 s on an empty cache, and
   left a 96 GiB copy of the installer archive in the repository cache.
6. The first warm run of a pass fills the repository contents cache.

## Limits of this comparison

* One machine, one container, one part. A shared cloud VM varies from
  hour to hour; three repeats show the spread, not a distribution.
* The designs are small to medium: at most 10.6 % of the part's LUTs in
  Vivado's terms. Larger designs, and designs with tight timing, were not
  measured.
* Vivado ran from rules_vivado's project flow, which writes reports and a
  project at each step. A non-project Tcl flow may start faster. Both
  flows ran with their rules' default settings.
* The comparison measures the rules as a user meets them: Bazel, the
  rules and the tools together.

## Reproducing it

`README.md` says how to run `bench.sh`. The raw results are in `data/`:
`passN.results.tsv` and `passN.env.txt`. The Bazel profiles and logs of
every measurement, and the tools' reports, were kept outside the
repository.
