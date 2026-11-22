// ch03_alu_add_tb.v - feed a few additions to the real ALU (alu6502.v)
// and print the result with the C, V, N and Z flags.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch03_alu_add.vvp examples/ch03_alu_add_tb.v \
//     ../rtl/alu6502.v
//   vvp out/ch03_alu_add.vvp

module tb;
reg  [7:0] a, m;
reg        fc;
wire [7:0] na, nx, ny, ns, nm;
wire       nn, nv, nd, ni, nz, nc;
alu6502 dut (
    .op(6'd7), .acc_mode(1'b0),                // 7 = OP_ADC
    .a(a), .x(8'd0), .y(8'd0), .s(8'hFF), .m(m),
    .fn(1'b0), .fv(1'b0), .fd(1'b0), .fi(1'b1), .fz(1'b0), .fc(fc),
    .na(na), .nx(nx), .ny(ny), .ns(ns), .nm(nm),
    .nn(nn), .nv(nv), .nd(nd), .ni(ni), .nz(nz), .nc(nc)
);

task add(input [7:0] ta, input [7:0] tm, input tc);
begin
    a = ta; m = tm; fc = tc; #1;
    $display(" $%h + $%h + %b = $%h   C=%b V=%b N=%b Z=%b   (%0d + %0d + %0d)",
             a, m, fc, na, nc, nv, nn, nz, $signed(a), $signed(m), fc);
end
endtask

initial begin
    add(8'h50, 8'h10, 1'b0);   // 80 + 16: fine both ways
    add(8'h50, 8'h50, 1'b0);   // 80 + 80 = 160: too big for signed
    add(8'hFF, 8'h01, 1'b0);   // 255 + 1: unsigned wraps, signed -1 + 1 = 0
    add(8'h7F, 8'h01, 1'b0);   // 127 + 1: signed overflow
    add(8'hD0, 8'h90, 1'b0);   // -48 + -112 = -160: signed overflow
    add(8'h12, 8'h34, 1'b1);   // with carry in
    $finish;
end
endmodule
