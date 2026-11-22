#!/bin/sh
# ch17_irq.sh [options] - assemble sw/examples/ch17_ticks.s and run it on
# the interrupt test bench examples/ch17_irq_tb.v under Icarus Verilog.
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
# Run from hw/sim. Files go to out/ch17_ticks.*
set -e
cd "$(dirname "$0")/.."
ca65 ${NOACK:+-D NOACK=1} -o out/ch17_ticks.o -l out/ch17_ticks.lst ../sw/examples/ch17_ticks.s
ld65 -C ../sw/examples/ch17_ticks.cfg -o out/ch17_ticks.bin out/ch17_ticks.o
od -An -tx1 -v out/ch17_ticks.bin > out/ch17_ticks.hex
iverilog -o out/ch17_irq.vvp examples/ch17_irq_tb.v \
    ../rtl/cpu6502.v ../rtl/alu6502.v ../rtl/via.v
vvp -n out/ch17_irq.vvp +prog=out/ch17_ticks.hex "$@"
