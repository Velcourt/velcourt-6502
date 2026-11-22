// ch10_bus_tb.v - watch the CPU bus clock by clock, with the same
// two-clocks-per-cycle memory that soc.v uses for its block RAM.
//   iverilog -o ch10_bus_tb.vvp ch10_bus_tb.v ../../rtl/cpu6502.v \
//            ../../rtl/alu6502.v && vvp ch10_bus_tb.vvp
//   vvp ch10_bus_tb.vvp +fast     (ce held at 1: see what breaks)
`timescale 1ns/1ns
module ch10_bus_tb;
reg clk = 0, rst = 1, ce = 0;
reg fast = 0;
wire [15:0] ab;
wire [7:0]  dout;
wire        we, sync;
reg  [7:0]  mem [0:65535];
reg  [7:0]  q;                       // registered read, like block RAM

cpu6502 cpu (.clk(clk), .ce(ce), .rst(rst), .ab(ab), .dout(dout),
             .we(we), .din(q), .irq_n(1'b1), .nmi_n(1'b1), .sync(sync));

always #20 clk = ~clk;               // 25 MHz-ish; only the order matters

// clock enable exactly as in soc.v (or always 1 with +fast)
always @(posedge clk) ce <= rst ? 1'b0 : (fast ? 1'b1 : ~ce);

// memory exactly as soc.v's RAM: write on a ce clock, else latch a read
always @(posedge clk) begin
    if (we && ce) mem[ab] <= dout;
    else          q <= mem[ab];
end

function [47:0] name(input [5:0] s);
    case (s)
        0: name = "FETCH";  1: name = "T1";     3: name = "ABSHI";
        10: name = "RD";    11: name = "WR";    32: name = "INTH";
        33: name = "INTL";  34: name = "INTP";  35: name = "VECL";
        36: name = "VECH";  default: name = "other";
    endcase
endfunction

integer i, n = 0;
initial begin
    if ($test$plusargs("fast")) fast = 1;
    for (i = 0; i < 65536; i = i + 1) mem[i] = 8'hEA;      // NOP
    mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h02;           // reset -> $0200
    // $0200: LDA $1234 / STA $0300 / JMP $0206
    mem[16'h0200] = 8'hAD; mem[16'h0201] = 8'h34; mem[16'h0202] = 8'h12;
    mem[16'h0203] = 8'h8D; mem[16'h0204] = 8'h00; mem[16'h0205] = 8'h03;
    mem[16'h0206] = 8'h4C; mem[16'h0207] = 8'h06; mem[16'h0208] = 8'h02;
    mem[16'h1234] = 8'h5A;
    repeat (4) @(posedge clk);
    rst = 0;
    $display("clock ce state  ab   din we dout sync");
    repeat (fast ? 24 : 44) begin
        @(negedge clk);                // middle of the clock: values settled
        $display("%5d  %b  %-5s %h  %h  %b  %h   %b", n, ce,
                 name(cpu.state), ab, q, we, dout, sync);
        n = n + 1;
    end
    $display("A = %h, memory $0300 = %h", cpu.a, mem[16'h0300]);
    $finish;
end
endmodule
