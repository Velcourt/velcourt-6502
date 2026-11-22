// ch04_debounce_tb.v - press and release button S2 with contact bounce
// and watch the NMI line that soc.v's debouncer drives.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch04_debounce.vvp examples/ch04_debounce_tb.v \
//     ../rtl/soc.v \
//     ../rtl/cpu6502.v ../rtl/alu6502.v ../rtl/video.v \
//     ../rtl/uart.v ../rtl/ps2_kbd.v ../rtl/spi_sd.v \
//     ../rtl/via.v ../rtl/sound.v
//   vvp out/ch04_debounce.vvp
// Add -DNO_INIT to iverilog to see what happens without the power-up values.

module tb;
reg clk = 0, rst = 1, button = 0;  // rst stays 1: the CPU sleeps throughout
soc #(.ROM_FILE("../build/rom.hex")) dut (
    .clk(clk), .rst(rst), .uart_rx(1'b1), .ps2_clk(1'b1), .ps2_dat(1'b1),
    .sd_miso(1'b1), .button(button)
);

always #1 clk = ~clk;
integer clocks = 0, last = 0;     // last = clock of the last contact change
always @(posedge clk) clocks <= clocks + 1;

`ifndef NO_INIT
// The FPGA loads every flip-flop with a known value at power-up (0 here).
// Icarus starts them as x, so we give the debouncer the same start.
initial begin dut.btn_stable = 1'b0; dut.deb_cnt = 18'd0; end
`endif

// print every change of the NMI line
always @(dut.nmi_n)
    $display("clock %7d: nmi_n = %b", clocks, dut.nmi_n);

// contact bounce: the line flips n times, at irregular short intervals
task bounce(input level, input integer n);
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            button = (i % 2 == 0) ? level : !level;
            last = clocks;
            repeat (1500 + 700 * (i % 3)) @(posedge clk);
        end
        button = level;
    end
endtask

initial begin
    repeat (1000) @(posedge clk);
    $display("clock %7d: press (bouncing)", clocks);
    bounce(1'b1, 9);
    $display("clock %7d: last bounce, button now held", last);
    repeat (400000) @(posedge clk);
    $display("clock %7d: release (bouncing)", clocks);
    bounce(1'b0, 7);
    $display("clock %7d: last bounce, button now released", last);
    repeat (300000) @(posedge clk);
    $display("clock %7d: end, nmi_n = %b, deb_cnt = %h", clocks, dut.nmi_n,
             dut.deb_cnt);
    $finish;
end
endmodule
