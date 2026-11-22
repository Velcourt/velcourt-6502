// ch05_cpu_tb.v - a small self-checking test bench for cpu6502, with a VCD.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch05_cpu_tb.vvp examples/ch05_cpu_tb.v \
//       ../rtl/cpu6502.v ../rtl/alu6502.v
//   vvp out/ch05_cpu_tb.vvp              (expects $42 in $0200)
//   vvp out/ch05_cpu_tb.vvp +expect=43   (a wrong expectation: FAIL)
`timescale 1ns/1ps
module ch05_cpu_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;                   // 100 MHz in simulated time

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout; wire we, sync;
    wire [7:0] din = mem[ab];               // memory answers within the cycle

    cpu6502 u_cpu (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout),
                   .we(we), .din(din), .irq_n(1'b1), .nmi_n(1'b1), .sync(sync));

    always @(posedge clk) if (we) mem[ab] <= dout;

    integer i, cycles = 0, same = 0, wr_cycle = -1, expect_val;
    reg running = 0;                        // set at the first fetch of $0400
    reg [15:0] last_pc = 16'hFFFF;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        // $0400: LDA #$41 / CLC / ADC #$01 / STA $0200 / JMP $0408
        mem[16'h0400] = 8'hA9; mem[16'h0401] = 8'h41;
        mem[16'h0402] = 8'h18;
        mem[16'h0403] = 8'h69; mem[16'h0404] = 8'h01;
        mem[16'h0405] = 8'h8D; mem[16'h0406] = 8'h00; mem[16'h0407] = 8'h02;
        mem[16'h0408] = 8'h4C; mem[16'h0409] = 8'h08; mem[16'h040A] = 8'h04;
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h04;   // reset to $0400
        if (!$value$plusargs("expect=%h", expect_val)) expect_val = 8'h42;
        $dumpfile("out/ch05_cpu.vcd");
        $dumpvars(1, ch05_cpu_tb);          // this module's signals only
        repeat (3) @(posedge clk);
        rst = 0;
    end

    always @(posedge clk) if (!rst) begin
        if (sync && ab == 16'h0400) running = 1;
        if (running) cycles = cycles + 1;   // cycle 1 = fetch of LDA
        if (we && ab == 16'h0200) wr_cycle = cycles;
        if (sync) begin
            if (ab == last_pc) same = same + 1; else same = 0;
            last_pc = ab;
            if (same == 3) begin
                $display("trapped at $%04x after %0d cycles", ab, cycles);
                $display("write to $0200 in cycle %0d", wr_cycle);
                if (wr_cycle != 10)         // 2 + 2 + 2 cycles, then STA's 4th
                    $fatal(1, "FAIL: the write came in cycle %0d, not 10",
                           wr_cycle);
                if (mem[16'h0200] == expect_val)
                    $display("PASS: $0200 = %02x", mem[16'h0200]);
                else
                    $fatal(1, "FAIL: $0200 = %02x, expected %02x",
                           mem[16'h0200], expect_val[7:0]);
                $finish;
            end
        end
        if (cycles > 1000) $fatal(1, "TIMEOUT at $%04x", ab);
    end
endmodule
