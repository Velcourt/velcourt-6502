#!/usr/bin/env python3
"""ch05_vcdtable.py - print a VCD file as a table, one row per clock cycle.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

    python3 -I examples/ch05_vcdtable.py out/ch05_cpu.vcd clk sync ab din we

Each row samples the signals at a falling clock edge, in the middle of
the cycle, when everything clocked by the rising edge has settled.
"""
import sys


def read_vcd(path):
    """Return ({name: id}, {name: width}, [(time, id, value), ...])."""
    ids, widths, changes = {}, {}, []
    time = 0
    with open(path) as f:
        tokens = f.read().split()
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "$var":                      # $var wire 8 ! din [7:0] $end
            width, code, name = int(tokens[i + 2]), tokens[i + 3], tokens[i + 4]
            ids[name], widths[name] = code, width
            while tokens[i] != "$end":
                i += 1
        elif t.startswith("#"):
            time = int(t[1:])
        elif t[0] in "01xz" and len(t) > 1 and not t.startswith("$"):
            changes.append((time, t[1:], t[0]))
        elif t[0] in "bB":
            changes.append((time, tokens[i + 1], t[1:]))
            i += 1
        i += 1
    return ids, widths, changes


def table(path, clock, names):
    ids, widths, changes = read_vcd(path)
    now = {}
    rows = []
    clk_id = ids[clock]
    for time, code, value in changes:
        if code == clk_id and value == "0" and now.get(clk_id) == "1":
            rows.append((time, [now.get(ids[n], "x") for n in names]))
        now[code] = value
    return rows, widths


def show(value, width):
    if any(c in value for c in "xz"):
        return "x" * ((width + 3) // 4)
    return format(int(value, 2), "0%dX" % ((width + 3) // 4))


if __name__ == "__main__":
    path, clock, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    rows, widths = table(path, clock, names)
    print("cyc   time(ns)  " + "  ".join("%5s" % n for n in names))
    for k, (time, values) in enumerate(rows):
        cells = [show(v, widths[n]) for v, n in zip(values, names)]
        print("%4d  %8d  " % (k, time // 1000) +
              "  ".join("%5s" % c for c in cells))
