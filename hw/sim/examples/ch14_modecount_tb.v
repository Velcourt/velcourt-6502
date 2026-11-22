// ch14_modecount_tb.v - ask the decoder in cpu6502.v about all 256 opcodes
// and count how many use each addressing mode.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//   (from hw/sim)
//   iverilog -o out/ch14_modecount.vvp examples/ch14_modecount_tb.v \
//       ../rtl/cpu6502.v ../rtl/alu6502.v && vvp -n out/ch14_modecount.vvp
module ch14_modecount_tb;
    reg clk = 0;
    wire [15:0] ab; wire [7:0] dout; wire we, sync;
    cpu6502 u_cpu (.clk(clk), .ce(1'b0), .rst(1'b0), .ab(ab), .dout(dout),
                   .we(we), .din(8'h00), .irq_n(1'b1), .nmi_n(1'b1),
                   .sync(sync));
    integer i, m, total;
    integer count [0:15];
    integer nop2 = 0;            // undocumented opcodes (2-cycle NOPs)
    initial begin
        for (m = 0; m < 16; m = m + 1) count[m] = 0;
        for (i = 0; i < 256; i = i + 1) begin
            force u_cpu.ir = i;
            #1;
            // the decoder leaves op = NOP for undocumented opcodes;
            // $EA is the one documented NOP
            if (u_cpu.op == 0 && u_cpu.mode != 12 && u_cpu.mode != 11
                && i != 8'hEA) nop2 = nop2 + 1;
            else count[u_cpu.mode] = count[u_cpu.mode] + 1;
        end
        total = 0;
        for (m = 0; m < 13; m = m + 1) total = total + count[m];
        $display("IMP %0d  ACC %0d  IMM %0d  ZP %0d  ZPX %0d  ZPY %0d",
                 count[0], count[1], count[2], count[3], count[4], count[5]);
        $display("ABS %0d  ABSX %0d  ABSY %0d  INDX %0d  INDY %0d",
                 count[6], count[7], count[8], count[9], count[10]);
        $display("REL %0d  CTL %0d  documented %0d  undocumented %0d",
                 count[11], count[12], total, nop2);
        $finish(0);
    end
endmodule
