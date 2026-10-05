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
benchmark needs a rules_vivado release with this fix.
