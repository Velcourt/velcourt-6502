// ch24_ps2_tb.v - checks ps2_kbd.v: good frames, a parity error,
// a glitch on the clock line, a half-finished frame, and a full FIFO.
// Run from hw/:  iverilog -o sim/out/ch24_ps2_tb.vvp sim/examples/ch24_ps2_tb.v rtl/ps2_kbd.v
//                vvp sim/out/ch24_ps2_tb.vvp
`timescale 1ns/1ps
module ch24_ps2_tb;
reg clk = 0, rst = 1, cs = 0, we = 0, a0 = 0;
reg ps2_clk = 1, ps2_dat = 1;
wire [7:0] rdata; wire irq;
integer errors = 0, i;
reg [7:0] got;

ps2_kbd dut (.clk(clk), .rst(rst), .cs(cs), .we(we), .a0(a0), .rdata(rdata),
             .irq(irq), .ps2_clk(ps2_clk), .ps2_dat(ps2_dat));
always #19.84 clk = !clk;                  // 25.2 MHz

task clocks(input integer n); begin repeat (n) @(posedge clk); end endtask

// One bit: data set while the clock is high, then the clock falls.
// 1000 system clocks per half period, as in sim_soc.cpp (12.6 kHz).
task bit_out(input b); begin
    ps2_dat = b; clocks(1000); ps2_clk = 0; clocks(1000); ps2_clk = 1;
end endtask

// A frame of nbits bits (11 for a whole one); flip = 1 spoils the parity
task frame(input [7:0] code, input flip, input integer nbits);
    integer k; reg [10:0] f; begin
    f = {1'b1, ~^code ^ flip, code, 1'b0};  // stop, odd parity, data, start
    for (k = 0; k < nbits; k = k + 1) bit_out(f[k]);
    ps2_dat = 1; clocks(20000);
end endtask

task rd(input a, output [7:0] v); begin   // a CPU read: data, then the strobe
    @(negedge clk); a0 = a; #1 v = rdata; cs = 1; @(negedge clk); cs = 0;
end endtask

task expect_code(input [7:0] want); reg [7:0] s, v; begin
    rd(1, s); rd(0, v);
    if (s[0] !== 1'b1 || v !== want) begin
        $display("FAIL: wanted %h, status %b code %h", want, s, v); errors = errors + 1;
    end else $display("ok   code %h  (status %b)", v, s);
end endtask

initial begin
    clocks(5); rst = 0; clocks(5);
    frame(8'h1C, 0, 11);                   // A pressed
    expect_code(8'h1C);
    frame(8'hF0, 0, 11); frame(8'h1C, 0, 11);  // A released
    expect_code(8'hF0); expect_code(8'h1C);

    frame(8'h32, 1, 11);                   // bad parity: not stored, bit1 set
    rd(1, got);
    $display("%s  after a parity error status = %b", got == 8'b10 ? "ok  " : "FAIL", got);
    if (got != 8'b10) errors = errors + 1;
    rd(1, got);
    $display("%s  reading the status clears it: %b", got == 0 ? "ok  " : "FAIL", got);
    if (got != 0) errors = errors + 1;

    ps2_clk = 0; clocks(5); ps2_clk = 1; clocks(100);  // a 5-clock glitch
    frame(8'h21, 0, 11);                   // must still arrive as C, not shifted
    expect_code(8'h21);

    frame(8'h55, 0, 6);                    // half a frame, then silence
    clocks(60000);                         // more than the 50,000-clock timeout
    frame(8'h23, 0, 11);
    expect_code(8'h23);

    for (i = 0; i < 18; i = i + 1) frame(i + 8'h10, 0, 11);  // 18 codes, no reads
    rd(1, got);
    $display("after 18 codes the status is %b; count = %0d", got, dut.count);
    if (dut.count != 16) errors = errors + 1;
    for (i = 0; i < 16; i = i + 1) expect_code(i + 8'h10);
    rd(1, got);
    $display("%s  FIFO empty again: status %b", got == 0 ? "ok  " : "FAIL", got);
    if (got != 0) errors = errors + 1;

    if (errors == 0) $display("PASS"); else $display("FAILED: %0d errors", errors);
    $finish;
end
endmodule
