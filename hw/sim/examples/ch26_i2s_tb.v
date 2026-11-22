// ch26_i2s_tb.v - checks the I2S output of sound.v. It plays a tone,
// decodes BCK/WS/DIN like the amplifier would, and compares every
// decoded word with the sample the mixer produced.
// Run from hw/:  iverilog -o sim/out/ch26_i2s_tb.vvp sim/examples/ch26_i2s_tb.v rtl/sound.v
//                vvp sim/out/ch26_i2s_tb.vvp
`timescale 1ns/1ps
module ch26_i2s_tb;
reg clk = 0, rst = 1, cs = 0, we = 0;
reg [3:0] rs = 0; reg [7:0] wdata = 0;
wire bck, ws, din, tick; wire [15:0] sample;
integer errors = 0, words = 0, nbck = 0, i;

sound dut (.clk(clk), .rst(rst), .cs(cs), .we(we), .rs(rs), .wdata(wdata),
           .i2s_bck(bck), .i2s_ws(ws), .i2s_din(din), .sample(sample), .sample_tick(tick));
always #19.84 clk = !clk;                  // 25.2 MHz

task wr(input [3:0] r, input [7:0] v); begin
    @(negedge clk); rs = r; wdata = v; we = 1; cs = 1; @(negedge clk); cs = 0; we = 0;
end endtask

// The receiver: sample DIN and WS on each rising edge of BCK. A word starts
// one bit clock after WS changes and is 16 bits long, MSB first.
reg ws_old = 1; integer pos = 99; reg [15:0] word; reg [15:0] expect_l;
reg [15:0] last_l; reg ws_word = 0;
always @(posedge bck) begin
    nbck = nbck + 1;
    if (pos < 16) begin
        word = {word[14:0], din}; pos = pos + 1;
        if (pos == 16) begin
            words = words + 1;
            if (!ws_word) begin last_l = word; if (word !== expect_l) errors = errors + 1; end
            else if (word !== last_l) errors = errors + 1;   // right = left
        end
    end
    if (ws != ws_old) begin pos = 0; ws_word = ws; if (!ws) expect_l = sample; end
    ws_old = ws;
end

// print the first frames: one line per bit clock
integer show = 0;
always @(posedge bck) if (show > 0 && show <= 34) begin
    $display("bck %2d  WS=%b  DIN=%b", show, ws, din); show = show + 1;
end

initial begin
    repeat (5) @(posedge clk); rst = 0;
    wr(0, 8'h4A); wr(1, 8'h02); wr(2, 8'd15);     // voice 0: step 586 (440 Hz), loudest
    wr(4, 8'h15); wr(5, 8'h03); wr(6, 8'd6);      // voice 1: step 789
    wr(12, 8'd40); wr(13, 8'd2);                  // a little noise
    repeat (3) @(posedge tick);
    @(negedge ws); show = 1;
    repeat (2000) @(posedge tick);
    $display("%0d words decoded, %0d bit clocks, %0d mismatches", words, nbck, errors);
    if (errors == 0 && words > 3900) $display("PASS"); else $display("FAILED");
    $finish;
end
endmodule
