// ch11_alu_tb.v - drive alu6502 through every operation and every
// combination of A, M, carry and decimal flag, and write each answer
// to a binary file. ch11_alu_check.py compares the file with a model.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch11_alu.vvp examples/ch11_alu_tb.v ../rtl/alu6502.v
//   vvp out/ch11_alu.vvp
`timescale 1ns/1ps
module ch11_alu_tb;
    reg  [5:0] op;
    reg        acc_mode;
    reg  [7:0] a, x, y, s, m;
    reg        fn, fv, fd, fi, fz, fc;
    wire [7:0] na, nx, ny, ns, nm;
    wire       nn, nv, nd, ni, nz, nc;

    alu6502 dut (.op(op), .acc_mode(acc_mode),
                 .a(a), .x(x), .y(y), .s(s), .m(m),
                 .fn(fn), .fv(fv), .fd(fd), .fi(fi), .fz(fz), .fc(fc),
                 .na(na), .nx(nx), .ny(ny), .ns(ns), .nm(nm),
                 .nn(nn), .nv(nv), .nd(nd), .ni(ni), .nz(nz), .nc(nc));

    integer f, o, am, d, c, ia, im, count;
    initial begin
        f = $fopen("out/ch11_alu.bin", "wb");
        count = 0;
        for (o = 0; o <= 38; o = o + 1)
        for (am = 0; am <= 1; am = am + 1)
        if (am == 0 || (o >= 16 && o <= 19))        // acc_mode: shifts only
        for (d = 0; d <= 1; d = d + 1)
        for (c = 0; c <= 1; c = c + 1)
        for (ia = 0; ia < 256; ia = ia + 1)
        for (im = 0; im < 256; im = im + 1) begin
            op = o; acc_mode = am; fd = d; fc = c;
            a = ia; m = im;
            x = ia ^ 8'h5A; y = ia ^ 8'hA5; s = ia + 8'h33;
            {fn, fv, fi, fz} = ia[3:0] ^ im[7:4];   // the other flags vary too
            #1;
            $fwrite(f, "%c%c%c%c%c%c", na, nx, ny, ns, nm,
                    {nn, nv, 2'b10, nd, ni, nz, nc});
            count = count + 1;
        end
        $fclose(f);
        $display("wrote %0d results", count);
        $finish;
    end
endmodule
