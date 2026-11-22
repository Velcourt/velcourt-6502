#!/usr/bin/env python3
"""basic_syms.py - pick out the BASIC addresses the kernel needs."""
import sys
want = "INIT TXTTAB VARTAB INDEX MEMSIZ READY".split()
sym = {l.split()[0]: l.split("=")[1].strip() for l in open(sys.argv[1])}
with open(sys.argv[2], "w") as f:
    f.write("; basic_syms.inc - addresses inside BASIC that the kernel needs (from msasm)\n")
    for w in want:
        f.write("BASIC_%-8s= %s\n" % (w, sym[w]))
