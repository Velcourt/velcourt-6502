// uart.v - 8N1 serial port with a 256-byte receive FIFO.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Registers (offset from the device base):
//   +0  read: next received byte (removes it from the FIFO)
//       write: send this byte
//   +1  read: status  bit0 = a byte is waiting, bit1 = transmitter busy,
//                     bit2 = a byte was lost because the FIFO was full
//
// DIV is the system clock divided by the baud rate:
// 25.2 MHz / 115200 = 218.75, so 219 gives 115068 baud (0.11 % slow).

module uart #(
    parameter DIV = 219,
    parameter FIFO_BITS = 8        // 2^8 = 256 bytes: room to paste a program
) (
    input  wire       clk,
    input  wire       rst,
    // CPU side
    input  wire       cs,          // one-clock strobe at the end of a CPU cycle
                                   // that addresses this device
    input  wire       we,
    input  wire       a0,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire       irq,         // a byte is waiting
    // pins
    input  wire       rx,
    output reg        tx
);

// ---------------- transmitter ----------------
reg [9:0]  tx_shift;               // stop bit, 8 data bits, start bit
reg [3:0]  tx_bits;                // bits left to send
reg [15:0] tx_cnt;                 // clocks left in the current bit
// busy until the stop bit has lasted its full time
wire       tx_busy = (tx_bits != 0) || (tx_cnt != 0);

always @(posedge clk) begin
    if (rst) begin
        tx <= 1'b1; tx_bits <= 0; tx_cnt <= 0;
    end else if (cs && we && !a0 && !tx_busy) begin
        tx_shift <= {1'b1, wdata, 1'b0};
        tx_bits  <= 4'd10;
    end else if (tx_cnt != 0) begin
        tx_cnt <= tx_cnt - 16'd1;
    end else if (tx_bits != 0) begin
        tx       <= tx_shift[0];       // next bit onto the wire
        tx_shift <= {1'b1, tx_shift[9:1]};
        tx_cnt   <= DIV - 1;
        tx_bits  <= tx_bits - 4'd1;
    end
end

// ---------------- receiver ----------------
// Synchronise the pin first: it comes from another clock domain.
reg [2:0] rx_sync;
always @(posedge clk) rx_sync <= {rx_sync[1:0], rx};
wire rx_in = rx_sync[2];

reg [15:0] rx_cnt;
reg [3:0]  rx_bits;
reg [7:0]  rx_shift;
reg        rx_active;
reg        rx_done;
always @(posedge clk) begin
    rx_done <= 1'b0;
    if (rst) begin
        rx_active <= 1'b0;
    end else if (!rx_active) begin
        if (!rx_in) begin                       // start bit begins
            rx_active <= 1'b1;
            rx_cnt    <= DIV / 2;               // sample in the middle of bits
            rx_bits   <= 4'd0;
        end
    end else if (rx_cnt != 0) begin
        rx_cnt <= rx_cnt - 16'd1;
    end else begin
        rx_cnt <= DIV - 1;
        if (rx_bits == 0) begin
            if (rx_in) rx_active <= 1'b0;       // false start: a glitch
            else rx_bits <= 4'd1;
        end else if (rx_bits <= 4'd8) begin
            rx_shift <= {rx_in, rx_shift[7:1]}; // LSB arrives first
            rx_bits  <= rx_bits + 4'd1;
        end else begin                          // stop bit
            rx_active <= 1'b0;
            rx_done   <= rx_in;                 // keep only well-framed bytes
        end
    end
end

// ---------------- receive FIFO ----------------
localparam DEPTH = 1 << FIFO_BITS;
reg [7:0]           fifo [0:DEPTH-1];
reg [FIFO_BITS-1:0] wp, rp;
reg [FIFO_BITS:0]   count;
reg                 overrun;
wire full = (count == DEPTH);
wire pop  = cs && !we && !a0 && (count != 0);
always @(posedge clk) begin
    if (rst) begin
        wp <= 0; rp <= 0; count <= 0; overrun <= 1'b0;
    end else begin
        if (rx_done) begin
            if (full) overrun <= 1'b1;
            else begin fifo[wp] <= rx_shift; wp <= wp + 1'b1; end
        end
        if (pop) rp <= rp + 1'b1;
        if (cs && !we && a0) overrun <= 1'b0;   // reading status clears it
        count <= count + ((rx_done && !full) ? 1'b1 : 1'b0) - (pop ? 1'b1 : 1'b0);
    end
end

assign rdata = a0 ? {5'd0, overrun, tx_busy, count != 0} : fifo[rp];
assign irq   = (count != 0);

endmodule
