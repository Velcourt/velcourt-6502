#!/bin/sh
# ch14_trace.sh NAME [+sum=1] [+max=N] - assemble examples/NAME.s and run it
# on cpu6502 under Icarus Verilog, printing one line per bus cycle.
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
# Run from hw/sim. Files go to out/NAME.*
set -e
cd "$(dirname "$0")/.."
name=$1; shift
ca65 -o out/$name.o -l out/$name.lst examples/$name.s
ld65 -C examples/ch14_trace.cfg -o out/$name.bin out/$name.o
od -An -tx1 -v out/$name.bin > out/$name.hex
iverilog -o out/ch14_trace.vvp examples/ch14_trace_tb.v \
    ../rtl/cpu6502.v ../rtl/alu6502.v
vvp -n out/ch14_trace.vvp +prog=out/$name.hex "$@"
