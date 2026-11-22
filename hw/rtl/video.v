// video.v - 640x480 timing, a 320x200 16-colour framebuffer, and a border.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Each framebuffer pixel is drawn as a 2x2 block, so the 320x200 picture
// fills 640x400 of the screen. The 40 lines above and below show the
// border colour. Two pixels share a byte: the high nibble is the left one.
//
// One byte covers four screen pixels (two framebuffer pixels, each drawn
// twice), so the video needs a byte only every fourth clock. It shares the
// framebuffer's read port with the CPU: it may use the port in clocks where
// `slot` is 1. A second pair of counters runs four pixels ahead of the beam,
// so the byte for the next group of four pixels is fetched in time.

module video (
    input  wire        clk,          // pixel clock, 25.2 MHz
    input  wire        rst,
    input  wire        slot,         // 1: the read port is ours this clock
    output wire [14:0] fb_addr,      // framebuffer byte we want
    input  wire [7:0]  fb_data,      // read data, one clock after the address
    input  wire [3:0]  border,       // border colour index
    output reg  [7:0]  r, g, b,
    output reg         hs, vs, de,
    output wire        vblank        // 1 while the beam is outside the picture
);

// ---------------- 640x480 @ 60 Hz timing ----------------
localparam H_VIS = 640, H_FP = 16, H_SYNC = 96, H_BP = 48, H_TOT = 800;
localparam V_VIS = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33, V_TOT = 525;
localparam PIC_TOP = 40, PIC_BOT = 440;          // picture lines 40..439

// The beam position (hc, vc), and the fetch position (fx, fy) four ahead.
reg [9:0] hc, vc, fx, fy;
always @(posedge clk) begin
    if (rst) begin
        hc <= 0; vc <= 0; fx <= 4; fy <= 0;
    end else begin
        if (hc == H_TOT - 1) begin
            hc <= 0; vc <= (vc == V_TOT - 1) ? 10'd0 : vc + 10'd1;
        end else hc <= hc + 10'd1;
        if (fx == H_TOT - 1) begin
            fx <= 0; fy <= (fy == V_TOT - 1) ? 10'd0 : fy + 10'd1;
        end else fx <= fx + 10'd1;
    end
end

// ---------------- fetching ----------------
// framebuffer x = fx/2, y = (fy-40)/2; byte = y*160 + fx/4 = y*128 + y*32 + fx/4
wire [9:0] pic_line = fy - PIC_TOP;
wire [7:0] fby      = pic_line[8:1];
assign fb_addr = {fby, 7'd0} + {2'd0, fby, 5'd0} + {7'd0, fx[9:2]};

// Fetch in the first half of each group of four (when the slot is ours),
// catch the data the clock after, and start using it when the group begins.
wire fetch = slot && !fx[1];
reg  fetched;
reg  [7:0] next_byte, cur_byte;
always @(posedge clk) begin
    fetched <= fetch;
    if (fetched) next_byte <= fb_data;
    if (hc[1:0] == 2'b11) cur_byte <= next_byte;  // next clock starts a group
end

// ---------------- what the beam shows now ----------------
wire h_vis  = (hc < H_VIS);
wire v_vis  = (vc < V_VIS);
wire in_pic = h_vis && (vc >= PIC_TOP) && (vc < PIC_BOT);
wire hs_now = !((hc >= H_VIS + H_FP) && (hc < H_VIS + H_FP + H_SYNC)); // active low
wire vs_now = !((vc >= V_VIS + V_FP) && (vc < V_VIS + V_FP + V_SYNC));
assign vblank = (vc < PIC_TOP) || (vc >= PIC_BOT);

// ---------------- palette: 16 colours ----------------
function [23:0] palette(input [3:0] i);
    case (i)
        4'h0: palette = 24'h000000;  // black
        4'h1: palette = 24'hFFFFFF;  // white
        4'h2: palette = 24'hA83A32;  // brick red
        4'h3: palette = 24'h6ECDC8;  // teal
        4'h4: palette = 24'h8E44A4;  // violet
        4'h5: palette = 24'h4CAF50;  // leaf green
        4'h6: palette = 24'h2C3FA0;  // deep blue
        4'h7: palette = 24'hF2E35B;  // lemon
        4'h8: palette = 24'hC4762A;  // amber
        4'h9: palette = 24'h6B4A1C;  // brown
        4'hA: palette = 24'hE8837A;  // salmon
        4'hB: palette = 24'h474747;  // dark grey
        4'hC: palette = 24'h7A7A7A;  // mid grey
        4'hD: palette = 24'hA6E89C;  // mint
        4'hE: palette = 24'h7F92F0;  // sky blue
        4'hF: palette = 24'hB5B5B5;  // light grey
    endcase
endfunction

wire [3:0]  pix   = hc[1] ? cur_byte[3:0] : cur_byte[7:4];  // left pixel first
wire [23:0] color = in_pic ? palette(pix) : palette(border);

always @(posedge clk) begin
    hs <= hs_now; vs <= vs_now; de <= h_vis && v_vis;
    {r, g, b} <= (h_vis && v_vis) ? color : 24'h000000;
end

endmodule
