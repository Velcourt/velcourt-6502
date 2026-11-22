#!/usr/bin/env python3
"""ch05_fbaddr_model.py - a golden model for the framebuffer address in video.v.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

    python3 -I examples/ch05_fbaddr_model.py out/ch05_fbaddr.txt [lead]

Line n of the log is fb_addr in clock n after reset. The model works out
where the fetch counters should be in that clock, and from there which
byte the video needs, using plain multiplication and division.
"""
import sys

H_TOT, V_TOT = 800, 525
PIC_TOP, PIC_BOT = 40, 440
lead = int(sys.argv[2]) if len(sys.argv) > 2 else 4   # fetch runs 4 ahead

checked = errors = 0
with open(sys.argv[1]) as log:
    for n, line in enumerate(log):
        p = n + lead
        fx, fy = p % H_TOT, (p // H_TOT) % V_TOT
        if fx >= 640 or not PIC_TOP <= fy < PIC_BOT:
            continue                       # the video ignores this address
        want = (fy - PIC_TOP) // 2 * 160 + fx // 4
        got = int(line, 16)
        checked += 1
        if got != want:
            errors += 1
            if errors <= 3:
                print("clock %d (fx=%d, fy=%d): got %d, model says %d"
                      % (n, fx, fy, got, want))
print("%d addresses checked, %d wrong" % (checked, errors))
print("PASS" if errors == 0 else "FAIL")
sys.exit(1 if errors else 0)
