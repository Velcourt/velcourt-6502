// soc.v - the whole computer, except the FPGA-specific clock and pin parts.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Memory map
//   $0000-$3FFF  RAM, 16 KB (zero page, stack, BASIC program and variables)
//   $4000-$BCFF  framebuffer, 320 x 200 pixels, 4 bits each (32 000 bytes)
//   $BD00-$BEFF  free (reads $FF)
//   $BF00-$BFFF  input/output, 16 bytes per device:
//       $BF00 UART (USB serial)       $BF10 PS/2 keyboard
//       $BF20 VIA (timers, LEDs, button)
//       $BF30 SPI (SD card)           $BF40 sound
//       $BF50 video and system
//   $C000-$FFFF  ROM, 16 KB (BASIC, the kernel and the monitor)
//
// Timing: the system clock is the 25.2 MHz pixel clock. The CPU takes one
// step on every second clock (ce=1), so it runs at 12.6 MHz. In the clock
// with ce=0 the block RAMs latch the address; in the clock with ce=1 their
// data is ready and the CPU latches it.

module soc #(
    parameter ROM_FILE = "rom.hex",
    parameter UART_DIV = 219
) (
    input  wire        clk,          // 25.2 MHz
    input  wire        rst,
    // video out (to the DVI encoder)
    output wire [7:0]  r, g, b,
    output wire        hs, vs, de,
    // serial
    input  wire        uart_rx,
    output wire        uart_tx,
    // PS/2 keyboard
    input  wire        ps2_clk,
    input  wire        ps2_dat,
    // SD card
    output wire        sd_sck, sd_mosi, sd_cs_n,
    input  wire        sd_miso,
    // sound
    output wire        i2s_bck, i2s_ws, i2s_din,
    output wire [15:0] sample,
    output wire        sample_tick,
    // LEDs and button
    output wire [5:0]  leds,         // 1 = on
    input  wire        button,       // 1 = pressed
    // for the simulator and the logic analyser
    output wire [15:0] dbg_ab,
    output wire        dbg_sync,
    output wire        dbg_ce,
    output wire        dbg_we,
    output wire [7:0]  dbg_din
);

// ---------------- CPU clock enable ----------------
reg ce;
always @(posedge clk) ce <= rst ? 1'b0 : ~ce;

// ---------------- the CPU ----------------
wire [15:0] ab;
wire [7:0]  cpu_dout;
wire        cpu_we, sync;
reg  [7:0]  cpu_din;
wire        irq_n, nmi_n;

cpu6502 u_cpu (
    .clk(clk), .ce(ce), .rst(rst),
    .ab(ab), .dout(cpu_dout), .we(cpu_we), .din(cpu_din),
    .irq_n(irq_n), .nmi_n(nmi_n), .sync(sync)
);
assign dbg_ab = ab; assign dbg_sync = sync; assign dbg_ce = ce;
assign dbg_we = cpu_we; assign dbg_din = cpu_din;

