# Build Your Own 6502 Computer on an FPGA: companion code

The complete computer from the book by Adrian Velcourt: a 6502 CPU written in
Verilog, HDMI video, PS/2 and serial keyboards, SD card storage, sound, a
6522-style VIA, a kernel with a machine-code monitor, and Microsoft BASIC 1.1,
for the Sipeed Tang Nano 20K FPGA board.

Everything here was verified in simulation (Verilator and Icarus Verilog) and
synthesised, placed and routed for the Tang Nano 20K with its timing met.

## Folders

- `hw/rtl/`    the Verilog: CPU, ALU, video, HDMI, UART, PS/2, SPI, VIA, sound, system, board top
- `hw/sw/`     the kernel (ca65 assembly), its linker config and the font
- `hw/tools/`  Python tools: the MACRO-10 assembler for Microsoft's BASIC, the BASIC patcher, ROM builder, converters
- `hw/sim/`    simulator harnesses, test benches, scripts and the book's examples
- `hw/build/`  the pin constraints for the Tang Nano 20K; build outputs appear here
- `thirdparty/` Microsoft's BASIC source and Klaus Dormann's 6502 tests, with their licences

## Quick start (see Chapter 2 of the book for details on Windows, macOS and Linux)

1. Install the OSS CAD Suite (YosysHQ) and build cc65, so that `tools/oss-cad-suite/bin` and
   `tools/cc65/bin` sit next to `hw/`, or pass `TOOLS=/path/to/tools` to make.
2. In `hw/`:

        make rom          # Microsoft BASIC + kernel -> build/rom.hex
        make test-cpu     # Klaus Dormann's functional test and Bruce Clark's decimal test
        make sim          # the whole-computer simulator
        cd sim && ./obj_soc/sim_soc boot.script
        make bitstream    # build/top.fs for the Tang Nano 20K
        make flash        # openFPGALoader -b tangnano20k build/top.fs

## Licence

MIT for our code (see LICENSE). The files in `thirdparty/` keep their own licences.
