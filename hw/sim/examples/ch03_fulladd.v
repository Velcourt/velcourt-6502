// ch03_fulladd.v - a half adder and a full adder, written with assign.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

module half_add (
    input  wire a, b,
    output wire s, c
);
assign s = a ^ b;          // sum: 1 when exactly one input is 1
assign c = a & b;          // carry: 1 when both are 1
endmodule

module full_add (
    input  wire a, b, cin,
    output wire s, cout
);
assign s    = a ^ b ^ cin;
`ifdef BUG
assign cout = (a & b) | (cin & b);        // a deliberate mistake (Debug clinic)
`else
assign cout = (a & b) | (cin & (a ^ b));
`endif
endmodule
