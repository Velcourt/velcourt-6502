#!/usr/bin/env python3
"""ch11_alu_check.py - compare alu6502 with a Python model of the 6502.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

ch11_alu_tb.v writes six bytes per test (A X Y S M P after the operation)
in a fixed order. This script walks through the same order, works out what
a 6502 would do, and counts the differences.

    python3 -I examples/ch11_alu_check.py out/ch11_alu.bin   (from hw/sim)
"""
import sys

OPS = ("NOP LDA LDX LDY STA STX STY ADC SBC AND ORA EOR CMP CPX CPY BIT "
       "ASL LSR ROL ROR INC DEC INX INY DEX DEY TAX TAY TXA TYA TSX TXS "
       "CLC SEC CLI SEI CLV CLD SED").split()


def signed(v):
    """A byte read as a two's complement number, -128 to 127."""
    return v - 256 if v & 0x80 else v


def nz(r, v):
    """Set N and Z from an 8-bit value."""
    r["n"] = v >> 7
    r["z"] = int(v == 0)


def model(op, acc, a, x, y, s, m, n, v, d, i, z, c):
    """What the 6502 does, written from the programmer's manual,
    with NMOS decimal mode as described by Bruce Clark."""
    r = dict(a=a, x=x, y=y, s=s, m=m, n=n, v=v, d=d, i=i, z=z, c=c)
    if op in ("LDA", "LDX", "LDY"):
        r[op[2].lower()] = m
        nz(r, m)
    elif op in ("AND", "ORA", "EOR"):
        r["a"] = {"AND": a & m, "ORA": a | m, "EOR": a ^ m}[op]
        nz(r, r["a"])
    elif op in ("ADC", "SBC"):
        b = m if op == "ADC" else m ^ 0xFF        # SBC adds the complement
        total = a + b + c                          # the binary sum
        result = total & 0xFF
        r["c"] = int(total > 0xFF)
        sv = signed(a) + signed(b) + c             # the same sum, signed
        r["v"] = int(sv < -128 or sv > 127)
        nz(r, result)
        r["a"] = result
        if d and op == "ADC":
            lo = (a & 0x0F) + (m & 0x0F) + c
            if lo >= 0x0A:
                lo = ((lo + 0x06) & 0x0F) + 0x10
            hi = (a & 0xF0) + (m & 0xF0) + lo
            shi = signed(a & 0xF0) + signed(m & 0xF0) + lo
            r["n"] = (shi >> 7) & 1                # N and V: before the
            r["v"] = int(shi < -128 or shi > 127)  # high-digit correction
            if hi >= 0xA0:
                hi += 0x60
            r["a"] = hi & 0xFF
            r["c"] = int(hi >= 0x100)
            r["z"] = int(result == 0)              # Z: from the binary sum
        elif d and op == "SBC":                    # flags stay binary
            lo = (a & 0x0F) - (m & 0x0F) + c - 1
            if lo < 0:
                lo = ((lo - 0x06) & 0x0F) - 0x10
            hi = (a & 0xF0) - (m & 0xF0) + lo
            if hi < 0:
                hi -= 0x60
            r["a"] = hi & 0xFF
    elif op in ("CMP", "CPX", "CPY"):
        reg = {"CMP": a, "CPX": x, "CPY": y}[op]
        r["c"] = int(reg >= m)
        nz(r, (reg - m) & 0xFF)
    elif op == "BIT":
        r["z"] = int(a & m == 0)
        r["n"] = m >> 7
        r["v"] = (m >> 6) & 1
    elif op in ("ASL", "LSR", "ROL", "ROR"):
        val = a if acc else m
        if op in ("ASL", "ROL"):
            out = ((val << 1) | (c if op == "ROL" else 0)) & 0xFF
            r["c"] = val >> 7
        else:
            out = (val >> 1) | ((c << 7) if op == "ROR" else 0)
            r["c"] = val & 1
        r["a" if acc else "m"] = out
        nz(r, out)
    elif op in ("INC", "DEC"):
        r["m"] = (m + (1 if op == "INC" else -1)) & 0xFF
        nz(r, r["m"])
    elif op in ("INX", "INY", "DEX", "DEY"):
        reg = op[2].lower()
        r[reg] = (r[reg] + (1 if op[0] == "I" else -1)) & 0xFF
        nz(r, r[reg])
    elif op in ("TAX", "TAY", "TXA", "TYA", "TSX", "TXS"):
        src, dst = op[1].lower(), op[2].lower()
        r[dst] = r[src]
        if op != "TXS":                           # TXS leaves N and Z alone
            nz(r, r[dst])
    elif op in ("CLC", "SEC", "CLI", "SEI", "CLV", "CLD", "SED"):
        r[op[2].lower()] = int(op[0] == "S")
    # NOP, STA, STX, STY: the ALU changes nothing
    p = (r["n"] << 7 | r["v"] << 6 | 0x20 | r["d"] << 3 | r["i"] << 2
         | r["z"] << 1 | r["c"])
    return bytes((r["a"], r["x"], r["y"], r["s"], r["m"], p))


def main(path):
    data = open(path, "rb").read()
    pos = 0
    bad = {}
    tests = {}
    for code, op in enumerate(OPS):
        for acc in (0, 1):
            if acc and op not in ("ASL", "LSR", "ROL", "ROR"):
                continue
            for d in (0, 1):
                for c in (0, 1):
                    for a in range(256):
                        x, y, s = a ^ 0x5A, a ^ 0xA5, (a + 0x33) & 0xFF
                        for m in range(256):
                            fl = (a & 0x0F) ^ (m >> 4)
                            n, v = fl >> 3, (fl >> 2) & 1
                            i, z = (fl >> 1) & 1, fl & 1
                            want = model(op, acc, a, x, y, s, m,
                                         n, v, d, i, z, c)
                            got = data[pos:pos + 6]
                            pos += 6
                            tests[op] = tests.get(op, 0) + 1
                            if got != want:
                                bad[op] = bad.get(op, 0) + 1
                                if bad[op] <= 3:
                                    print(f"{op} acc={acc} D={d} C={c} "
                                          f"A=${a:02X} M=${m:02X}: "
                                          f"got {got.hex(' ')}, "
                                          f"want {want.hex(' ')}")
    assert pos == len(data), "file length does not match the test order"
    for op in OPS:
        print(f"{op}  {tests[op]:7d} tests  {bad.get(op, 0):7d} wrong")
    total = sum(tests.values())
    print(f"total {total} tests, {sum(bad.values())} wrong")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "out/ch11_alu.bin"))
