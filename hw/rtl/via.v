// via.v - the useful part of a 6522 VIA: two 8-bit ports and two timers.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Register numbers follow the real 6522, so 6522 code runs unchanged
// as long as it only uses what is here:
//   0 ORB/IRB   1 ORA/IRA   2 DDRB   3 DDRA
//   4 T1 low  (read: counter, clears T1 flag; write: latch)
//   5 T1 high (write: latch, load the counter, start, clear T1 flag)
//   6 T1 latch low   7 T1 latch high
//   8 T2 low  (read: counter, clears T2 flag; write: latch)
//   9 T2 high (write: load, start, clear T2 flag)
//  11 ACR (bit 6 = T1 repeats)   13 IFR   14 IER   15 ORA
// Not here: the shift register, handshake lines CA1/CA2/CB1/CB2, PB7
// timer output, T2 pulse counting. Timers count CPU cycles; a period of
// N gives an interrupt every N+1 cycles (the real chip takes N+2 in
// free-running mode).

module via (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick,        // one pulse per CPU cycle
    input  wire       cs,          // one-clock strobe at the end of the CPU cycle
    input  wire       we,
    input  wire [3:0] rs,          // register select
    input  wire [7:0] wdata,
    output reg  [7:0] rdata,
    output wire       irq,
    input  wire [7:0] pa_in, pb_in,
    output wire [7:0] pa_out, pb_out,
    output reg  [7:0] ddra, ddrb
);

reg [7:0]  ora, orb, acr, ier;
reg [15:0] t1_cnt, t1_latch, t2_cnt;
reg [7:0]  t2_latch_lo;
reg        t1_if, t2_if, t1_armed, t2_armed;

assign pa_out = ora;
assign pb_out = orb;
wire [7:0] ifr = {(t1_if & ier[6]) | (t2_if & ier[5]), t1_if, t2_if, 5'd0};
assign irq = ifr[7];

// Reads (combinational; the CPU latches them at the end of the cycle)
always @* begin
    case (rs)
        4'd0:  rdata = (orb & ddrb) | (pb_in & ~ddrb);
        4'd1, 4'd15: rdata = (ora & ddra) | (pa_in & ~ddra);
        4'd2:  rdata = ddrb;
        4'd3:  rdata = ddra;
        4'd4:  rdata = t1_cnt[7:0];
        4'd5:  rdata = t1_cnt[15:8];
        4'd6:  rdata = t1_latch[7:0];
        4'd7:  rdata = t1_latch[15:8];
        4'd8:  rdata = t2_cnt[7:0];
        4'd9:  rdata = t2_cnt[15:8];
        4'd11: rdata = acr;
        4'd13: rdata = ifr;
        4'd14: rdata = {1'b1, ier[6:0]};
        default: rdata = 8'h00;
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        ora <= 0; orb <= 0; ddra <= 0; ddrb <= 0; acr <= 0; ier <= 0;
        t1_if <= 0; t2_if <= 0; t1_armed <= 0; t2_armed <= 0;
        t1_cnt <= 16'hFFFF; t2_cnt <= 16'hFFFF; t1_latch <= 16'hFFFF;
    end else begin
        // ---- timers count down once per CPU cycle ----
        if (tick) begin
            if (t1_cnt == 16'd0) begin
                if (t1_armed) t1_if <= 1'b1;
                if (acr[6]) t1_cnt <= t1_latch;          // free-running
                else begin t1_cnt <= 16'hFFFF; t1_armed <= 1'b0; end
            end else t1_cnt <= t1_cnt - 16'd1;

            if (t2_cnt == 16'd0) begin
                if (t2_armed) t2_if <= 1'b1;
                t2_armed <= 1'b0;
            end
            t2_cnt <= t2_cnt - 16'd1;
        end

        // ---- CPU access ----
        if (cs && !we) begin
            if (rs == 4'd4) t1_if <= 1'b0;
            if (rs == 4'd8) t2_if <= 1'b0;
        end
        if (cs && we) case (rs)
            4'd0:  orb <= wdata;
            4'd1, 4'd15: ora <= wdata;
            4'd2:  ddrb <= wdata;
            4'd3:  ddra <= wdata;
            4'd4, 4'd6: t1_latch[7:0] <= wdata;
            4'd5: begin
                t1_latch[15:8] <= wdata;
                t1_cnt <= {wdata, t1_latch[7:0]};
                t1_if <= 1'b0; t1_armed <= 1'b1;
            end
            4'd7: begin t1_latch[15:8] <= wdata; t1_if <= 1'b0; end
            4'd8:  t2_latch_lo <= wdata;
            4'd9: begin
                t2_cnt <= {wdata, t2_latch_lo};
                t2_if <= 1'b0; t2_armed <= 1'b1;
            end
            4'd11: acr <= wdata;
            4'd13: begin                                  // write 1s to clear
                if (wdata[6]) t1_if <= 1'b0;
                if (wdata[5]) t2_if <= 1'b0;
            end
            4'd14: ier <= wdata[7] ? (ier | {1'b0, wdata[6:0]})
                                   : (ier & ~{1'b0, wdata[6:0]});
            default: ;
        endcase
    end
end

endmodule
