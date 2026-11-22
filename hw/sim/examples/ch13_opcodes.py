#!/usr/bin/env python3
"""ch13_opcodes.py - check what cpu6502's decoder says about each opcode
against the 151 documented NMOS 6502 opcodes, then write the matrix.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.

    python3 -I examples/ch13_opcodes.py out/ch13_decode.txt \
        out/ch13_matrix.txt        (from hw/sim)
"""
import sys

# The documented instruction set, as the programming manual lists it:
# mnemonic, then opcode:mode:bytes:cycles for each addressing mode.
# Cycles are the base count (no page crossing, branch not taken).
DOCUMENTED = """
ADC 69:imm:2:2 65:zp:2:3 75:zpx:2:4 6D:abs:3:4
ADC 7D:absx:3:4 79:absy:3:4 61:indx:2:6 71:indy:2:5
AND 29:imm:2:2 25:zp:2:3 35:zpx:2:4 2D:abs:3:4
AND 3D:absx:3:4 39:absy:3:4 21:indx:2:6 31:indy:2:5
ASL 0A:acc:1:2 06:zp:2:5 16:zpx:2:6 0E:abs:3:6 1E:absx:3:7
BCC 90:rel:2:2
BCS B0:rel:2:2
BEQ F0:rel:2:2
BIT 24:zp:2:3 2C:abs:3:4
BMI 30:rel:2:2
BNE D0:rel:2:2
BPL 10:rel:2:2
BRK 00:imp:1:7
BVC 50:rel:2:2
BVS 70:rel:2:2
CLC 18:imp:1:2
CLD D8:imp:1:2
CLI 58:imp:1:2
CLV B8:imp:1:2
CMP C9:imm:2:2 C5:zp:2:3 D5:zpx:2:4 CD:abs:3:4
CMP DD:absx:3:4 D9:absy:3:4 C1:indx:2:6 D1:indy:2:5
CPX E0:imm:2:2 E4:zp:2:3 EC:abs:3:4
CPY C0:imm:2:2 C4:zp:2:3 CC:abs:3:4
DEC C6:zp:2:5 D6:zpx:2:6 CE:abs:3:6 DE:absx:3:7
DEX CA:imp:1:2
DEY 88:imp:1:2
EOR 49:imm:2:2 45:zp:2:3 55:zpx:2:4 4D:abs:3:4
EOR 5D:absx:3:4 59:absy:3:4 41:indx:2:6 51:indy:2:5
INC E6:zp:2:5 F6:zpx:2:6 EE:abs:3:6 FE:absx:3:7
INX E8:imp:1:2
INY C8:imp:1:2
JMP 4C:abs:3:3 6C:ind:3:5
JSR 20:abs:3:6
LDA A9:imm:2:2 A5:zp:2:3 B5:zpx:2:4 AD:abs:3:4
LDA BD:absx:3:4 B9:absy:3:4 A1:indx:2:6 B1:indy:2:5
LDX A2:imm:2:2 A6:zp:2:3 B6:zpy:2:4 AE:abs:3:4 BE:absy:3:4
LDY A0:imm:2:2 A4:zp:2:3 B4:zpx:2:4 AC:abs:3:4 BC:absx:3:4
LSR 4A:acc:1:2 46:zp:2:5 56:zpx:2:6 4E:abs:3:6 5E:absx:3:7
NOP EA:imp:1:2
ORA 09:imm:2:2 05:zp:2:3 15:zpx:2:4 0D:abs:3:4
ORA 1D:absx:3:4 19:absy:3:4 01:indx:2:6 11:indy:2:5
PHA 48:imp:1:3
PHP 08:imp:1:3
PLA 68:imp:1:4
PLP 28:imp:1:4
ROL 2A:acc:1:2 26:zp:2:5 36:zpx:2:6 2E:abs:3:6 3E:absx:3:7
ROR 6A:acc:1:2 66:zp:2:5 76:zpx:2:6 6E:abs:3:6 7E:absx:3:7
RTI 40:imp:1:6
RTS 60:imp:1:6
SBC E9:imm:2:2 E5:zp:2:3 F5:zpx:2:4 ED:abs:3:4
SBC FD:absx:3:4 F9:absy:3:4 E1:indx:2:6 F1:indy:2:5
SEC 38:imp:1:2
SED F8:imp:1:2
SEI 78:imp:1:2
STA 85:zp:2:3 95:zpx:2:4 8D:abs:3:4
STA 9D:absx:3:5 99:absy:3:5 81:indx:2:6 91:indy:2:6
STX 86:zp:2:3 96:zpy:2:4 8E:abs:3:4
STY 84:zp:2:3 94:zpx:2:4 8C:abs:3:4
TAX AA:imp:1:2
TAY A8:imp:1:2
TSX BA:imp:1:2
TXA 8A:imp:1:2
TXS 9A:imp:1:2
TYA 98:imp:1:2
"""

