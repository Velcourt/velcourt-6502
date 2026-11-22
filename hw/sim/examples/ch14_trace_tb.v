// ch14_trace_tb.v - run a small program on cpu6502 and print every bus cycle.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
//   sh examples/ch14_trace.sh ch14_first        (from hw/sim)
//
// The program image (+prog=file.hex, one byte per word, loaded at $0000)
// starts at $0600; the reset vector is set to $0600 here. The run stops
// when the CPU fetches the same opcode twice in a row (a "JMP *" loop),
// or after +max=N cycles. With +sum=1 it prints one line per instruction
// (address, opcode, cycles) instead of one line per cycle.
`timescale 1ns/1ps
module ch14_trace_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout; wire we, sync;
    wire [7:0] din = mem[ab];               // memory answers within the cycle

    cpu6502 u_cpu (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout),
                   .we(we), .din(din), .irq_n(1'b1), .nmi_n(1'b1),
                   .sync(sync));

    always @(posedge clk) if (we) mem[ab] <= dout;

    // state number -> name, in the order of the localparams in cpu6502.v
    function [63:0] sname(input [5:0] st);
        case (st)
            0: sname = "FETCH";   1: sname = "T1";      2: sname = "ZPI";
            3: sname = "ABSHI";   4: sname = "FIX";     5: sname = "INDX0";
            6: sname = "INDXL";   7: sname = "INDXH";   8: sname = "INDYL";
            9: sname = "INDYH";  10: sname = "RD";     11: sname = "WR";
           12: sname = "RMWRD";  13: sname = "RMWDW";  14: sname = "RMWWR";
           15: sname = "BRT";    16: sname = "BRF";    17: sname = "PUSH";
           18: sname = "PLINC";  19: sname = "PLRD";   20: sname = "JSRD";
           21: sname = "JSRH";   22: sname = "JSRL";   23: sname = "JSRA";
           24: sname = "RTSINC"; 25: sname = "RTSL";   26: sname = "RTSH";
           27: sname = "RTSPC";  28: sname = "RTIINC"; 29: sname = "RTIP";
           30: sname = "RTIL";   31: sname = "RTIH";   32: sname = "INTH";
           33: sname = "INTL";   34: sname = "INTP";   35: sname = "VECL";
           36: sname = "VECH";   37: sname = "INDL";   38: sname = "INDH";
           default: sname = "?";
        endcase
    endfunction

    // one flag as a letter: capital = 1, small = 0, ? = not yet known
    function [7:0] fl(input b, input [7:0] up);
        fl = (b === 1'b1) ? up : (b === 1'b0) ? up + 8'd32 : "?";
    endfunction

    integer cyc = 0, max = 200, sum = 0, n = 0, i;
    reg [15:0] last = 16'hFFFF, iaddr;
    reg [7:0]  iop;
    reg [1023:0] prog;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        if (!$value$plusargs("prog=%s", prog)) begin
            $display("usage: vvp ch14_trace.vvp +prog=F.hex [+max=N] [+sum=1]");
            $finish;
        end
        $readmemh(prog, mem, 0, 16'h3FFF);     // the image covers 16 KB
        if ($value$plusargs("max=%d", max)) ;
        if ($value$plusargs("sum=%d", sum)) ;
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h06;   // reset to $0600
        if (sum) $display("addr  op  cycles");
        else $display(" cyc state    ab   rw data   pc   a  x  y  s  flags");
        repeat (2) @(posedge clk);
        #1 rst = 0;
    end

    // print in the middle of each cycle, when ab, we and din have settled
    always @(negedge clk) if (!rst) begin
        cyc = cyc + 1;
        if (sync) begin
            if (sum && n > 0) $display("%04x  %02x  %0d", iaddr, iop, n);
            if (ab == last) $finish(0);              // JMP * : stop here
            last = ab; iaddr = ab; iop = din; n = 0;
        end
        n = n + 1;
        if (!sum)
            $display({"%4d %-7s%s %04x  %s  %02x   %04x  ",
                      "%02x %02x %02x %02x %s%s%s%s%s%s"},
                cyc, sname(u_cpu.state), sync ? "*" : " ", ab,
                we ? "W" : "R", we ? dout : din, u_cpu.pc,
                u_cpu.a, u_cpu.x, u_cpu.y, u_cpu.s,
                fl(u_cpu.fn, "N"), fl(u_cpu.fv, "V"), fl(u_cpu.fd, "D"),
                fl(u_cpu.fi, "I"), fl(u_cpu.fz, "Z"), fl(u_cpu.fc, "C"));
        if (cyc >= max) $finish(0);
    end
endmodule
