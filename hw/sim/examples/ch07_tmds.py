#!/usr/bin/env python3
"""ch07_tmds.py - a Python model of the DVI 1.0 TMDS encoder, for Chapter 7.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

Encodes a byte step by step the way rtl/tmds_encoder.v does, prints each
step, and decodes the result again. Usage:
    python3 -I ch07_tmds.py            the worked example (brick red, x4)
    python3 -I ch07_tmds.py A8 3A 32   any bytes, in hex, as one lane
    python3 -I ch07_tmds.py --stats    level changes before and after stage 1
"""
import sys

def bits(v, n):                      # most significant bit first, like Verilog
    return format(v, "0%db" % n)

def stage1(d):
    n1d = bin(d).count("1")
    use_xnor = n1d > 4 or (n1d == 4 and (d & 1) == 0)
    q = d & 1
    for i in range(1, 8):
        prev = (q >> (i - 1)) & 1
        di = (d >> i) & 1
        b = (prev ^ di) ^ (1 if use_xnor else 0)
        q |= b << i
    q |= (0 if use_xnor else 1) << 8
    return q, n1d, use_xnor

def stage2(q_m, cnt):
    low = q_m & 0xFF
    q8 = (q_m >> 8) & 1
    n1 = bin(low).count("1")
    n0 = 8 - n1
    if cnt == 0 or n1 == n0:
        rule = "A (cnt=0 or n1=n0)"
        data = low if q8 else (~low & 0xFF)
        q = ((1 - q8) << 9) | (q8 << 8) | data
        cnt = cnt + (n1 - n0 if q8 else n0 - n1)
    elif (cnt > 0 and n1 > n0) or (cnt < 0 and n0 > n1):
        rule = "B (invert)"
        q = (1 << 9) | (q8 << 8) | (~low & 0xFF)
        cnt = cnt + 2 * q8 + n0 - n1
    else:
        rule = "C (send as is)"
        q = (q8 << 8) | low
        cnt = cnt - 2 * (1 - q8) + n1 - n0
    return q, cnt, n1, n0, rule

def decode(q):
    d = q & 0xFF
    if q & 0x200:
        d ^= 0xFF
    out = d & 1
    for i in range(1, 8):
        b = ((d >> i) ^ (d >> (i - 1))) & 1
        if not (q & 0x100):
            b ^= 1
        out |= b << i
    return out

def disparity(q):                    # ones minus zeros of a 10-bit symbol
    return 2 * bin(q).count("1") - 10

def changes(v):                      # level changes inside 8 bits
    s = bits(v, 8)
    return sum(1 for a, b in zip(s, s[1:]) if a != b)

def stats():
    raw, enc = {}, {}
    for d in range(256):
        a, b = changes(d), changes(stage1(d)[0] & 0xFF)
        raw[a] = raw.get(a, 0) + 1
        enc[b] = enc.get(b, 0) + 1
    print("raw bytes", sorted(raw.items()))
    print("q_m[7:0] ", sorted(enc.items()))

if __name__ == "__main__" and sys.argv[1:] == ["--stats"]:
    stats()
elif __name__ == "__main__":
    data = [int(a, 16) for a in sys.argv[1:]] or [0x3A] * 4
    cnt = 0
    for d in data:
        q_m, n1d, use_xnor = stage1(d)
        q, new, n1, n0, rule = stage2(q_m, cnt)
        print("d = $%02X = %s  ones=%d  -> %s" % (d, bits(d, 8), n1d,
              "XNOR" if use_xnor else "XOR"))
        print("   q_m = %s  (bit 8 = %d)  n1=%d n0=%d" % (bits(q_m, 9),
              q_m >> 8, n1, n0))
        print("   cnt before %+d, rule %s" % (cnt, rule))
        print("   q   = %s  symbol disparity %+d, cnt after %+d" % (bits(q, 10),
              disparity(q), new))
        ok = "ok" if decode(q) == d else "WRONG"
        print("   decoded back: $%02X %s" % (decode(q), ok))
        cnt = new
