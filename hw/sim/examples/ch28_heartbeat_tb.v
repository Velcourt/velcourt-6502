// ch28_heartbeat_tb.v - check the heartbeat with small counters.
// iverilog -o hb ch28_heartbeat.v ch28_heartbeat_tb.v && vvp hb
`timescale 1ns/1ps
module tb;
reg clk = 0, ev = 0;
wire beat, seen;
ch28_heartbeat #(.BEAT_BIT(3), .HOLD_BITS(4)) dut (
    .clk(clk), .event_in(ev), .beat(beat), .seen(seen));
always #20 clk = ~clk;
integer i, errors = 0, flips = 0, lit = 0;
reg last;
initial begin
    #1 last = beat;
    for (i = 0; i < 64; i = i + 1) begin   // beat flips every 2^3 clocks
        @(posedge clk); #1;
        if (beat != last) flips = flips + 1;
        last = beat;
    end
    if (flips != 8) errors = errors + 1;
    @(negedge clk) ev = 1;                  // one pulse, one clock long
    @(negedge clk) ev = 0;
    for (i = 0; i < 40; i = i + 1) begin   // count the clocks after it
        @(posedge clk); #1;
        if (seen) lit = lit + 1;
    end
    if (lit != 15) errors = errors + 1;     // 2^4 clocks, one was the pulse
    $display("beat flips: %0d in 64 clocks", flips);
    $display("seen: lit for %0d clocks after the pulse", lit);
    if (errors) $display("FAIL"); else $display("PASS");
    $finish;
end
endmodule
