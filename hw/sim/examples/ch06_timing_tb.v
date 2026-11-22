// ch06_timing_tb.v - measure the video timing of video.v from its pins.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch06_timing_tb.vvp examples/ch06_timing_tb.v ../rtl/video.v
//   vvp out/ch06_timing_tb.vvp
//
// The bench runs a little over two frames, watches hs, vs, de and the
// colour, and measures every interval in pixel clocks. It also writes a
// short VCD around the end of one line (out/ch06_line.vcd).
`timescale 1ns/1ps
module ch06_timing_tb;
    reg clk = 0, rst = 1;
    always #19.841 clk = ~clk;               // 25.2 MHz: 39.683 ns period

    // the shared read port, as soc.v drives it: slot = ce, every 2nd clock
    reg slot = 0;
    always @(posedge clk) slot <= rst ? 1'b0 : ~slot;

    // a framebuffer full of $11: every picture pixel is colour 1 (white)
    wire [14:0] fb_addr; reg [7:0] fb_q = 8'h11;
    always @(posedge clk) fb_q <= 8'h11;

    wire [7:0] r, g, b; wire hs, vs, de, vblank;
    video u (.clk(clk), .rst(rst), .slot(slot), .fb_addr(fb_addr),
             .fb_data(fb_q), .border(4'd6), .r(r), .g(g), .b(b),
             .hs(hs), .vs(vs), .de(de), .vblank(vblank));

    // ------------------------------------------------ measuring
    integer n = 0;                           // clocks since reset ended
    integer t_hs_fall = -1, t_hs_rise = -1, t_de_fall = -1, t_de_rise = -1;
    integer t_vs_fall = -1, t_vs_rise = -1;
    integer de_pulses = 0, pic_pulses = 0, first_pic = -1, frames = 0;
    reg hs_d = 1, vs_d = 1, de_d = 0, pic_seen = 0;
    integer errors = 0;

    task check(input [255:0] what, input integer got, input integer want);
        if (got != want) begin
            $display("FAIL %0s: %0d, expected %0d", what, got, want);
            errors = errors + 1;
        end
    endtask

    always @(posedge clk) if (!rst) begin
        n = n + 1;
        if (de && {r, g, b} == 24'hFFFFFF) pic_seen = 1;
        if (!de && {r, g, b} != 24'h000000) check("black in blanking", 1, 0);
        // ---- horizontal ----
        if (hs_d && !hs) begin                       // hs falls
            if (t_hs_fall >= 0) check("line period", n - t_hs_fall, 800);
            if (t_de_fall >= 0 && n - t_de_fall < 800)
                check("front porch", n - t_de_fall, 16);
            if (t_de_fall >= 0 && frames == 1 && de_pulses == 100)
                $display("front porch   %0d clocks", n - t_de_fall);
            t_hs_fall = n;
        end
        if (!hs_d && hs) begin                       // hs rises
            check("hsync width", n - t_hs_fall, 96);
            if (frames == 1 && de_pulses == 100)
                $display("hsync width   %0d clocks", n - t_hs_fall);
            t_hs_rise = n;
        end
        if (!de_d && de) begin                       // de rises
            if (t_hs_rise >= 0 && n - t_hs_rise < 800)
                check("back porch", n - t_hs_rise, 48);
            if (frames == 1 && de_pulses == 100)
                $display("back porch    %0d clocks", n - t_hs_rise);
            t_de_rise = n; pic_seen = 0;
        end
        if (de_d && !de) begin                       // de falls
            if (t_hs_fall >= 0)                      // skip the first line
                check("active width", n - t_de_rise, 640);
            if (frames == 1 && de_pulses == 99)
                $display("active pixels %0d clocks", n - t_de_rise);
            if (pic_seen) begin
                if (first_pic < 0) first_pic = de_pulses;
                pic_pulses = pic_pulses + 1;
            end
            de_pulses = de_pulses + 1;
            t_de_fall = n;
        end
        // ---- vertical ----
        if (vs_d && !vs) begin                       // vs falls
            if (t_vs_fall >= 0) begin
                $display("frame         %0d clocks = %0d lines",
                         n - t_vs_fall, (n - t_vs_fall) / 800);
                check("frame period", n - t_vs_fall, 420000);
                $display("visible lines %0d, picture lines %0d (first %0d)",
                         de_pulses, pic_pulses, first_pic);
                check("visible lines", de_pulses, 480);
                check("picture lines", pic_pulses, 400);
                check("first picture line", first_pic, 40);
            end
            $display("last de to vs %0d clocks", n - t_de_fall);
            check("last de to vs", n - t_de_fall, 160 + 10 * 800);
            t_vs_fall = n; frames = frames + 1;
            de_pulses = 0; pic_pulses = 0; first_pic = -1;
        end
        if (!vs_d && vs) begin                       // vs rises
            $display("vsync width   %0d clocks = %0d lines",
                     n - t_vs_fall, (n - t_vs_fall) / 800);
            check("vsync width", n - t_vs_fall, 2 * 800);
            t_vs_rise = n;
        end
        if (!de_d && de && t_vs_rise >= 0 && n - t_vs_rise < 420000) begin
            if (de_pulses == 0) begin
                $display("vs to first de %0d clocks = %0d lines",
                         n - t_vs_rise, (n - t_vs_rise) / 800);
                check("vs to first de", n - t_vs_rise, 33 * 800);
            end
        end
        hs_d = hs; vs_d = vs; de_d = de;
        if (frames == 3) begin
            if (errors == 0) $display("PASS: all timing checks");
            else $fatal(1, "%0d timing errors", errors);
            $finish;
        end
    end

    // ------------------------------------------------ a short waveform
    initial begin
        $dumpfile("out/ch06_line.vcd");
        repeat (4) @(posedge clk);
        rst = 0;
        wait (n == 800 + 630);                       // line 1, hc near 630
        $dumpvars(1, ch06_timing_tb.u.hc, ch06_timing_tb.u.hs_now,
                  ch06_timing_tb.u.h_vis, hs, de, clk);
        wait (n == 800 + 664);
        $dumpoff;
    end
endmodule
