// ch25_spi_tb.v - checks spi_sd.v: one byte each way at both speeds,
// against a mode-0 slave that changes MISO on the falling edge of SCK.
// Run from hw/:  iverilog -o sim/out/ch25_spi_tb.vvp sim/examples/ch25_spi_tb.v rtl/spi_sd.v
//                vvp sim/out/ch25_spi_tb.vvp [+late=NS]
`timescale 1ns/1ps
module ch25_spi_tb;
reg clk = 0, rst = 1, cs = 0, we = 0, a0 = 0;
reg [7:0] wdata = 0;
wire [7:0] rdata; wire sck, mosi, cs_n;
reg miso = 1;
integer errors = 0, t0, n, rises;
integer late = 10;                         // card's output delay in ns (+late=N)

spi_sd dut (.clk(clk), .rst(rst), .cs(cs), .we(we), .a0(a0), .wdata(wdata),
            .rdata(rdata), .sd_sck(sck), .sd_mosi(mosi), .sd_miso(miso), .sd_cs_n(cs_n));
always #19.84 clk = !clk;                  // 25.2 MHz
integer cycle = 0;
always @(posedge clk) cycle = cycle + 1;

// the card: samples MOSI on rising SCK, shifts out its byte on falling SCK
reg [7:0] slave_tx, slave_rx;
always @(posedge sck) begin slave_rx = {slave_rx[6:0], mosi}; rises = rises + 1; end
always @(negedge sck) if (!cs_n) begin
    slave_tx = {slave_tx[6:0], 1'b1}; #(late) miso = slave_tx[7];
end

task wr(input a, input [7:0] v); begin
    @(negedge clk); a0 = a; wdata = v; we = 1; cs = 1; @(negedge clk); cs = 0; we = 0;
end endtask

task xfer(input [7:0] out, input [7:0] card, input fast); reg [7:0] r; begin
    wr(1, {6'd0, fast, 1'b1});                       // select, speed
    slave_tx = card; miso = card[7]; rises = 0;
    wr(0, out); t0 = cycle;
    @(negedge clk); a0 = 1; #1;
    while (rdata[0]) begin @(negedge clk); #1; end                 // poll busy
    n = cycle - t0;
    a0 = 0; #1 r = rdata;
    $display("%s: sent %h, card got %h; card sent %h, we got %h; %0d clocks",
             fast ? "fast" : "slow", out, slave_rx, card, r, n);
    if (slave_rx !== out || r !== card || rises != 8) errors = errors + 1;
end endtask

initial begin
    if ($value$plusargs("late=%d", late)) $display("card output delay %0d ns", late);
    repeat (5) @(posedge clk); rst = 0;
    $display("after reset: CS pin %b, SCK %b, MOSI %b", cs_n, sck, mosi);
    xfer(8'h40, 8'hFF, 0);
    xfer(8'h95, 8'h01, 0);
    xfer(8'hA5, 8'h3C, 1);
    xfer(8'hFF, 8'hFE, 1);
    wr(1, 8'd0);
    @(negedge clk) $display("deselected: CS pin %b", cs_n);
    if (errors == 0) $display("PASS"); else $display("FAILED: %0d errors", errors);
    $finish;
end
endmodule
