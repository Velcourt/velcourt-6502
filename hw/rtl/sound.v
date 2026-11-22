// sound.v - three square-wave voices, one noise voice, and an I2S output.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// The sample rate is 25.2 MHz / 512 = 49 219 Hz. Each tone voice adds
// its 16-bit step to a phase accumulator once per sample; the top bit is
// the square wave, so  frequency = step x 49219 / 65536 = step x 0.751 Hz.
// (440 Hz, the A above middle C, is step 586.)
//
// Registers:
//   +0,+1  voice 0 step (low, high)   +2  voice 0 volume (0-15)
//   +4,+5  voice 1 step               +6  voice 1 volume
//   +8,+9  voice 2 step               +10 voice 2 volume
//   +12    noise rate (0-255)         +13 noise volume
//
// The board's amplifier (a MAX98357A-type chip) takes I2S: a bit clock
// BCK, a word select WS (left/right) and the data, MSB first, one bit
// clock after WS changes. We send the same 16-bit sample to both sides.

module sound (
    input  wire        clk,         // 25.2 MHz
    input  wire        rst,
    input  wire        cs,          // one-clock strobe at the end of the CPU cycle
    input  wire        we,
    input  wire [3:0]  rs,
    input  wire [7:0]  wdata,
    output wire        i2s_bck,
    output wire        i2s_ws,
    output wire        i2s_din,
    output reg  [15:0] sample,      // for the simulator's WAV writer
    output wire        sample_tick
);

reg [15:0] step [0:2];
reg [3:0]  vol  [0:2];
reg [7:0]  nrate;
reg [3:0]  nvol;

always @(posedge clk) begin
    if (rst) begin
        step[0] <= 0; step[1] <= 0; step[2] <= 0;
        vol[0] <= 0;  vol[1] <= 0;  vol[2] <= 0;
        nrate <= 0; nvol <= 0;
    end else if (cs && we) case (rs)
        4'd0:  step[0][7:0]  <= wdata;   4'd1:  step[0][15:8] <= wdata;
        4'd2:  vol[0] <= wdata[3:0];
        4'd4:  step[1][7:0]  <= wdata;   4'd5:  step[1][15:8] <= wdata;
        4'd6:  vol[1] <= wdata[3:0];
        4'd8:  step[2][7:0]  <= wdata;   4'd9:  step[2][15:8] <= wdata;
        4'd10: vol[2] <= wdata[3:0];
        4'd12: nrate <= wdata;
        4'd13: nvol  <= wdata[3:0];
        default: ;
    endcase
end

// ---------------- sample clock and I2S framing ----------------
// 512 clocks per sample: 32 bit clocks of 16 system clocks each.
reg [8:0] div;
always @(posedge clk) div <= rst ? 9'd0 : div + 9'd1;
assign sample_tick = (div == 9'd511);
assign i2s_bck = div[3];                     // 1.575 MHz
wire   bck_fall = (div[3:0] == 4'd15);       // data changes as BCK falls
wire [4:0] bitn = div[8:4];                  // bit-clock number 0..31

// ---------------- voices ----------------
reg [15:0] phase [0:2];
reg [15:0] nphase;
reg [16:0] lfsr;
integer k;
always @(posedge clk) begin
    if (rst) begin
        phase[0] <= 0; phase[1] <= 0; phase[2] <= 0;
        nphase <= 0; lfsr <= 17'h1;
    end else if (sample_tick) begin
        for (k = 0; k < 3; k = k + 1) phase[k] <= phase[k] + step[k];
        {nphase} <= nphase + {nrate, 8'd0};
        if (nphase + {nrate, 8'd0} < nphase)            // overflow: new noise bit
            lfsr <= {lfsr[0] ^ lfsr[3], lfsr[16:1]};
    end
end

// Each voice contributes +vol*512 or -vol*512
function signed [15:0] level(input high, input [3:0] v);
    level = high ? $signed({3'd0, v, 9'd0}) : -$signed({3'd0, v, 9'd0});
endfunction

wire signed [15:0] mix = level(phase[0][15], vol[0]) + level(phase[1][15], vol[1])
                       + level(phase[2][15], vol[2]) + level(lfsr[0], nvol);

// ---------------- I2S shift register ----------------
// Bit clock n = 0..31 of a frame. WS is low for n = 0..15 (left) and high
// for 16..31 (right). Data runs one bit clock behind WS, so the left MSB
// goes out at n = 1 and the right LSB at n = 0 of the next frame.
reg [31:0] shreg;
reg        ws_r, din_r;
always @(posedge clk) begin
    if (sample_tick) sample <= mix;
    if (bck_fall) begin
        ws_r  <= (bitn >= 5'd16);
        din_r <= shreg[31];
        if (bitn == 5'd0) shreg <= {sample, sample};    // left and right
        else              shreg <= {shreg[30:0], 1'b0};
    end
end
assign i2s_ws  = ws_r;
assign i2s_din = din_r;

endmodule