# Numbering used by cpu6502.v (localparams M_* and OP_*)
MODES = ["imp", "acc", "imm", "zp", "zpx", "zpy", "abs", "absx", "absy",
         "indx", "indy", "rel", "ctl"]
OPS = ("NOP LDA LDX LDY STA STX STY ADC SBC AND ORA EOR CMP CPX CPY BIT "
       "ASL LSR ROL ROR INC DEC INX INY DEX DEY TAX TAY TXA TYA TSX TXS "
       "CLC SEC CLI SEI CLV CLD SED PLA").split()
# Control opcodes are told apart by the state machine's case (ir)
CTL = {0x00: ("BRK", "imp"), 0x20: ("JSR", "abs"), 0x40: ("RTI", "imp"),
       0x60: ("RTS", "imp"), 0x08: ("PHP", "imp"), 0x28: ("PLP", "imp"),
       0x48: ("PHA", "imp"), 0x68: ("PLA", "imp"), 0x4C: ("JMP", "abs"),
       0x6C: ("JMP", "ind")}
# Branches: bits 7:6 pick the flag, bit 5 the value that takes the branch
BRANCH = {("N", 0): "BPL", ("N", 1): "BMI", ("V", 0): "BVC", ("V", 1): "BVS",
          ("C", 0): "BCC", ("C", 1): "BCS", ("Z", 0): "BNE", ("Z", 1): "BEQ"}
FLAGS_AT_TEST = {"N": 0, "V": 0, "C": 0, "Z": 1}   # after LDA #0, CLC, CLV
LENGTH = {"imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2,
          "abs": 3, "absx": 3, "absy": 3, "indx": 2, "indy": 2, "rel": 2}


def main(dump, matrix_out):
    ref = {}
    for line in DOCUMENTED.strip().splitlines():
        name, *entries = line.split()
        for e in entries:
            code, mode, nbytes, cyc = e.split(":")
            ref[int(code, 16)] = (name, mode, int(nbytes), int(cyc))
    print(f"documented opcodes in the reference: {len(ref)}")

    problems = 0
    rows = []
    for line in open(dump):
        f = line.split()
        if len(f) != 6 or not f[1].startswith("mode="):
            continue
        code = int(f[0], 16)
        mode = MODES[int(f[1].split("=")[1])]
        kind = ["none", "read", "write", "rmw"][int(f[2].split("=")[1])]
        op = OPS[int(f[3].split("=")[1])]
        nxt = int(f[4].split("=")[1], 16)
        cyc = int(f[5].split("=")[1])
        # name the opcode the way the CPU itself tells them apart
        if mode == "ctl":
            name, mode = CTL[code]
        elif mode == "rel":
            flag = "NVCZ"[code >> 6]
            name = BRANCH[(flag, (code >> 5) & 1)]
        else:
            name = op
        length = nxt - 0x0209
        if code in ref:
            rname, rmode, rbytes, rcyc = ref[code]
            msgs = []
            if (name, mode) != (rname, rmode):
                msgs.append(f"decoded as {name} {mode}, "
                            f"manual says {rname} {rmode}")
            if mode == "rel":
                taken = FLAGS_AT_TEST[flag] == (code >> 5) & 1
                want_cyc = 3 if taken else 2
                want_nxt = 0x021B if taken else 0x020B
                if (cyc, nxt) != (want_cyc, want_nxt):
                    msgs.append(f"branch: {cyc} cycles to {nxt:04X}")
            else:
                if cyc != rcyc:
                    msgs.append(f"{cyc} cycles, manual says {rcyc}")
                jumps = ("BRK", "JSR", "RTI", "RTS", "JMP")
                if name not in jumps and length != rbytes:
                    msgs.append(f"{length} bytes, manual says {rbytes}")
                if name in ("JMP", "JSR") and mode == "abs" and nxt != 0x3010:
                    msgs.append(f"jumped to {nxt:04X}")
            for m in msgs:
                print(f"${code:02X}: {m}")
            problems += len(msgs)
            rows.append((code, rname, rmode, kind, cyc, "doc"))
        else:
            # undocumented: must be a NOP that takes two cycles
            ok_len = length == 1 or (code == 0x89 and length == 2)
            if op != "NOP" or cyc != 2 or not ok_len:
                print(f"${code:02X}: undocumented, decoded as {name} {mode}, "
                      f"{length} bytes, {cyc} cycles")
                problems += 1
            rows.append((code, "NOP", mode, kind, cyc, "undoc"))
    ndoc = sum(1 for r in rows if r[5] == "doc")
    print(f"opcodes decoded: {len(rows)}, documented {ndoc}, "
          f"undocumented {len(rows) - ndoc}")
    print(f"mismatches: {problems}")
    with open(matrix_out, "w") as out:
        for r in rows:
            out.write(f"{r[0]:02X} {r[1]} {r[2]} {r[3]} {r[4]} {r[5]}\n")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
