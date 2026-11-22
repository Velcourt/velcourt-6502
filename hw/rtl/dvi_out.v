// dvi_out.v - three TMDS encoders, 10:1 serializers and differential pins.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Blue carries HSYNC and VSYNC during blanking, as DVI requires.
// The serializers (OSER10) take a 10-bit word on every pixel clock and
// shift it out at five times that rate on both clock edges (DDR), so a
// 126 MHz serial clock gives 252 Mbit/s per lane (25.2 MHz x 10 bits).
// The clock lane simply sends 1111100000 every pixel. The HDMI pins of the
// GW2AR-18 are true LVDS pins, so the output buffers are TLVDS_OBUF.

module dvi_out (
    input  wire       pclk,       // pixel clock 25.2 MHz
    input  wire       sclk,       // serial clock 126 MHz (5 x pclk)
    input  wire       rst,
    input  wire [7:0] r, g, b,
    input  wire       hs, vs, de,
    output wire [2:0] tmds_p, tmds_n,   // lanes 0=blue 1=green 2=red
    output wire       tmds_clk_p, tmds_clk_n,
    output wire [9:0] sym_b, sym_g, sym_r   // exposed for simulation
);

tmds_encoder enc_b (.clk(pclk), .d(b), .c({vs, hs}), .de(de), .q(sym_b));
tmds_encoder enc_g (.clk(pclk), .d(g), .c(2'b00),    .de(de), .q(sym_g));
tmds_encoder enc_r (.clk(pclk), .d(r), .c(2'b00),    .de(de), .q(sym_r));

`ifndef SIM
wire [9:0] words [0:3];
assign words[0] = sym_b;
assign words[1] = sym_g;
assign words[2] = sym_r;
assign words[3] = 10'b1111100000;      // the clock lane
wire [3:0] serial;

genvar i;
generate for (i = 0; i < 4; i = i + 1) begin : lane
    OSER10 ser (
        .Q(serial[i]),
        .D0(words[i][0]), .D1(words[i][1]), .D2(words[i][2]), .D3(words[i][3]),
        .D4(words[i][4]), .D5(words[i][5]), .D6(words[i][6]), .D7(words[i][7]),
        .D8(words[i][8]), .D9(words[i][9]),
        .PCLK(pclk), .FCLK(sclk), .RESET(rst)
    );
end endgenerate

TLVDS_OBUF buf_b   (.I(serial[0]), .O(tmds_p[0]),  .OB(tmds_n[0]));
TLVDS_OBUF buf_g   (.I(serial[1]), .O(tmds_p[1]),  .OB(tmds_n[1]));
TLVDS_OBUF buf_r   (.I(serial[2]), .O(tmds_p[2]),  .OB(tmds_n[2]));
TLVDS_OBUF buf_clk (.I(serial[3]), .O(tmds_clk_p), .OB(tmds_clk_n));
`else
assign tmds_p = 3'b000; assign tmds_n = 3'b111;
assign tmds_clk_p = 1'b0; assign tmds_clk_n = 1'b1;
`endif

endmodule
