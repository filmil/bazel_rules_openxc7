<!-- SPDX-License-Identifier: Apache-2.0 -->
# Analysis notes: openxc7 against Vivado

Differences between the two flows found while setting up the benchmark
(issue #11). Each entry says what was seen, why, and what was done. The
report cites these notes.

## 1. Yosys leaves a `$buf` cell that nextpnr-xilinx cannot place

**Seen.** PicoRV32 (1 core) failed place and route:

```
ERROR: Unable to place cell '$auto$rtlil_bufnorm.cc:460:bufNormalize$60655',
no BELs remaining to implement cell type '$buf'
```

**Why.** Yosys 0.69's buffer normalisation leaves one 32-bit `$buf` after
`synth_xilinx`, on a wire that only renames another
(`wire [31:0] dbg_mem_addr = mem_addr;` in picorv32.v). `opt_clean -purge`
and `bufnorm -reset` do not remove it. blinky has no such wire, so it never
showed. Vivado has no such failure: its synthesis keeps no generic cells.

**Done.** Both Yosys scripts (`openxc7/private/synthesis.bzl` and the
Vivado emulator) now run `techmap -map +/techmap.v t:$buf; opt_clean`
after `synth_xilinx`, which turns the cell into a connection.

## 2. nextpnr fails the build on a timing violation; Vivado does not

**Seen.** With 1 fixed, PicoRV32 failed again, on one hold violation:

```
ERROR: Hold/min time violation for clock 'posedge core[0].tile.clk':
  clk-to-q 0.30  routing 0.35  -> core[0].tile.ram.0.0.DIBDI11  hold -0.67
  slack -0.02 ns
Info: Max frequency for clock 'core[0].tile.clk': 147.17 MHz (PASS at 100.00 MHz)
```

**Why.** Two differences. nextpnr-xilinx ends with an error when any timing
check fails, where Vivado's `route_design` reports the violation and goes
on to the bitstream. And nextpnr does not repair hold time, where Vivado's
router adds delay to short paths until hold is met. A flip-flop driving a
block RAM's data input directly is such a short path.

**Done.** Both nextpnr calls pass `--timing-allow-fail`, as Vivado
behaves: the violation stays in the place and route log (and in the
emulator's `report_timing_summary`), and the build goes on. Whether that
hold miss is real on silicon, or an artefact of nextpnr's block RAM timing
model, is not established here; the Vivado run of the same design is the
comparison.

**For the report.** The Vivado-routed design is expected to meet hold.
Timing closure is part of the comparison, not only run time.

## 3. rules_vivado's place and route rewrote the design's sources

This one is a defect in rules_vivado, not a difference between the tools,
but it hits both of its flows (emulated and real Vivado).

**Seen.** The emulated PicoRV32 place and route built once, then failed on
every later build:

```
cp: cannot create regular file '.../execroot/_main/picorv32_soc.v':
Permission denied
```

Afterwards `picorv32_soc.v` and `blinky.sv` in the source tree had mode
555, where git has 644.

**Why.** The place and route action copies the synthesis output, which
holds copies of the sources, into its working directory with
`cp -R -a --dereference`. In this module the sources are in the root
package, so each has the same path in the working directory, where it is
a symlink to the user's file. `cp` wrote through the symlink into the
source tree, and `-a` set the read-only mode of the copy. rules_vivado's
own tests keep their sources in subpackages, so they never hit it.

**Done.** filmil/bazel_rules_vivado#149 passes `--remove-destination`,
which replaces the symlink instead of writing through it. Checked here
with `--override_module=rules_vivado=` on that branch: three emulated
place and route targets rebuilt twice, and the sources kept mode 644. The
fix is in rules_vivado 3.16.2, which this module now uses.

## Method: what "cold" means

Two effects found in a smoke run of `bench.sh` (openxc7, blinky, on
eph1) change what a case measures. The script handles both.

* **Bazel 9 reuses unpacked tools across output bases.** The repository
  contents cache, next to the repository cache, keeps each unpacked
  repository. The first cold synthesis took 60.6 s, the second 8.8 s,
  because the second did not unpack oss-cad-suite again. The `cold` case
  now passes `--repo_contents_cache=`. `warm` keeps that cache, as a CI
  job with shared caches would.
* **A comment at the end of a source may change nothing downstream.**
  After a comment was appended to `blinky.sv`, synthesis ran again
  (4.0 s), Yosys wrote the same netlist, and Bazel reused the place and
  route (0.3 s). A comment put first moves the source line numbers that
  Yosys records, so place and route runs again (10.6 s). The script times
  both, as `edit_end` and `edit_top`. rules_vivado's place and route
  depends on the synthesis output directory, which holds copies of the
  sources, so it is expected to run again after any edit (see 3); the
  Vivado runs will show whether it does.

## 4. Vivado's 16-core build barely costs more than its 1-core build

**Seen.** Pass 1 on instance-3 (one repeat), cold, in seconds:

| Flow | 1 core synth / pnr | 16 cores synth / pnr |
|---|---|---|
| openxc7 | 34.5 / 51.3 | 94.7 / 485.0 |
| Vivado | 123.0 / 164.0 | 130.8 / 187.8 |

Yosys keeps all sixteen cores: its cell counts are exactly 16 times the
1-core ones (96 to 1,536 CARRY4, 1 to 16 RAMB18E1).

**Suspected.** The benchmark design may not be what Vivado builds. All
sixteen cores are identical, run the same program from the same reset,
and the LED is the exclusive or of sixteen identical bits, which is always
0. A tool that proves the cores equivalent can merge them, or remove them
all. Vivado's synthesis merges equivalent registers by default; Yosys
did not here.

**Open.** Vivado's utilisation reports for both designs will settle it;
instance-3 builds them after pass 2. If Vivado did merge the cores, the
16-core design needs cores that differ (for example a different increment
per core) and an output that depends on every one, and its numbers are
measured again.

## 5. The one-off Vivado installation, and what it leaves behind

Pass 1's first Vivado build, `vivado.blinky.cold.synth`, took 6,034.6 s.
It includes the one-off installation: copying the 103 GB installer
archive (about 31 MB/s), unpacking it and running the installer. It is
left out of every comparison. Afterwards the install cache held 52 GB with
its `COMPLETE` marker, and fresh output bases reused it: the next
Vivado synthesis in a fresh output base, `vivado.blinky.warm.synth`, took
18.3 s.

The installation also left a 96 GiB copy of the installer archive in
Bazel's repository cache (`/data/cache/bazel/repo`), which nothing cleans
up. rules_vivado could avoid that copy for a `file://` archive; that is a
separate change.

## 6. The first warm run in a pass unpacks the open tools

`openxc7.blinky.warm.synth` took 30.9 s in pass 1, against 7.6 s and 11.2 s
for the larger designs. Cold runs turn off the repository contents cache
(see Method), so the first warm run of a pass is the first to fill it: it
unpacks oss-cad-suite. Later warm runs reuse it. The cache lives with the
repository cache and outlives a pass, so pass 2 does not pay it.
