// ch17_irq_tb.v - cpu6502 and the VIA on a 64 KB memory, for interrupts.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
//   sh examples/ch17_irq.sh [+from=N +to=M] [+nmi=N]     (from hw/sim)
//
// The image (+prog=file.hex, 64 KB, one byte per line) brings its own
// vectors. The VIA sits at $BF20-$BF2F as in soc.v. The bench prints a
// line each time the CPU enters the IRQ or NMI handler, prints every bus
// cycle between cycles +from and +to, and can pull NMI low for one cycle
// at cycle +nmi. It stops at a JMP * loop or after +max cycles.
`timescale 1ns/1ps
module ch17_irq_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout, via_q; wire we, sync, via_irq;
    wire sel_via = (ab[15:4] == 12'hBF2);
    wire [7:0] din = sel_via ? via_q : mem[ab];
    reg  nmi_n = 1;
    wire [7:0] leds;

    // one CPU cycle per clock here, so ce, tick and the strobe are all 1
    cpu6502 u_cpu (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout),
                   .we(we), .din(din), .irq_n(!via_irq), .nmi_n(nmi_n),
                   .sync(sync));
    via u_via (.clk(clk), .rst(rst), .tick(1'b1), .cs(sel_via), .we(we),
               .rs(ab[3:0]), .wdata(dout), .rdata(via_q), .irq(via_irq),
               .pa_in(8'd0), .pb_in(8'd0), .pa_out(), .pb_out(leds),
               .ddra(), .ddrb());

    always @(posedge clk) if (we && !sel_via) mem[ab] <= dout;

    function [63:0] sname(input [5:0] st);
        case (st)
            0: sname = "FETCH";   1: sname = "T1";      2: sname = "ZPI";
            3: sname = "ABSHI";   4: sname = "FIX";    10: sname = "RD";
           11: sname = "WR";     12: sname = "RMWRD";  13: sname = "RMWDW";
           14: sname = "RMWWR";  15: sname = "BRT";    16: sname = "BRF";
           17: sname = "PUSH";   18: sname = "PLINC";  19: sname = "PLRD";
           28: sname = "RTIINC"; 29: sname = "RTIP";   30: sname = "RTIL";
           31: sname = "RTIH";   32: sname = "INTH";   33: sname = "INTL";
           34: sname = "INTP";   35: sname = "VECL";   36: sname = "VECH";
           default: sname = "other";
        endcase
    endfunction

    integer cyc = 0, max = 20000, from = -1, to = -1, nmi_at = -1, i;
    integer last_irq = 0;
    reg [15:0] last = 16'hFFFF;
    reg [1023:0] prog;
    wire [15:0] v_irq = {mem[16'hFFFF], mem[16'hFFFE]};
    wire [15:0] v_nmi = {mem[16'hFFFB], mem[16'hFFFA]};
    initial begin
        if (!$value$plusargs("prog=%s", prog)) begin
            $display("usage: vvp ch17_irq.vvp +prog=file.hex [options]");
            $finish;
        end
        $readmemh(prog, mem);
        if ($value$plusargs("max=%d", max)) ;
        if ($value$plusargs("from=%d", from)) ;
        if ($value$plusargs("to=%d", to)) ;
        if ($value$plusargs("nmi=%d", nmi_at)) ;
        repeat (2) @(posedge clk);
        #1 rst = 0;
    end

    always @(negedge clk) if (!rst) begin
        cyc = cyc + 1;
        nmi_n = (cyc == nmi_at) ? 1'b0 : 1'b1;
        if (sync && ab == v_irq) begin
            $display("cycle %5d: IRQ handler entered (+%0d), LEDs %02x",
                     cyc, cyc - last_irq, leds);
            last_irq = cyc;
        end
        if (sync && ab == v_nmi)
            $display("cycle %5d: NMI handler entered", cyc);
        if (cyc >= from && cyc <= to)
            $display("%5d %-6s %s %04x %s %02x  s=%02x irq=%b nmi=%b",
                     cyc, sname(u_cpu.state), sync ? "*" : " ", ab,
                     we ? "W" : "R", we ? dout : din, u_cpu.s,
                     !via_irq, nmi_n);
        if (sync) begin
            if (ab == last) begin
                $display("cycle %5d: stopped at $%04x, ticks=%0d spins=%0d",
                         cyc, ab, mem[16'h0080],
                         {mem[16'h0082], mem[16'h0081]});
                $finish(0);
            end
            last = ab;
        end
        if (cyc >= max) $finish(0);
    end
endmodule
