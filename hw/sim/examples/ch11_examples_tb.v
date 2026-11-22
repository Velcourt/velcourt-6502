// ch11_examples_tb.v - the worked ADC, SBC and CMP examples of Chapter 11,
// run through alu6502 in binary mode.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch11_examples.vvp examples/ch11_examples_tb.v \
//            ../rtl/alu6502.v
//   vvp out/ch11_examples.vvp
`timescale 1ns/1ps
module ch11_examples_tb;
    localparam OP_ADC = 6'd7, OP_SBC = 6'd8, OP_CMP = 6'd12;
    reg  [5:0] op;
    reg  [7:0] a, m;
    reg        fc;
    wire [7:0] na, nx, ny, ns, nm;
    wire       nn, nv, nd, ni, nz, nc;

    alu6502 dut (.op(op), .acc_mode(1'b0),
                 .a(a), .x(8'h00), .y(8'h00), .s(8'hFF), .m(m),
                 .fn(1'b0), .fv(1'b0), .fd(1'b0), .fi(1'b0), .fz(1'b0), .fc(fc),
                 .na(na), .nx(nx), .ny(ny), .ns(ns), .nm(nm),
                 .nn(nn), .nv(nv), .nd(nd), .ni(ni), .nz(nz), .nc(nc));

    task show(input [5:0] iop, input [7:0] ia, input [7:0] im, input ic);
        begin
            op = iop; a = ia; m = im; fc = ic; #1;
            $display("%s A=$%h M=$%h C=%0d  ->  A=$%h  N=%0d V=%0d Z=%0d C=%0d",
                     iop == OP_ADC ? "ADC" : iop == OP_SBC ? "SBC" : "CMP",
                     ia, im, ic, na, nn, nv, nz, nc);
        end
    endtask

    initial begin
        show(OP_ADC, 8'h10, 8'h20, 0);
        show(OP_ADC, 8'h50, 8'h50, 0);
        show(OP_ADC, 8'hD0, 8'h90, 0);
        show(OP_ADC, 8'hFF, 8'h01, 0);
        show(OP_ADC, 8'h7F, 8'h00, 1);
        show(OP_SBC, 8'h50, 8'h30, 1);
        show(OP_SBC, 8'h30, 8'h50, 1);
        show(OP_SBC, 8'h50, 8'h30, 0);
        show(OP_SBC, 8'h80, 8'h01, 1);
        show(OP_CMP, 8'h10, 8'h20, 0);
        show(OP_CMP, 8'h20, 8'h20, 0);
        show(OP_CMP, 8'h30, 8'h20, 0);
        show(OP_CMP, 8'h05, 8'hFF, 0);
        show(OP_CMP, 8'hF0, 8'h10, 0);
        $finish;
    end
endmodule
