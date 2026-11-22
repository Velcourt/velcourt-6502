// ch04_blocking_tb.v - the same three-flop shift register written twice:
// with non-blocking (<=) and with blocking (=) assignments.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch04_blocking.vvp examples/ch04_blocking_tb.v
//   vvp out/ch04_blocking.vvp

module shift_nb (input wire clk, input wire d, output reg q1, q2, q3);
always @(posedge clk) begin
    q1 <= d;
    q2 <= q1;
    q3 <= q2;
end
endmodule

module shift_b (input wire clk, input wire d, output reg q1, q2, q3);
always @(posedge clk) begin
    q1 = d;            // wrong for flip-flops: q2 sees the NEW q1
    q2 = q1;
    q3 = q2;
end
endmodule

module tb;
reg clk = 0, d = 0;
wire a1, a2, a3, b1, b2, b3;
shift_nb u_nb (.clk(clk), .d(d), .q1(a1), .q2(a2), .q3(a3));
shift_b  u_b  (.clk(clk), .d(d), .q1(b1), .q2(b2), .q3(b3));

always #5 clk = ~clk;              // a clock edge every 10 time units

integer n;
initial begin
    $display("edge  d | <= : q1 q2 q3 | =  : q1 q2 q3");
    for (n = 1; n <= 5; n = n + 1) begin
        d = (n == 1);                  // a single 1, for one clock
        @(posedge clk); #1;
        $display("  %0d   %b |       %b  %b  %b |       %b  %b  %b",
                 n, d, a1, a2, a3, b1, b2, b3);
    end
    $finish;
end
endmodule
