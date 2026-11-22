// ch28_heartbeat.v - two debugging lights for a board that shows nothing.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt.  MIT licence.
//
// beat     blinks from the system clock alone: if it blinks, the PLL runs
//          and the bitstream is loaded, whatever the CPU is doing.
// seen     lights for a while after each pulse on "event" (a stretcher),
//          so a pulse of 40 ns becomes a flash the eye can see.
//
// To use it, borrow two LEDs in your own copy of top_tangnano20k.v:
//   wire beat, rx_seen;
//   ch28_heartbeat hb (.clk(pclk), .event_in(~uart_rx),
//                      .beat(beat), .seen(rx_seen));
//   assign led_n = ~{beat, rx_seen, leds[3:0]};

module ch28_heartbeat #(
    parameter BEAT_BIT = 24,        // 2^24 clocks = 0.67 s at 25.2 MHz
    parameter HOLD_BITS = 21        // 2^21 clocks = 83 ms
) (
    input  wire clk,
    input  wire event_in,           // 1 = something happened
    output wire beat,
    output wire seen
);

reg [BEAT_BIT:0]  count = 0;
reg [HOLD_BITS:0] hold = 0;         // top bit set = finished waiting

always @(posedge clk) begin
    count <= count + 1'b1;
    if (event_in)
        hold <= 0;                  // restart the wait on every event
    else if (!hold[HOLD_BITS])
        hold <= hold + 1'b1;
end

assign beat = count[BEAT_BIT];
assign seen = !hold[HOLD_BITS];

endmodule
