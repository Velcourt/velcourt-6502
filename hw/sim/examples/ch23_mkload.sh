#!/bin/sh
# ch23_mkload.sh NAME - assemble sw/examples/NAME.s for $0600, turn it
# into Intel HEX and print the simulator script lines that type the
# records into the monitor's L command.
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
# Run from hw/. Files go next to the source: NAME.o, NAME.bin, NAME.hex
set -e
cd sw/examples
ca65 -o $1.o -l $1.lst $1.s
ld65 -C ch09_ram.cfg -o $1.bin $1.o
cd ../..
python3 -I tools/bin2ihex.py sw/examples/$1.bin 0x0600 sw/examples/$1.hex >&2
sed 's/^/send /; s/$/\\r/' sw/examples/$1.hex
