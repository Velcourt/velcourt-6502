// ch04_uart_rx_tb.v - drive the receiver of uart.v with serial frames:
// a good byte, a glitch, a byte with a broken stop bit, another good byte.
// Prints where the receiver samples, then reads the FIFO like the CPU does.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch04_uart_rx.vvp examples/ch04_uart_rx_tb.v ../rtl/uart.v
//   vvp out/ch04_uart_rx.vvp

module tb;
localparam DIV = 219;              // clocks per bit, as in soc.v
reg clk = 0, rst = 1, rx = 1;
reg cs = 0, we = 0, a0 = 0;
wire [7:0] rdata;
wire irq, tx;
uart #(.DIV(DIV)) dut (.clk(clk), .rst(rst), .cs(cs), .we(we), .a0(a0),
    .wdata(8'h00), .rdata(rdata), .irq(irq), .rx(rx), .tx(tx));

always #1 clk = ~clk;
time edge_at = 0;                  // when the line last fell

// report every moment the receiver looks at the line
reg trace = 0;
always @(posedge clk)
    if (dut.rx_active && dut.rx_cnt == 0 && trace)
        $display("  sample %0d at clock %0d after the edge: line = %b",
                 dut.rx_bits, ($time - edge_at) / 2, dut.rx_in);

// send one frame: start bit, 8 data bits LSB first, stop bit
task frame(input [7:0] data, input stop);
    integer i;
    begin
        edge_at = $time;
        rx = 0; repeat (DIV) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i]; repeat (DIV) @(posedge clk);
        end
        rx = stop; repeat (DIV) @(posedge clk);
        rx = 1;    repeat (DIV) @(posedge clk);   // line idle
    end
endtask

// one CPU read of register a, as a one-clock strobe
task cpu_read(input reg_a0, output [7:0] value);
    begin
        @(negedge clk) begin cs = 1; a0 = reg_a0; end
        @(posedge clk) value = rdata;   // latched at the edge, like the CPU
        @(negedge clk) cs = 0;
    end
endtask

reg [7:0] v;
initial begin
    repeat (4) @(posedge clk); rst = 0; repeat (10) @(posedge clk);
    $display("frame 1: $41, good stop bit");
    trace = 1; frame(8'h41, 1'b1); trace = 0;
    $display("glitch: line low for 40 clocks");
    trace = 1; edge_at = $time;
    rx = 0; repeat (40) @(posedge clk); rx = 1; repeat (3 * DIV) @(posedge clk);
    trace = 0;
    $display("frame 2: $55, stop bit 0 (framing error)");
    frame(8'h55, 1'b0);
    $display("frame 3: $0D, good stop bit");
    frame(8'h0D, 1'b1);
    cpu_read(1'b1, v); $display("status = %b", v[2:0]);
    while (v[0]) begin
        cpu_read(1'b0, v); $display("read $%h", v);
        cpu_read(1'b1, v);
    end
    $display("status = %b, FIFO empty", v[2:0]);
    $finish;
end
endmodule
