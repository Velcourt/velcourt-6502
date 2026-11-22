// ch07_tb_tmds.v - checks rtl/tmds_encoder.v by decoding its symbols again.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
//   iverilog -o ch07_tb_tmds.vvp ch07_tb_tmds.v ../../rtl/tmds_encoder.v
//   vvp ch07_tb_tmds.vvp
//
// 1. prints the symbols for four brick-red pixels (red channel $A8)
// 2. sends 200 000 random bytes with a blanking gap now and then, decodes
//    every symbol, and checks the byte, the control codes and the running
//    disparity (ones minus zeros sent since the last blanking period)

module tb;
reg        clk = 0;
reg  [7:0] d = 0;
reg  [1:0] c = 0;
reg        de = 0;
wire [9:0] q;

tmds_encoder dut (.clk(clk), .d(d), .c(c), .de(de), .q(q));

// the receiver's half: 10-bit symbol back to 8 bits
function [7:0] decode(input [9:0] s);
    reg [7:0] v; integer i;
    begin
        v = s[9] ? ~s[7:0] : s[7:0];
        decode[0] = v[0];
        for (i = 1; i < 8; i = i + 1)
            decode[i] = s[8] ? (v[i] ^ v[i-1]) : ~(v[i] ^ v[i-1]);
    end
endfunction

function integer ones10(input [9:0] s);
    integer i;
    begin
        ones10 = 0;
        for (i = 0; i < 10; i = i + 1) ones10 = ones10 + s[i];
    end
endfunction

reg  [7:0] sent_d;               // what went in one clock ago
reg  [1:0] sent_c;
reg        sent_de;
integer n, errors = 0, data_syms = 0, ctrl_syms = 0;
integer disp = 0, max_disp = 0, min_disp = 0;
reg [15:0] lfsr = 16'hACE1;

task tick;
    begin
        sent_d = d; sent_c = c; sent_de = de;
        #5 clk = 1; #5 clk = 0;
    end
endtask

// check the symbol the encoder produced for the previous input
task check;
    begin
        if (sent_de) begin
            data_syms = data_syms + 1;
            if (decode(q) !== sent_d) begin
                errors = errors + 1;
                if (errors < 5)
                    $display("decode error: sent %h got %h", sent_d, decode(q));
            end
            disp = disp + 2 * ones10(q) - 10;
            if (disp > max_disp) max_disp = disp;
            if (disp < min_disp) min_disp = disp;
            if (disp !== dut.cnt) begin
                errors = errors + 1;
                if (errors < 5) $display("cnt %0d but %0d sent", dut.cnt, disp);
            end
        end else begin
            ctrl_syms = ctrl_syms + 1;
            disp = 0;
            case (q)
                10'b1101010100: if (sent_c != 2'b00) errors = errors + 1;
                10'b0010101011: if (sent_c != 2'b01) errors = errors + 1;
                10'b0101010100: if (sent_c != 2'b10) errors = errors + 1;
                10'b1010101011: if (sent_c != 2'b11) errors = errors + 1;
                default: errors = errors + 1;
            endcase
        end
    end
endtask

initial begin
    // ---- part 1: the worked example ----
    de = 0; c = 2'b00; tick;
    de = 1; d = 8'hA8;
    for (n = 0; n < 4; n = n + 1) begin
        tick;
        $display("pixel %0d: d=%h  q=%b  cnt=%0d", n, sent_d, q, dut.cnt);
    end
    de = 0; tick;

    // ---- part 2: random data with blanking ----
    for (n = 0; n < 200000; n = n + 1) begin
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        if (n % 1000 < 900) begin de = 1; d = lfsr[7:0]; end
        else begin de = 0; c = lfsr[9:8]; end
        tick;
        check;
    end
    $display("data symbols %0d, control symbols %0d", data_syms, ctrl_syms);
    $display("running disparity stayed between %0d and %0d",
             min_disp, max_disp);
    $display("%s: %0d errors", errors ? "FAIL" : "PASS", errors);
    $finish;
end
endmodule
