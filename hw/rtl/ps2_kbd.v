// ps2_kbd.v - receives scan codes from a PS/2 keyboard into a FIFO.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// The keyboard drives both lines. On each falling edge of PS2 clock
// the data line holds one bit: a 0 start bit, 8 data bits (LSB first),
// an odd-parity bit and a 1 stop bit. The 6502 turns the scan codes
// into characters in software (chapter 24).
//
// Registers:
//   +0  read: next scan code (removes it)
//   +1  read: status  bit0 = a code is waiting, bit1 = a frame had an error

module ps2_kbd (
    input  wire       clk,
    input  wire       rst,
    input  wire       cs,          // one-clock strobe at the end of the CPU cycle
    input  wire       we,
    input  wire       a0,
    output wire [7:0] rdata,
    output wire       irq,
    input  wire       ps2_clk,
    input  wire       ps2_dat
);

// Synchronise both lines, and filter the clock: it must be stable
// for 8 system clocks before we believe it changed.
reg [2:0] cs_sync, ds_sync;
always @(posedge clk) begin
    cs_sync <= {cs_sync[1:0], ps2_clk};
    ds_sync <= {ds_sync[1:0], ps2_dat};
end
reg [2:0] stable;
reg       kclk = 1'b1, kclk_old = 1'b1;
always @(posedge clk) begin
    if (cs_sync[2] == kclk) stable <= 0;
    else if (stable == 3'd7) kclk <= cs_sync[2];
    else stable <= stable + 3'd1;
    kclk_old <= kclk;
end
wire fall = kclk_old && !kclk;

// Shift in 11 bits. A timeout resets a frame left half-finished.
reg [10:0] shift;
reg [3:0]  nbits;
reg [15:0] idle;
reg        got, bad;
always @(posedge clk) begin
    got <= 1'b0;
    if (rst) begin
        nbits <= 0; idle <= 0;
    end else if (fall) begin
        shift <= {ds_sync[2], shift[10:1]};
        idle  <= 0;
        if (nbits == 4'd10) begin
            nbits <= 0;
            got   <= 1'b1;
        end else nbits <= nbits + 4'd1;
    end else if (nbits != 0) begin
        if (idle == 16'd50000) nbits <= 0;      // about 2 ms with no clock
        else idle <= idle + 16'd1;
    end
end
// frame = {stop, parity, d7..d0, start}
wire       frame_ok = got && !shift[0] && shift[10] && ^shift[9:1];
wire [7:0] code     = shift[8:1];

// FIFO of 16 scan codes
reg [7:0] fifo [0:15];
reg [3:0] wp, rp;
reg [4:0] count;
wire      pop = cs && !we && !a0 && (count != 0);
always @(posedge clk) begin
    if (rst) begin
        wp <= 0; rp <= 0; count <= 0; bad <= 1'b0;
    end else begin
        if (got && !frame_ok) bad <= 1'b1;
        if (cs && !we && a0) bad <= 1'b0;
        if (frame_ok && count != 5'd16) begin
            fifo[wp] <= code; wp <= wp + 4'd1;
        end
        if (pop) rp <= rp + 4'd1;
        count <= count + ((frame_ok && count != 5'd16) ? 5'd1 : 5'd0)
                       - (pop ? 5'd1 : 5'd0);
    end
end

assign rdata = a0 ? {6'd0, bad, count != 0} : fifo[rp];
assign irq   = (count != 0);

endmodule
