#!/usr/bin/env python3
"""sendhex.py PORT FILE.hex - send an Intel HEX file to the monitor's L command.
Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

Needs pyserial (pip install pyserial). PORT is for example
  /dev/tty.usbserial-XXXX (macOS), /dev/ttyUSB1 (Linux), COM4 (Windows).
Type L at the monitor's * prompt first, then run this."""
import sys, time
import serial                                   # pyserial
port, path = sys.argv[1], sys.argv[2]
with serial.Serial(port, 115200, timeout=0.1) as s:
    for line in open(path):
        line = line.strip()
        if not line.startswith(":"):
            continue
        s.write((line + "\r").encode("ascii"))
        time.sleep(0.02)                        # let the 6502 keep up
        reply = s.read(64).decode("ascii", "replace")
        sys.stdout.write(reply)
        sys.stdout.flush()
print("\nsent", path)
