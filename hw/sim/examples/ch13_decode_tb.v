// ch13_decode_tb.v - ask cpu6502's decoder about all 256 opcodes, then
// run each opcode once and measure its length and its cycle count.
// ch13_opcodes.py checks the result against the 151 documented opcodes.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch13_decode.vvp examples/ch13_decode_tb.v \
//            ../rtl/cpu6502.v ../rtl/alu6502.v
//   vvp out/ch13_decode.vvp > out/ch13_decode.txt
`timescale 1ns/1ps
module ch13_decode_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout; wire we, sync;
    wire [7:0] din = mem[ab];

    cpu6502 dut (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout),
                 .we(we), .din(din), .irq_n(1'b1), .nmi_n(1'b1), .sync(sync));

    always @(posedge clk) if (we) mem[ab] <= dout;

    integer i, k, cycles;
    reg [3:0] dmode; reg [1:0] dkind; reg [5:0] dop;
    reg [15:0] next_pc;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            // 1. the decoder alone: hold IR at the opcode and read its outputs
            force dut.ir = i;
            #1;
            dmode = dut.mode; dkind = dut.kind; dop = dut.op;
            release dut.ir;

            // 2. run it: a short prefix sets A, X, Y and the flags, then the
            //    opcode at $0209 with operand bytes $10 $30
            for (k = 0; k < 65536; k = k + 1) mem[k] = 8'h00;
            mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h02;
            mem[16'h0200] = 8'hA2; mem[16'h0201] = 8'h00;   // LDX #0
            mem[16'h0202] = 8'hA0; mem[16'h0203] = 8'h00;   // LDY #0
            mem[16'h0204] = 8'hA9; mem[16'h0205] = 8'h00;   // LDA #0
            mem[16'h0206] = 8'h18;                          // CLC
            mem[16'h0207] = 8'hD8;                          // CLD
            mem[16'h0208] = 8'hB8;                          // CLV
            mem[16'h0209] = i;
            mem[16'h020A] = 8'h10; mem[16'h020B] = 8'h30;
            rst = 1;
            repeat (3) @(posedge clk);
            #1 rst = 0;
            // wait for the fetch of our opcode
            while (!(sync && ab == 16'h0209)) begin @(posedge clk); #1; end
            @(posedge clk); #1;
            cycles = 1;
            // count cycles up to the next opcode fetch
            while (!sync && cycles < 20) begin
                @(posedge clk); #1;
                cycles = cycles + 1;
            end
            next_pc = ab;
            $display("%02X mode=%0d kind=%0d op=%0d next=%04X cycles=%0d",
                     i[7:0], dmode, dkind, dop, next_pc, cycles);
        end
        $finish;
    end
endmodule
