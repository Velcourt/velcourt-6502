// ch16_uart_rmw_tb.v - cpu6502 plus uart.v: shows what a read-modify-write
// instruction does to an I/O register.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//   (from hw/sim)
//   ca65 -o out/ch16_uart_rmw.o examples/ch16_uart_rmw.s
//   ld65 -C examples/ch14_trace.cfg -o out/ch16_uart_rmw.bin \
//       out/ch16_uart_rmw.o
//   od -An -tx1 -v out/ch16_uart_rmw.bin > out/ch16_uart_rmw.hex
//   iverilog -o out/ch16_uart_rmw.vvp examples/ch16_uart_rmw_tb.v \
//       ../rtl/cpu6502.v ../rtl/alu6502.v ../rtl/uart.v
//   vvp -n out/ch16_uart_rmw.vvp
`timescale 1ns/1ps
module ch16_uart_rmw_tb;
    localparam DIV = 8;                      // 8 clocks per bit: a fast UART
    reg clk = 0, cpu_rst = 1, uart_rst = 1, rx = 1;
    always #5 clk = ~clk;

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout, uart_q; wire we, sync, tx, irq;
    wire sel_uart = (ab[15:1] == 15'h5F80);  // $BF00 and $BF01
    wire [7:0] din = sel_uart ? uart_q : mem[ab];

    cpu6502 u_cpu (.clk(clk), .ce(1'b1), .rst(cpu_rst), .ab(ab), .dout(dout),
                   .we(we), .din(din), .irq_n(1'b1), .nmi_n(1'b1),
                   .sync(sync));
    // every clock is a CPU cycle here, so cs can simply follow the address
    uart #(.DIV(DIV)) u_uart (.clk(clk), .rst(uart_rst), .cs(sel_uart),
        .we(we), .a0(ab[0]), .wdata(dout), .rdata(uart_q), .irq(irq),
        .rx(rx), .tx(tx));

    always @(posedge clk) if (we && !sel_uart) mem[ab] <= dout;

    // log every CPU cycle that touches $BF00
    integer cyc = 0;
    always @(negedge clk) if (!cpu_rst) begin
        cyc = cyc + 1;
        if (ab == 16'hBF00)
            $display("cycle %0d: %s $BF00 %s $%02x", cyc,
                     we ? "write" : "read ", we ? "<-" : "->",
                     we ? dout : din);
    end

    // send one byte into the UART's receive pin, 8N1
    task send(input [7:0] b);
        integer k;
        begin
            rx = 0; repeat (DIV) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rx = b[k]; repeat (DIV) @(posedge clk);
            end
            rx = 1; repeat (2 * DIV) @(posedge clk);
        end
    endtask

    // watch the transmit pin and print each byte that goes out
    reg [7:0] got;
    integer j;
    always @(negedge tx) if (!uart_rst) begin
        repeat (DIV / 2) @(posedge clk);         // middle of the start bit
        for (j = 0; j < 8; j = j + 1) begin
            repeat (DIV) @(posedge clk);
            got[j] = tx;
        end
        $display("the UART transmitted $%02x", got);
    end

    integer i;
    reg [15:0] last = 16'hFFFF;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        $readmemh("out/ch16_uart_rmw.hex", mem, 0, 16'h3FFF);
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h06;
        repeat (2) @(posedge clk);
        uart_rst = 0;
        send("A"); send("B");                     // two bytes wait in the FIFO
        $display("FIFO holds %0d bytes before the CPU starts", u_uart.count);
        cpu_rst = 0;
    end

    always @(posedge clk) if (!cpu_rst && sync) begin
        if (ab == last) begin                     // reached "done: jmp done"
            $display("afterwards: status $%02x, next byte $%02x",
                     mem[16'h0010], mem[16'h0011]);
            $finish(0);
        end
        last = ab;
    end
endmodule
