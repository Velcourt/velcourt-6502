// ch12_decimal_tb.v - the worked decimal-mode examples of Chapter 12,
// run through alu6502. Each line shows the inputs, the ALU's internal
// steps (dal, dsum, dadj for ADC; sl, sh for SBC) and the result.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch12_decimal.vvp examples/ch12_decimal_tb.v \
//            ../rtl/alu6502.v
//   vvp out/ch12_decimal.vvp
`timescale 1ns/1ps
module ch12_decimal_tb;
    localparam OP_ADC = 6'd7, OP_SBC = 6'd8;
    reg  [5:0] op;
    reg  [7:0] a, m;
    reg        fd, fc;
    wire [7:0] na, nx, ny, ns, nm;
    wire       nn, nv, nd, ni, nz, nc;

    alu6502 dut (.op(op), .acc_mode(1'b0),
                 .a(a), .x(8'h00), .y(8'h00), .s(8'hFF), .m(m),
                 .fn(1'b0), .fv(1'b0), .fd(fd), .fi(1'b0), .fz(1'b0), .fc(fc),
                 .na(na), .nx(nx), .ny(ny), .ns(ns), .nm(nm),
                 .nn(nn), .nv(nv), .nd(nd), .ni(ni), .nz(nz), .nc(nc));

    task adc(input [7:0] ia, input [7:0] im, input ic);
        begin
            op = OP_ADC; fd = 1; a = ia; m = im; fc = ic; #1;
            $display("ADC $%h + $%h + C%0d: dal=$%h dsum=$%h dadj=$%h",
                     ia, im, ic, dut.dal, dut.dsum, dut.dadj);
            $display("    ->  A=$%h N%0d V%0d Z%0d C%0d", na, nn, nv, nz, nc);
        end
    endtask

    task sbc(input [7:0] ia, input [7:0] im, input ic);
        begin
            op = OP_SBC; fd = 1; a = ia; m = im; fc = ic; #1;
            $display("SBC $%h - $%h C%0d: sl=%0d sh=%0d",
                     ia, im, ic, dut.sl, dut.sh);
            $display("    ->  A=$%h N%0d V%0d Z%0d C%0d", na, nn, nv, nz, nc);
        end
    endtask

    initial begin
        $display("-- valid BCD, addition");
        adc(8'h12, 8'h34, 0);
        adc(8'h25, 8'h48, 0);
        adc(8'h58, 8'h46, 1);
        adc(8'h99, 8'h01, 0);
        adc(8'h79, 8'h00, 1);
        adc(8'h50, 8'h50, 0);
        $display("-- valid BCD, subtraction");
        sbc(8'h46, 8'h12, 1);
        sbc(8'h40, 8'h13, 1);
        sbc(8'h32, 8'h02, 0);
        sbc(8'h00, 8'h01, 1);
        sbc(8'h10, 8'h09, 0);
        $display("-- invalid BCD");
        adc(8'h0F, 8'h01, 0);
        adc(8'h1A, 8'h00, 0);
        adc(8'hFF, 8'hFF, 1);
        sbc(8'h0A, 8'h00, 1);
        sbc(8'h20, 8'h0F, 1);
        $display("-- the same sum in binary mode");
        op = OP_ADC; fd = 0; a = 8'h58; m = 8'h46; fc = 1; #1;
        $display("ADC $58 + $46 + C1, D=0");
        $display("    ->  A=$%h N%0d V%0d Z%0d C%0d", na, nn, nv, nz, nc);
        $finish;
    end
endmodule
