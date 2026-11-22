// ch03_fulladd_tb.v - print the truth table of the full adder.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch03_fa.vvp examples/ch03_fulladd.v \
//     examples/ch03_fulladd_tb.v
//   vvp out/ch03_fa.vvp

module tb;
reg  a, b, cin;
wire s, cout;
full_add dut (.a(a), .b(b), .cin(cin), .s(s), .cout(cout));

integer i;
initial begin
    $display(" a b cin | cout s");
    for (i = 0; i < 8; i = i + 1) begin
        {a, b, cin} = i[2:0];
        #1;                                  // let the gates settle
        $display(" %b %b  %b  |   %b  %b", a, b, cin, cout, s);
    end
    $finish;
end
endmodule
