// ch08_tb_fetch.v - the framebuffer's shared read port, checked pixel by pixel.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
//   iverilog -o ch08_tb_fetch.vvp ch08_tb_fetch.v ../../rtl/video.v
//   vvp ch08_tb_fetch.vvp
//
// The framebuffer and its read-port multiplexer are written exactly as in
// rtl/soc.v. The framebuffer is filled with random bytes, a pretend CPU
// reads random framebuffer addresses in every one of its cycles, and the
// test bench checks two things for two whole frames:
//   - every visible pixel shows the colour the framebuffer says it should
//   - every CPU read returns the byte at the address the CPU asked for

module tb;
reg clk = 0, rst = 1;
always #20 clk = ~clk;                   // 40 ns period; only the order matters

// ---- as in soc.v ----
reg ce;
always @(posedge clk) ce <= rst ? 1'b0 : ~ce;

reg  [14:0] fb_cpu_addr = 0;
wire [14:0] fb_vid_addr;
wire [14:0] fb_rd_addr = ce ? fb_vid_addr : fb_cpu_addr;
reg  [7:0]  fb [0:32767];
reg  [7:0]  fb_q;
always @(posedge clk) fb_q <= fb[fb_rd_addr];

wire [7:0] r, g, b;
wire hs, vs, de, vblank;
video u_video (
    .clk(clk), .rst(rst),
    .slot(ce), .fb_addr(fb_vid_addr), .fb_data(fb_q), .border(4'd6),
    .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de), .vblank(vblank)
);

// the expected colour of screen pixel (x, y)
function [23:0] expect_rgb(input integer x, input integer y);
    reg [7:0] v; reg [3:0] pix;
    begin
        if (x >= 640 || y >= 480) expect_rgb = 24'h000000;
        else if (y < 40 || y >= 440) expect_rgb = u_video.palette(4'd6);
        else begin
            v = fb[((y - 40) / 2) * 160 + x / 4];
            pix  = ((x / 2) % 2 == 0) ? v[7:4] : v[3:0];
            expect_rgb = u_video.palette(pix);
        end
    end
endfunction

integer i, clocks = 0, pix_checked = 0, cpu_checked = 0, errors = 0;
integer x_was, y_was;
reg [14:0] cpu_asked;
reg [31:0] seed = 32'd12345;

initial begin
    for (i = 0; i < 32768; i = i + 1) fb[i] = $random(seed);
    #100 rst = 0;
end

always @(posedge clk) if (!rst) begin
    x_was = u_video.hc; y_was = u_video.vc;      // beam before this edge
    if (ce) begin
        // the CPU latches its data in the clock with ce=1
        if (clocks > 2) begin
            cpu_checked = cpu_checked + 1;
            if (fb_q !== fb[cpu_asked]) errors = errors + 1;
        end
    end
    #1;
    if ({r, g, b} !== expect_rgb(x_was, y_was)) begin
        errors = errors + 1;
        if (errors < 5) $display("pixel %0d,%0d wrong", x_was, y_was);
    end
    pix_checked = pix_checked + 1;
    if (!ce) begin                                 // a new CPU cycle begins
        cpu_asked = $unsigned($random(seed)) % 32000;
        fb_cpu_addr = cpu_asked;
    end
    clocks = clocks + 1;
    if (clocks == 2 * 800 * 525) begin
        $display("first bytes of line 0: %h %h %h", fb[0], fb[1], fb[2]);
        $display("clocks %0d, pixels checked %0d, CPU reads checked %0d",
            clocks, pix_checked, cpu_checked);
        $display("%s: %0d errors", errors ? "FAIL" : "PASS", errors);
        $finish;
    end
end
// a trace of the start of picture line 40 (first frame), sampled in the
// middle of each clock, when every signal is stable
always @(negedge clk)
    if (!rst && clocks < 800 * 525 && u_video.vc == 40 && u_video.hc < 13) begin
        $write("hc=%2d ce=%0d fx=%2d fetch=%0d rd_addr=%5d fb_q=%h ",
            u_video.hc, ce, u_video.fx, u_video.fetch, fb_rd_addr, fb_q);
        $display("next=%h cur=%h pix=%h",
            u_video.next_byte, u_video.cur_byte, u_video.pix);
    end
endmodule
