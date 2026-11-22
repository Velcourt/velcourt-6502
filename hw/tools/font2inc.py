# font2inc.py - font.txt -> font.inc (ca65 data) and a preview PNG
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import write_png
src, inc, png = sys.argv[1:4]
glyphs = {}
cur = None
for line in open(src):
    line = line.rstrip("\n")
    if line.startswith("//") or not line.strip(): continue
    if line.startswith("="):
        cur = int(line[1:], 16); glyphs[cur] = []
    else:
        assert len(line) == 8, (hex(cur), line)
        glyphs[cur].append(line)
assert sorted(glyphs) == list(range(0x20, 0x7f)), "need 0x20..0x7E"
with open(inc, "w") as f:
    f.write("; font.inc - generated from font.txt by font2inc.py. 8 bytes per glyph,\n")
    f.write("; top row first, bit 7 = leftmost pixel. Characters $20-$7E.\n")
    for c in range(0x20, 0x7f):
        rows = glyphs[c]; assert len(rows) == 8, hex(c)
        bs = [int(r.replace("#", "1").replace(".", "0"), 2) for r in rows]
        ch = chr(c) if chr(c) not in "\\'\"" else " "
        f.write("        .byte " + ",".join("$%02X" % b for b in bs) + f"   ; ${c:02X} {ch}\n")
# preview: 16 glyphs per row, 6 rows, scaled x4, with grid gaps
S, G = 4, 2
W = 16 * (8 * S + G) + G; H = 6 * (8 * S + G) + G
img = [bytearray(b"\xe8\xe8\xe8" * W) for _ in range(H)]
for i, c in enumerate(range(0x20, 0x80)):
    if c == 0x7f: break
    gx, gy = i % 16, i // 16
    for y, r in enumerate(glyphs[c]):
        for x, p in enumerate(r):
            col = b"\x10\x10\x10" if p == "#" else b"\xff\xff\xff"
            for dy in range(S):
                row = img[G + gy * (8 * S + G) + y * S + dy]
                for dx in range(S):
                    px = G + gx * (8 * S + G) + x * S + dx
                    row[px*3:px*3+3] = col
write_png(png, W, H, img)
print("ok", len(glyphs), "glyphs")
