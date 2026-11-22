#!/bin/sh
# ch18_trace.sh [cpu.v] - build ch18_trace.cpp against a CPU source (by
# default ../rtl/cpu6502.v) and run Klaus Dormann's functional test on it.
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
# Run from hw/sim. The model is built in out/ch18_obj.
set -e
cd "$(dirname "$0")/.."
cpu=${1:-../rtl/cpu6502.v}
verilator --cc --exe --build -O3 -Wno-fatal -Wno-WIDTH --public-flat-rw \
    --top-module cpu6502 "$cpu" ../rtl/alu6502.v examples/ch18_trace.cpp \
    -o ch18_trace -Mdir out/ch18_obj > out/ch18_build.log
./out/ch18_obj/ch18_trace \
    ../../thirdparty/dormann/bin_files/6502_functional_test.bin 3469
