// ch04_ce_tb.v - release reset and print the first system clocks of the
// computer: the clock enable, the address bus and the data the CPU reads.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch04_ce.vvp examples/ch04_ce_tb.v ../rtl/soc.v \
//     ../rtl/cpu6502.v ../rtl/alu6502.v ../rtl/video.v \
//     ../rtl/uart.v ../rtl/ps2_kbd.v ../rtl/spi_sd.v \
//     ../rtl/via.v ../rtl/sound.v
//   vvp out/ch04_ce.vvp

module tb;
reg clk = 0, rst = 1;
soc #(.ROM_FILE("../build/rom.hex")) dut (
    .clk(clk), .rst(rst), .uart_rx(1'b1), .ps2_clk(1'b1), .ps2_dat(1'b1),
    .sd_miso(1'b1), .button(1'b0)
);
initial begin dut.btn_stable = 1'b0; dut.deb_cnt = 18'd0; end  // power-up

always #1 clk = ~clk;

integer n;
initial begin
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 0;
    $display("clock ce state  ab    din   (the CPU latches din when ce=1)");
    for (n = 1; n <= 22; n = n + 1) begin
        @(negedge clk);              // look in the middle of each clock
        $display("%4d   %b  %2d    %h  %h", n, dut.ce, dut.u_cpu.state,
                 dut.ab, dut.cpu_din);
    end
    $finish;
end
endmodule
