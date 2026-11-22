#!/usr/bin/env python3
"""bin2ihex.py IN.bin LOAD_ADDRESS OUT.hex - write a binary as Intel HEX records.
Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

Each record is  :LLAAAATT<data>CC  where LL = byte count, AAAA = address,
TT = 00 for data or 01 for end of file, and CC makes all bytes sum to zero."""
import sys
data = open(sys.argv[1], "rb").read()
addr = int(sys.argv[2], 0)
lines = []
for i in range(0, len(data), 16):
    chunk = data[i:i + 16]
    a = addr + i
    rec = [len(chunk), a >> 8, a & 0xFF, 0x00] + list(chunk)
    rec.append((-sum(rec)) & 0xFF)
    lines.append(":" + "".join("%02X" % b for b in rec))
lines.append(":00000001FF")
open(sys.argv[3], "w").write("\n".join(lines) + "\n")
print("%d bytes at $%04X -> %d records" % (len(data), addr, len(lines)))
