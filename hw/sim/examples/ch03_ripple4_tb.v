// ch03_ripple4_tb.v - a 4-bit ripple-carry adder built from full adders,
// checked against Verilog's own + and against signed arithmetic.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch03_r4.vvp examples/ch03_fulladd.v \
//     examples/ch03_ripple4_tb.v
//   vvp out/ch03_r4.vvp

module ripple4 (
    input  wire [3:0] a, b,
    input  wire       cin,
    output wire [3:0] s,
    output wire       cout,
    output wire       v            // signed overflow
);
wire [4:0] c;                      // c[0] is the carry in, c[4] the carry out
assign c[0] = cin;
full_add fa0 (.a(a[0]), .b(b[0]), .cin(c[0]), .s(s[0]), .cout(c[1]));
full_add fa1 (.a(a[1]), .b(b[1]), .cin(c[1]), .s(s[1]), .cout(c[2]));
full_add fa2 (.a(a[2]), .b(b[2]), .cin(c[2]), .s(s[2]), .cout(c[3]));
full_add fa3 (.a(a[3]), .b(b[3]), .cin(c[3]), .s(s[3]), .cout(c[4]));
assign cout = c[4];
// the same formula as bin_v in alu6502.v, on 4 bits
assign v = (~(a[3] ^ b[3])) & (a[3] ^ s[3]);
endmodule

module tb;
reg  [3:0] a, b;
reg        cin;
wire [3:0] s;
wire       cout, v;
ripple4 dut (.a(a), .b(b), .cin(cin), .s(s), .cout(cout), .v(v));

integer i, errors, checked, sa, sb, ssum;
reg [4:0] want;                    // reference: 5-bit unsigned sum
reg       want_v;                  // reference: signed result out of range
initial begin
    errors = 0; checked = 0;
    for (i = 0; i < 512; i = i + 1) begin
        {cin, a, b} = i[8:0];
        #1;
        want = a + b + cin;
        sa = a[3] ? a - 16 : a;      // the same bits read as -8..7
        sb = b[3] ? b - 16 : b;
        ssum = sa + sb + cin;
        want_v = (ssum < -8) || (ssum > 7);
        checked = checked + 1;
        if ({cout, s} !== want || v !== want_v) begin
            errors = errors + 1;
            if (errors <= 5)
                $display("MISMATCH a=%h b=%h c=%b: got %b%h v=%b want %h v=%b",
                         a, b, cin, cout, s, v, want, want_v);
        end
    end
    $display("%0d cases checked, %0d errors", checked, errors);
    $finish;
end
endmodule
