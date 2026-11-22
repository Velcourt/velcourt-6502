// spi_sd.v - an SPI master for talking to an SD card, one byte at a time.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// SPI mode 0: the clock idles low, both sides sample on the rising edge
// and change on the falling edge. Bytes go most significant bit first.
// Every byte sent brings one byte back.
//
// Registers:
//   +0  write: send this byte (and receive one)
//       read:  the byte received by the last transfer
//   +1  write: control  bit0 = select the card (CS pin low)
//                       bit1 = fast clock (3.15 MHz), else 394 kHz for start-up
//       read:  status   bit0 = transfer in progress

module spi_sd (
    input  wire       clk,
    input  wire       rst,
    input  wire       cs,          // one-clock strobe at the end of the CPU cycle
    input  wire       we,
    input  wire       a0,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output reg        sd_sck,
    output wire       sd_mosi,
    input  wire       sd_miso,
    output wire       sd_cs_n
);

reg       selected, fast;
reg [7:0] tx, rx;
reg [3:0] bits;                    // bits left in this byte
reg [5:0] div;                     // clock divider
reg [1:0] miso_sync;                // two flip-flops: enough, and fast enough
wire      busy = (bits != 0);
wire [5:0] half = fast ? 6'd3 : 6'd31;   // clocks per half SCK period - 1

always @(posedge clk) miso_sync <= {miso_sync[0], sd_miso};

always @(posedge clk) begin
    if (rst) begin
        selected <= 1'b0; fast <= 1'b0; sd_sck <= 1'b0;
        bits <= 0; div <= 0; tx <= 8'hFF;
    end else begin
        if (cs && we && a0) {fast, selected} <= wdata[1:0];
        if (cs && we && !a0 && !busy) begin
            tx <= wdata; bits <= 4'd8; div <= half;
        end else if (busy) begin
            if (div != 0) div <= div - 6'd1;
            else begin
                div <= half;
                if (!sd_sck) begin                 // rising edge: sample
                    sd_sck <= 1'b1;
                    rx <= {rx[6:0], miso_sync[1]};
                end else begin                     // falling edge: next bit
                    sd_sck <= 1'b0;
                    tx <= {tx[6:0], 1'b1};
                    bits <= bits - 4'd1;
                end
            end
        end
    end
end

assign sd_mosi = tx[7];
assign sd_cs_n = !selected;
assign rdata   = a0 ? {7'd0, busy} : rx;

endmodule
