// SPDX-License-Identifier: Apache-2.0
//
// The open flow's first board check, on the Alinx AX7A200B: every tenth of
// a second or so, the serial line says "openxc7 hello <n>" with n counting
// up in hex, at 115200 baud, 8N1, and the four LEDs count too. A program
// on the board's host can read the line, so the check needs nobody to look
// at the board.
module uart_hello #(
    // 200 MHz / 115200 = 1736.1; the 0.006 per cent error is far inside
    // what a UART tolerates.
    parameter integer BAUD_DIV = 1736,
    // About a tenth of a second between lines.
    parameter integer GAP = 20_000_000
) (
    input  wire sys_clk_p,   // 200 MHz, differential
    input  wire sys_clk_n,
    output reg  uart_tx = 1'b1,
    output wire led1,
    output wire led2,
    output wire led3,
    output wire led4
);
    wire clk;
    IBUFDS clk_buf (.I(sys_clk_p), .IB(sys_clk_n), .O(clk));

    // "openxc7 hello " then four hex digits, CR, LF: 20 bytes.
    localparam integer LEN = 20;
    reg [15:0] n = 16'h0000;

    function [7:0] hex(input [3:0] d);
        hex = d < 10 ? 8'h30 + d : 8'h61 + d - 10;
    endfunction

    function [7:0] char(input [4:0] i, input [15:0] v);
        case (i)
            0: char = "o";  1: char = "p";  2: char = "e";  3: char = "n";
            4: char = "x";  5: char = "c";  6: char = "7";  7: char = " ";
            8: char = "h";  9: char = "e"; 10: char = "l"; 11: char = "l";
           12: char = "o"; 13: char = " ";
           14: char = hex(v[15:12]); 15: char = hex(v[11:8]);
           16: char = hex(v[7:4]);   17: char = hex(v[3:0]);
           18: char = 8'h0d;         19: char = 8'h0a;
           default: char = 8'h3f;
        endcase
    endfunction

    reg [10:0] baud = 0;      // cycles into the current bit
    reg [3:0]  bitn = 0;      // 0 start, 1..8 data, 9 stop
    reg [4:0]  idx = 0;       // byte of the line being sent
    reg        busy = 1'b0;
    reg [24:0] wait_count = 0;
    reg [9:0]  frame = 10'h3ff;

    always @(posedge clk) begin
        if (!busy) begin
            uart_tx <= 1'b1;
            if (wait_count == GAP - 1) begin
                wait_count <= 0;
                busy <= 1'b1;
                idx <= 0;
                bitn <= 0;
                baud <= 0;
                frame <= {1'b1, char(0, n), 1'b0};
            end else begin
                wait_count <= wait_count + 1;
            end
        end else if (baud == BAUD_DIV - 1) begin
            baud <= 0;
            if (bitn == 9) begin
                bitn <= 0;
                if (idx == LEN - 1) begin
                    busy <= 1'b0;
                    n <= n + 1;
                end else begin
                    idx <= idx + 1;
                    frame <= {1'b1, char(idx + 1, n), 1'b0};
                end
            end else begin
                bitn <= bitn + 1;
            end
        end else begin
            baud <= baud + 1;
            uart_tx <= frame[bitn];
        end
    end

    assign {led4, led3, led2, led1} = n[3:0];
endmodule
