// ch05_fbaddr_tb.v - log video.v's framebuffer address for one whole frame,
// for the Python golden model in ch05_fbaddr_model.py to check.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
// Run from hw/sim:
//   iverilog -o out/ch05_fbaddr_tb.vvp examples/ch05_fbaddr_tb.v ../rtl/video.v
//   vvp out/ch05_fbaddr_tb.vvp
//   python3 -I examples/ch05_fbaddr_model.py out/ch05_fbaddr.txt
`timescale 1ns/1ps
module ch05_fbaddr_tb;
    reg clk = 0, rst = 1;
    always #20 clk = ~clk;

    wire [14:0] fb_addr;
    wire [7:0] r, g, b; wire hs, vs, de, vblank;
    video u (.clk(clk), .rst(rst), .slot(1'b1), .fb_addr(fb_addr),
             .fb_data(8'h00), .border(4'd6), .r(r), .g(g), .b(b),
             .hs(hs), .vs(vs), .de(de), .vblank(vblank));

    integer f, n;
    initial begin
        f = $fopen("out/ch05_fbaddr.txt", "w");
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 0;              // line n of the log = clock n
        for (n = 0; n < 800 * 525; n = n + 1) begin
            $fwrite(f, "%h\n", fb_addr);     // sampled in mid-cycle
            @(negedge clk);
        end
        $fclose(f);
        $display("logged %0d clocks", n);
        $finish;
    end
endmodule
