// SPDX-License-Identifier: Apache-2.0
//
// A benchmark design: SOC_CORES PicoRV32 cores (third_party/picorv32), each
// with 1 KiB of on-chip RAM and an LED register, on blinky's pins.
//
// Each core runs a four-instruction program from its RAM: it counts in x1
// and stores the count to the LED register at 0x1000, forever. The board's
// LED shows the exclusive or of bit 20 of every core's LED register, so no
// core can be removed by synthesis as unused.
//
// SOC_CORES is set with a define: 1 for the small case, 16 for the large
// one. The ports are blinky's, so alinx-a200t-b.xdc applies unchanged.

`ifndef SOC_CORES
`define SOC_CORES 1
`endif

module picorv32_soc (
    output wire out,
    input  wire clk,
    input  wire reset
);
    wire [`SOC_CORES-1:0] led_bits;

    genvar i;
    generate
        for (i = 0; i < `SOC_CORES; i = i + 1) begin : core
            picorv32_tile tile (
                .clk(clk),
                .resetn(~reset),
                .led(led_bits[i])
            );
        end
    endgenerate

    assign out = ^led_bits;
endmodule

// One core, its RAM and its LED register.
module picorv32_tile (
    input  wire clk,
    input  wire resetn,
    output wire led
);
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 cpu (
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'b0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'b0)
    );

    // 256 words of RAM. The program:
    //   0x0: lui  x2, 0x1        x2 = 0x1000, the LED register
    //   0x4: addi x1, x1, 1
    //   0x8: sw   x1, 0(x2)
    //   0xc: j    0x4
    reg [31:0] ram [0:255];
    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) ram[k] = 32'h0000_0013;  // nop
        ram[0] = 32'h0000_1137;
        ram[1] = 32'h0010_8093;
        ram[2] = 32'h0011_2023;
        ram[3] = 32'hff9f_f06f;
    end

    reg [31:0] led_reg;
    wire       is_led = mem_addr[12];

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (!resetn) begin
            led_reg <= 32'b0;
        end else if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;
            mem_rdata <= ram[mem_addr[9:2]];
            if (is_led) begin
                if (|mem_wstrb) led_reg <= mem_wdata;
            end else begin
                if (mem_wstrb[0]) ram[mem_addr[9:2]][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) ram[mem_addr[9:2]][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) ram[mem_addr[9:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) ram[mem_addr[9:2]][31:24] <= mem_wdata[31:24];
            end
        end
    end

    assign led = led_reg[20];
endmodule
