#!/usr/bin/env python3
"""make_rom.py - join BASIC ($C000-$E0FF) and the kernel ($E100-$FFFF) into rom.hex.
Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence."""
import sys
basic = open(sys.argv[1], "rb").read()      # 16 KB image from msasm, $C000-$FFFF
kernel = open(sys.argv[2], "rb").read()     # $E100-$FFFF from ld65
assert len(basic) == 0x4000 and len(kernel) == 0x1F00
assert all(b == 0xFF for b in basic[0x2100:]), "BASIC runs past $E0FF"
rom = basic[:0x2100] + kernel
open(sys.argv[3], "w").write("".join("%02x\n" % b for b in rom))
open(sys.argv[3].replace(".hex", ".bin"), "wb").write(rom)
print("rom: %d bytes, reset vector $%04X" % (len(rom), rom[0x3FFC] | rom[0x3FFD] << 8))
