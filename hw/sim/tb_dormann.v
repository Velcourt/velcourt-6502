// tb_dormann.v - runs Klaus Dormann's 6502 functional test on cpu6502.
// The test traps in a "JMP *" loop: at $3469 on success, anywhere else on error.
`timescale 1ns/1ps
module tb_dormann;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [7:0] mem [0:65535];
    wire [15:0] ab; wire [7:0] dout; wire we, sync;
    wire [7:0] din = mem[ab];               // memory answers within the cycle

    cpu6502 u_cpu (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout),
                   .we(we), .din(din), .irq_n(1'b1), .nmi_n(1'b1), .sync(sync));

    always @(posedge clk) if (we) mem[ab] <= dout;

    reg [15:0] last_pc = 16'hFFFF;
    integer cycles = 0, same = 0;
    initial begin
        $readmemh("dormann_functional.hex", mem);
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h04;   // reset to $0400
        repeat (3) @(posedge clk);
        rst = 0;
    end

    always @(posedge clk) if (!rst) begin
        cycles = cycles + 1;
        if (sync) begin
            if (ab == last_pc) same = same + 1; else same = 0;
            last_pc = ab;
            if (same == 3) begin
                if (ab == 16'h3469) $display("PASS: functional test finished at $%04x after %0d cycles", ab, cycles);
                else                $display("FAIL: trapped at $%04x after %0d cycles (test number in $0200 = %02x)", ab, cycles, mem[16'h0200]);
                $finish;
            end
        end
        if (cycles > 200_000_000) begin $display("TIMEOUT at $%04x", ab); $finish; end
    end
endmodule
