#!/usr/bin/env python3
"""ppm2png.py IN.ppm OUT.png [crop: x y w h] - convert a simulator frame."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import write_png
d = open(sys.argv[1], "rb").read()
parts = d.split(b"\n", 3); w, h = map(int, parts[1].split()); px = parts[3]
x0, y0, cw, ch = (map(int, sys.argv[3:7]) if len(sys.argv) > 6 else (0, 0, w, h))
rows = [px[((y0 + y) * w + x0) * 3:((y0 + y) * w + x0 + cw) * 3] for y in range(ch)]
write_png(sys.argv[2], cw, ch, rows)
