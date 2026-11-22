// tmds_encoder.v - turns one 8-bit colour channel into a 10-bit TMDS symbol.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Two steps, as described in the DVI 1.0 specification:
//  1. Minimise transitions: chain the bits with XOR or XNOR,
//     whichever produces fewer 0/1 changes. Bit 8 records the choice.
//  2. Keep the line DC-balanced: count the ones and zeros already sent
//     and invert the word (bit 9 = 1) when that brings the count back
//     towards zero.
// Outside the visible area the four control symbols carry HSYNC/VSYNC.

module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] d,        // pixel data
    input  wire [1:0] c,        // control bits {c1, c0}, used when de=0
    input  wire       de,       // data enable: 1 = visible pixel
    output reg  [9:0] q
);

function [3:0] ones8(input [7:0] v);
    ones8 = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
endfunction

// ---- step 1: transition-minimised word q_m ----
wire [3:0] n1d    = ones8(d);
wire       use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && d[0] == 1'b0);
wire [8:0] q_m;
assign q_m[0] = d[0];
genvar i;
generate for (i = 1; i < 8; i = i + 1) begin : chain
    assign q_m[i] = use_xnor ? ~(q_m[i-1] ^ d[i]) : (q_m[i-1] ^ d[i]);
end endgenerate
assign q_m[8] = ~use_xnor;

// ---- step 2: DC balance ----
wire [3:0] n1 = ones8(q_m[7:0]);
wire [3:0] n0 = 4'd8 - n1;
reg signed [4:0] cnt;                  // running disparity: ones minus zeros sent

always @(posedge clk) begin
    if (!de) begin
        cnt <= 0;
        case (c)
            2'b00: q <= 10'b1101010100;
            2'b01: q <= 10'b0010101011;
            2'b10: q <= 10'b0101010100;
            2'b11: q <= 10'b1010101011;
        endcase
    end else if (cnt == 0 || n1 == n0) begin
        q <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
        if (q_m[8]) cnt <= cnt + $signed({1'b0, n1}) - $signed({1'b0, n0});
        else        cnt <= cnt + $signed({1'b0, n0}) - $signed({1'b0, n1});
    end else if ((cnt > 0 && n1 > n0) || (cnt < 0 && n0 > n1)) begin
        q <= {1'b1, q_m[8], ~q_m[7:0]};
        cnt <= cnt + $signed({4'd0, q_m[8]} << 1) + $signed({1'b0, n0}) - $signed({1'b0, n1});
    end else begin
        q <= {1'b0, q_m[8], q_m[7:0]};
        cnt <= cnt - $signed({4'd0, ~q_m[8]} << 1) + $signed({1'b0, n1}) - $signed({1'b0, n0});
    end
end

endmodule
