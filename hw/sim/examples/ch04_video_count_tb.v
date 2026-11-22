// ch04_video_count_tb.v - run the counters of video.v for two frames and
// measure the sync pulses by counting clocks.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch04_video_count.vvp examples/ch04_video_count_tb.v \
//     ../rtl/video.v
//   vvp out/ch04_video_count.vvp

module tb;
reg clk = 0, rst = 1;
wire [7:0] r, g, b;
wire hs, vs, de, vblank;
wire [14:0] fb_addr;
video dut (.clk(clk), .rst(rst), .slot(1'b0), .fb_addr(fb_addr),
           .fb_data(8'h00), .border(4'd6), .r(r), .g(g), .b(b),
           .hs(hs), .vs(vs), .de(de), .vblank(vblank));

always #1 clk = ~clk;

integer clocks = 0;                // clocks since reset was released
integer hs_fall = -1, hs_low = 0, vs_fall = -1, lines = 0;
integer de_clocks = 0, frames = 0;
reg hs_old = 1, vs_old = 1;
always @(posedge clk) if (!rst) begin
    clocks = clocks + 1;
    if (de) de_clocks = de_clocks + 1;
    if (!hs) hs_low = hs_low + 1;
    if (hs_old && !hs) begin       // falling edge of HSYNC
        if (hs_fall >= 0 && frames == 1 && lines == 1)
            $display("HSYNC period %0d clocks, low for %0d",
                     clocks - hs_fall, hs_low);
        hs_fall = clocks; hs_low = 0; lines = lines + 1;
    end
    if (vs_old && !vs) begin       // falling edge of VSYNC
        if (vs_fall >= 0)
            $display("VSYNC period %0d clocks = %0d lines; de=1 for %0d",
                     clocks - vs_fall, lines, de_clocks);
        vs_fall = clocks; lines = 0; de_clocks = 0; frames = frames + 1;
    end
    hs_old = hs; vs_old = vs;
end

initial begin
    repeat (4) @(posedge clk);
    rst = 0;
    wait (frames == 3);
    $display("stopped after %0d clocks", clocks);
    $finish;
end
endmodule