// ---------------- address decoding ----------------
wire sel_ram = (ab[15:14] == 2'b00);                       // $0000-$3FFF
wire sel_fb  = (ab >= 16'h4000) && (ab < 16'hBD00);        // $4000-$BCFF
wire sel_io  = (ab[15:8] == 8'hBF);                        // $BF00-$BFFF
wire sel_rom = (ab[15:14] == 2'b11);                       // $C000-$FFFF
wire [2:0] dev = ab[6:4];                                  // which device
wire wr      = cpu_we && ce;                               // write strobe
wire io_stb  = sel_io && ce;                               // device strobe

// ---------------- RAM: 16 KB ----------------
reg [7:0] ram [0:16383];
reg [7:0] ram_q;
always @(posedge clk) begin
    if (wr && sel_ram) ram[ab[13:0]] <= cpu_dout;
    else               ram_q <= ram[ab[13:0]];
end

// ---------------- ROM: 16 KB ----------------
reg [7:0] rom [0:16383];
initial $readmemh(ROM_FILE, rom);
reg [7:0] rom_q;
always @(posedge clk) rom_q <= rom[ab[13:0]];

// ---------------- framebuffer: one write port, one shared read port ----------------
// The CPU writes through its own port. The read port takes turns: in clocks
// with ce=0 it reads for the CPU (the byte is ready in the ce=1 clock, when
// the CPU latches it); in clocks with ce=1 it may read for the video circuit.
// One write port plus one read port is "simple dual port" block RAM, which
// fits 32 KB into 16 of the chip's 46 blocks.
wire [14:0] fb_cpu_addr = ab[14:0] - 15'h4000;   // $4000 -> 0
wire [14:0] fb_vid_addr;
wire [14:0] fb_rd_addr  = ce ? fb_vid_addr : fb_cpu_addr;
reg  [7:0]  fb [0:32767];
reg  [7:0]  fb_q;
always @(posedge clk) if (wr && sel_fb) fb[fb_cpu_addr] <= cpu_dout;
always @(posedge clk) fb_q <= fb[fb_rd_addr];

// ---------------- video and system registers ($BF50) ----------------
reg  [3:0] border;
reg  [1:0] irq_en;                 // bit0 UART, bit1 PS/2 keyboard
wire       vblank;
always @(posedge clk) begin
    if (rst) begin border <= 4'd6; irq_en <= 2'd0; end
    else if (io_stb && cpu_we && dev == 3'd5) case (ab[3:0])
        4'd0: border <= cpu_dout[3:0];
        4'd2: irq_en <= cpu_dout[1:0];
        default: ;
    endcase
end

video u_video (
    .clk(clk), .rst(rst),
    .slot(ce), .fb_addr(fb_vid_addr), .fb_data(fb_q), .border(border),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de), .vblank(vblank)
);

// ---------------- devices ----------------
wire [7:0] uart_q, kbd_q, via_q, spi_q;
wire       uart_irq, kbd_irq, via_irq;

uart #(.DIV(UART_DIV)) u_uart (
    .clk(clk), .rst(rst), .cs(io_stb && dev == 3'd0), .we(cpu_we), .a0(ab[0]),
    .wdata(cpu_dout), .rdata(uart_q), .irq(uart_irq), .rx(uart_rx), .tx(uart_tx)
);

ps2_kbd u_kbd (
    .clk(clk), .rst(rst), .cs(io_stb && dev == 3'd1), .we(cpu_we), .a0(ab[0]),
    .rdata(kbd_q), .irq(kbd_irq), .ps2_clk(ps2_clk), .ps2_dat(ps2_dat)
);

wire [7:0] pa_out, pb_out, ddra, ddrb;
via u_via (
    .clk(clk), .rst(rst), .tick(ce), .cs(io_stb && dev == 3'd2), .we(cpu_we),
    .rs(ab[3:0]), .wdata(cpu_dout), .rdata(via_q), .irq(via_irq),
    .pa_in({7'd0, button}), .pb_in(8'd0), .pa_out(pa_out), .pb_out(pb_out),
    .ddra(ddra), .ddrb(ddrb)
);
assign leds = pb_out[5:0] & ddrb[5:0];

spi_sd u_spi (
    .clk(clk), .rst(rst), .cs(io_stb && dev == 3'd3), .we(cpu_we), .a0(ab[0]),
    .wdata(cpu_dout), .rdata(spi_q),
    .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs_n(sd_cs_n)
);

sound u_sound (
    .clk(clk), .rst(rst), .cs(io_stb && dev == 3'd4), .we(cpu_we), .rs(ab[3:0]),
    .wdata(cpu_dout), .i2s_bck(i2s_bck), .i2s_ws(i2s_ws), .i2s_din(i2s_din),
    .sample(sample), .sample_tick(sample_tick)
);

// ---------------- interrupts ----------------
assign irq_n = !(via_irq || (uart_irq && irq_en[0]) || (kbd_irq && irq_en[1]));

// The button also drives NMI, through a debouncer: it must be steady
// for 2^18 clocks (about 10 ms) before the NMI line follows it.
reg [17:0] deb_cnt;
reg        btn_sync1, btn_sync2, btn_stable;
always @(posedge clk) begin
    btn_sync1 <= button; btn_sync2 <= btn_sync1;
    if (btn_sync2 == btn_stable) deb_cnt <= 0;
    else if (&deb_cnt) btn_stable <= btn_sync2;
    else deb_cnt <= deb_cnt + 18'd1;
end
assign nmi_n = !btn_stable;

// ---------------- read data for the CPU ----------------
reg [7:0] io_q;
always @* begin
    case (dev)
        3'd0: io_q = uart_q;
        3'd1: io_q = kbd_q;
        3'd2: io_q = via_q;
        3'd3: io_q = spi_q;
        3'd5: io_q = (ab[3:0] == 4'd0) ? {4'd0, border} :
                     (ab[3:0] == 4'd1) ? {7'd0, vblank} :
                     (ab[3:0] == 4'd2) ? {6'd0, irq_en} : 8'h00;
        default: io_q = 8'hFF;
    endcase
end

always @* begin
    if      (sel_ram) cpu_din = ram_q;
    else if (sel_rom) cpu_din = rom_q;
    else if (sel_fb)  cpu_din = fb_q;
    else if (sel_io)  cpu_din = io_q;
    else              cpu_din = 8'hFF;
end

endmodule
