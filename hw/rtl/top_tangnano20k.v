// top_tangnano20k.v - the computer on a Sipeed Tang Nano 20K board.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Only this file and the .cst pin file know about the board.
// Everything else lives in soc.v and runs unchanged in the simulator.

module top_tangnano20k (
    input  wire       clk27,         // 27 MHz crystal
    input  wire       btn_reset,     // S1, reads 1 when pressed
    input  wire       btn_user,      // S2, reads 1 when pressed
    output wire [5:0] led_n,         // the six LEDs light when driven low
    // HDMI connector
    output wire [2:0] tmds_p, tmds_n,
    output wire       tmds_clk_p, tmds_clk_n,
    // USB serial, through the board's BL616 chip
    input  wire       uart_rx,
    output wire       uart_tx,
    // SD card slot
    output wire       sd_sck, sd_mosi, sd_cs_n,
    input  wire       sd_miso,
    // audio amplifier
    output wire       pa_en, i2s_bck, i2s_ws, i2s_din,
    // PS/2 keyboard on the pin header
    input  wire       ps2_clk, ps2_dat
);

// ---------------- clocks ----------------
// 27 MHz x 14 / 3 = 126 MHz serial clock (VCO 1008 MHz, divided by 8).
// 126 / 5 = 25.2 MHz pixel clock, which is also the system clock.
wire sclk, pclk, lock;

rPLL #(
    .FCLKIN("27"), .DEVICE("GW2AR-18C"),
    .IDIV_SEL(2), .FBDIV_SEL(13), .ODIV_SEL(8),
    .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
    .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"),
    .CLKOUTD_BYPASS("false"), .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"),
    .CLKOUTD3_SRC("CLKOUT"), .PSDA_SEL("0000"), .DYN_DA_EN("false"),
    .DUTYDA_SEL("1000")
) u_pll (
    .CLKIN(clk27), .CLKOUT(sclk), .LOCK(lock),
    .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
    .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
    .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0), .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
);

CLKDIV #(.DIV_MODE("5")) u_div (
    .CLKOUT(pclk), .HCLKIN(sclk), .RESETN(lock), .CALIB(1'b0)
);

// ---------------- reset ----------------
// Held for 65536 pixel clocks after the PLL locks, and while S1 is down.
reg [15:0] por = 16'd0;
reg        rst = 1'b1;
always @(posedge pclk) begin
    if (!lock || btn_reset) begin por <= 16'd0; rst <= 1'b1; end
    else if (por != 16'hFFFF) por <= por + 16'd1;
    else rst <= 1'b0;
end

// ---------------- the computer ----------------
wire [7:0] r, g, b;
wire       hs, vs, de;
wire [5:0] leds;

soc #(.ROM_FILE("rom.hex")) u_soc (
    .clk(pclk), .rst(rst),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
    .uart_rx(uart_rx), .uart_tx(uart_tx),
    .ps2_clk(ps2_clk), .ps2_dat(ps2_dat),
    .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_cs_n(sd_cs_n), .sd_miso(sd_miso),
    .i2s_bck(i2s_bck), .i2s_ws(i2s_ws), .i2s_din(i2s_din),
    .sample(), .sample_tick(),
    .leds(leds), .button(btn_user),
    .dbg_ab(), .dbg_sync(), .dbg_ce(), .dbg_we(), .dbg_din()
);

assign led_n = ~leds;
assign pa_en = 1'b1;                  // switch the amplifier on

dvi_out u_dvi (
    .pclk(pclk), .sclk(sclk), .rst(rst),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
    .tmds_p(tmds_p), .tmds_n(tmds_n), .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
    .sym_b(), .sym_g(), .sym_r()
);

endmodule
