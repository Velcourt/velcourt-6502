// ch03_decode_tb.v - check the address decoder of soc.v for all 65,536
// addresses against the memory map, by forcing the CPU's address bus.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
// Run from hw/sim:
//   iverilog -o out/ch03_decode.vvp examples/ch03_decode_tb.v ../rtl/soc.v \
//     ../rtl/cpu6502.v ../rtl/alu6502.v ../rtl/video.v \
//     ../rtl/uart.v ../rtl/ps2_kbd.v ../rtl/spi_sd.v \
//     ../rtl/via.v ../rtl/sound.v
//   vvp out/ch03_decode.vvp

module tb;
reg clk = 0, rst = 1;              // the clock never runs: we test wires only
soc #(.ROM_FILE("../build/rom.hex")) dut (
    .clk(clk), .rst(rst), .uart_rx(1'b1), .ps2_clk(1'b1), .ps2_dat(1'b1),
    .sd_miso(1'b1), .button(1'b0)
);

integer addr, errors;
integer n_ram, n_fb, n_io, n_rom, n_none;
reg [3:0] want;                    // expected {rom, io, fb, ram}
initial begin
    errors = 0; n_ram = 0; n_fb = 0; n_io = 0; n_rom = 0; n_none = 0;
    for (addr = 0; addr < 65536; addr = addr + 1) begin
        force dut.ab = addr[15:0];
        #1;
        // the memory map, written the slow and obvious way
        if      (addr <= 16'h3FFF) want = 4'b0001;    // RAM
        else if (addr <= 16'hBCFF) want = 4'b0010;    // framebuffer
        else if (addr <= 16'hBEFF) want = 4'b0000;    // nothing
        else if (addr <= 16'hBFFF) want = 4'b0100;    // I/O page
        else                       want = 4'b1000;    // ROM
        if ({dut.sel_rom, dut.sel_io, dut.sel_fb, dut.sel_ram} !== want) begin
            errors = errors + 1;
            if (errors <= 5)
                $display("MISMATCH at $%h: rom io fb ram = %b, want %b",
                         addr[15:0], {dut.sel_rom, dut.sel_io, dut.sel_fb,
                         dut.sel_ram}, want);
        end
        // nobody answers: the CPU must read $FF
        if (want == 4'b0000 && dut.cpu_din !== 8'hFF) begin
            errors = errors + 1;
            $display("MISMATCH at $%h: read %h, want ff", addr[15:0],
                     dut.cpu_din);
        end
        case (want)
            4'b0001: n_ram  = n_ram + 1;
            4'b0010: n_fb   = n_fb + 1;
            4'b0100: n_io   = n_io + 1;
            4'b1000: n_rom  = n_rom + 1;
            default: n_none = n_none + 1;
        endcase
    end
    $display("RAM %0d, framebuffer %0d, I/O %0d, ROM %0d, unused %0d",
             n_ram, n_fb, n_io, n_rom, n_none);
    $display("%0d addresses checked, %0d errors", addr, errors);
    $finish;
end
endmodule
