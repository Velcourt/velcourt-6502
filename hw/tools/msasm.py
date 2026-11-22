#!/usr/bin/env python3
"""msasm.py - assemble Microsoft's 1978 6502 BASIC source (MACRO-10 dialect).

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt.  MIT licence.

Microsoft wrote BASIC on a PDP-10 and assembled it with MACRO-10, using a
macro library (M6502) that taught MACRO-10 the 6502 instructions. This
script understands the subset of MACRO-10 that m6502.asm uses:

  * conditionals   IFE expr,<...>  IFN expr,<...>  (IF1/IF2/IFNDEF ignored)
  * macros         DEFINE NAME (ARGS),<body>     REPEAT n,<body>
  * numbers        RADIX 8 or 10, ^O octal, ^D decimal, "C" character
  * operators      + - * / & (and) ! (or) _ (shift), <...> as brackets
  * data           bare expressions (one byte), ADR(x) (a word), DT"text",
                   DC"text" (last character with bit 7 set), EXP, XWD, BLOCK
  * instructions   LDA X / LDA X,X / LDA X,Y,  and the M6502 suffixes:
                   LDAI = immediate, LDADY = (zp),Y, JMPD = JMP (ind),
                   LSR A, = accumulator

Usage: msasm.py SOURCE OUT.bin OUT.sym  START END  [SYM=VALUE ...]
"""
import re, sys

SYMCH = r"A-Z0-9$%."
OPS = {  # mnemonic: {mode: opcode}
 "ADC": {"imm":0x69,"zp":0x65,"zpx":0x75,"abs":0x6D,"absx":0x7D,"absy":0x79,"izx":0x61,"izy":0x71},
 "AND": {"imm":0x29,"zp":0x25,"zpx":0x35,"abs":0x2D,"absx":0x3D,"absy":0x39,"izx":0x21,"izy":0x31},
 "ASL": {"acc":0x0A,"zp":0x06,"zpx":0x16,"abs":0x0E,"absx":0x1E},
 "BIT": {"zp":0x24,"abs":0x2C},
 "CMP": {"imm":0xC9,"zp":0xC5,"zpx":0xD5,"abs":0xCD,"absx":0xDD,"absy":0xD9,"izx":0xC1,"izy":0xD1},
 "CPX": {"imm":0xE0,"zp":0xE4,"abs":0xEC},
 "CPY": {"imm":0xC0,"zp":0xC4,"abs":0xCC},
 "DEC": {"zp":0xC6,"zpx":0xD6,"abs":0xCE,"absx":0xDE},
 "EOR": {"imm":0x49,"zp":0x45,"zpx":0x55,"abs":0x4D,"absx":0x5D,"absy":0x59,"izx":0x41,"izy":0x51},
 "INC": {"zp":0xE6,"zpx":0xF6,"abs":0xEE,"absx":0xFE},
 "JMP": {"abs":0x4C,"ind":0x6C},
 "JSR": {"abs":0x20},
 "LDA": {"imm":0xA9,"zp":0xA5,"zpx":0xB5,"abs":0xAD,"absx":0xBD,"absy":0xB9,"izx":0xA1,"izy":0xB1},
 "LDX": {"imm":0xA2,"zp":0xA6,"zpy":0xB6,"abs":0xAE,"absy":0xBE},
 "LDY": {"imm":0xA0,"zp":0xA4,"zpx":0xB4,"abs":0xAC,"absx":0xBC},
 "LSR": {"acc":0x4A,"zp":0x46,"zpx":0x56,"abs":0x4E,"absx":0x5E},
 "ORA": {"imm":0x09,"zp":0x05,"zpx":0x15,"abs":0x0D,"absx":0x1D,"absy":0x19,"izx":0x01,"izy":0x11},
 "ROL": {"acc":0x2A,"zp":0x26,"zpx":0x36,"abs":0x2E,"absx":0x3E},
 "ROR": {"acc":0x6A,"zp":0x66,"zpx":0x76,"abs":0x6E,"absx":0x7E},
 "SBC": {"imm":0xE9,"zp":0xE5,"zpx":0xF5,"abs":0xED,"absx":0xFD,"absy":0xF9,"izx":0xE1,"izy":0xF1},
 "STA": {"zp":0x85,"zpx":0x95,"abs":0x8D,"absx":0x9D,"absy":0x99,"izx":0x81,"izy":0x91},
 "STX": {"zp":0x86,"zpy":0x96,"abs":0x8E},
 "STY": {"zp":0x84,"zpx":0x94,"abs":0x8C},
}
IMPLIED = {"BRK":0x00,"CLC":0x18,"CLD":0xD8,"CLI":0x58,"CLV":0xB8,"DEX":0xCA,"DEY":0x88,
 "INX":0xE8,"INY":0xC8,"NOP":0xEA,"PHA":0x48,"PHP":0x08,"PLA":0x68,"PLP":0x28,"RTI":0x40,
 "RTS":0x60,"SEC":0x38,"SED":0xF8,"SEI":0x78,"TAX":0xAA,"TAY":0xA8,"TSX":0xBA,"TXA":0x8A,
 "TXS":0x9A,"TYA":0x98}
BRANCH = {"BCC":0x90,"BCS":0xB0,"BEQ":0xF0,"BMI":0x30,"BNE":0xD0,"BPL":0x10,"BVC":0x50,"BVS":0x70}
IGNORE = {"TITLE","SUBTTL","SEARCH","SALL","PAGE","XLIST","LIST","PRINTX","PURGE","END",".XCREF",".CREF"}


class Asm:
    def __init__(self, presets):
        self.presets = presets
        self.prev = {}          # symbol values from the previous pass

    # ---------------------------------------------------------------- passes
    def run_pass(self, text, final):
        self.final = final
        self.sym = dict(self.presets)
        self.macros = {}
        self.radix = 10
        self.pc = 0
        self.mem = {}
        self.local = 0
        self.undefined = False
        self.process(text)
        return self.sym

    # ------------------------------------------------------------ expressions
    def value(self, name):
        if name == ".":
            return self.pc_stmt
        name = name[:6]                     # MACRO-10 keeps 6 characters
        if name in self.sym:
            return self.sym[name]
        if name in self.prev:
            return self.prev[name]          # forward reference: last pass's value
        if self.final:
            raise ValueError("undefined symbol " + name)
        self.undefined = True               # first pass, never seen yet
        return 0

    def tokens(self, s):
        toks, i = [], 0
        while i < len(s):
            c = s[i]
            if c in " \t":
                i += 1
            elif c == '"':
                j = s.index('"', i + 1)
                v = 0
                for ch in s[i + 1:j]:
                    v = (v << 7) | ord(ch)
                toks.append(("n", v)); i = j + 1
            elif c == "^":
                kind = s[i + 1]; m = re.match(r"[0-9]+", s[i + 2:])
                base = {"O": 8, "D": 10, "B": 2}[kind]
                toks.append(("n", int(m.group(0), base))); i += 2 + len(m.group(0))
            elif c.isdigit():
                m = re.match(r"[0-9]+", s[i:])
                d = m.group(0)
                # in RADIX 8 a number containing 8 or 9 is read as decimal
                base = 10 if re.search("[89]", d) else self.radix
                toks.append(("n", int(d, base))); i += len(d)
            elif re.match("[" + SYMCH + "]", c):
                m = re.match("[" + SYMCH + "]+", s[i:])
                toks.append(("s", m.group(0))); i += len(m.group(0))
            elif c in "+-*/&!_<>()":
                toks.append(("o", c)); i += 1
            else:
                raise ValueError("bad character %r in %r" % (c, s))
        return toks

    def expr(self, s):
        self._t = self.tokens(s); self._i = 0
        v = self._add()
        if self._i != len(self._t):
            raise ValueError("junk in expression %r" % s)
        return v

    def _peek(self):
        return self._t[self._i] if self._i < len(self._t) else (None, None)

    # MACRO-10 precedence: shift, then logical (& !), then * /, then + -
    def _add(self):
        v = self._mul()
        while self._peek() in (("o", "+"), ("o", "-")):
            op = self._t[self._i][1]; self._i += 1
            r = self._mul(); v = v + r if op == "+" else v - r
        return v

    def _mul(self):
        v = self._log()
        while self._peek() in (("o", "*"), ("o", "/")):
            op = self._t[self._i][1]; self._i += 1
            r = self._log(); v = v * r if op == "*" else (v // r if r else 0)
        return v

    def _log(self):
        v = self._shift()
        while self._peek() in (("o", "&"), ("o", "!")):
            op = self._t[self._i][1]; self._i += 1
            r = self._shift(); v = v & r if op == "&" else v | r
        return v

    def _shift(self):
        v = self._unary()
        while self._peek() == ("o", "_"):
            self._i += 1; r = self._unary()
            v = v << r if r >= 0 else v >> -r
        return v

    def _unary(self):
        t = self._peek()
        if t == ("o", "-"):
            self._i += 1; return -self._unary()
        if t == ("o", "+"):
            self._i += 1; return self._unary()
        if t in (("o", "<"), ("o", "(")):
            close = ">" if t[1] == "<" else ")"
            self._i += 1; v = self._add()
            if self._peek() != ("o", close):
                raise ValueError("missing " + close)
            self._i += 1; return v
        self._i += 1
        if t[0] == "n":
            return t[1]
        if t[0] == "s":
            return self.value(t[1])
        raise ValueError("expected a value")

    # ------------------------------------------------------------- emission
    def emit(self, *bs):
        for b in bs:
            if self.final and not (-256 <= b <= 255):
                raise ValueError("byte out of range: %d" % b)
            self.mem[self.pc & 0xFFFF] = b & 0xFF
            self.pc += 1

    # ------------------------------------------------------------ structure
    @staticmethod
    def bracket_body(text, i):
        """text[i] == '<'. Return (body, index after the matching '>')."""
        depth, j = 0, i
        while j < len(text):
            if text[j] == "<": depth += 1
            elif text[j] == ">":
                depth -= 1
                if depth == 0:
                    return text[i + 1:j], j + 1
            j += 1
        raise ValueError("unbalanced < >")

    @staticmethod
    def split_args(s):
        args, depth, cur, inq = [], 0, "", False
        for c in s:
            if c == '"': inq = not inq
            if not inq:
                if c == "<": depth += 1
                elif c == ">": depth -= 1
                elif c == "," and depth == 0:
                    args.append(cur); cur = ""; continue
            cur += c
        args.append(cur)
        out = []
        for a in args:
            a = a.strip()
            if a.startswith("<") and a.endswith(">") and Asm.bracket_body(a, 0)[1] == len(a):
                a = a[1:-1]
            out.append(a)
        return out

    def process(self, text):
        i = 0
        n = len(text)
        while i < n:
            j = text.find("\n", i)
            if j < 0: j = n
            line = text[i:j]
            # labels
            while True:
                m = re.match(r"\s*([" + SYMCH + r"]+)(::|:!|:)", line)
                if not m: break
                self.sym[m.group(1)[:6]] = self.pc
                line = line[m.end():]
            s = line.strip()
            if not s:
                i = j + 1; continue
            word = re.match(r"[A-Z0-9$%.]*", s).group(0)
            rest_at = i + (len(text[i:j]) - len(line.lstrip())) + len(word)
            # ---- constructs with a <body> that may run over several lines
            if word in ("IFE", "IFN", "IF1", "IF2", "IFNDEF", "IFDEF", "REPEAT", "DEFINE", "IFDIF", "IFIDN"):
                # the body starts at the first "<" after the first comma that
                # is not inside brackets (the condition may use <...> itself)
                k, depth = rest_at, 0
                while True:
                    c = text[k]
                    if c == "<": depth += 1
                    elif c == ">": depth -= 1
                    elif c == "," and depth == 0: break
                    k += 1
                lt = text.index("<", k)
                head = text[rest_at:lt].strip().rstrip(",").strip()
                if word == "DEFINE":
                    # DEFINE NAME (PARAMS),<body>   or   DEFINE NAME,<body>
                    m = re.match(r"([A-Z0-9$%.]+)\s*(\(([^)]*)\))?", head)
                    body, end = self.bracket_body(text, lt)
                    name = m.group(1)
                    params = [p.strip() for p in m.group(3).split(",")] if m.group(3) else []
                    if name != "DT":           # DT is built in (it uses IRPC)
                        self.macros[name] = (params, body)
                    i = end; continue
                if word in ("IFDIF", "IFIDN"):
                    raise ValueError("IFDIF/IFIDN outside DT are not supported")
                body, end = self.bracket_body(text, lt)
                try:
                    cond = self.expr(head) if word in ("IFE", "IFN", "REPEAT") else 0
                except ValueError as e:
                    raise ValueError("%s\n    in: %s %s\n    at: %r" % (e, word, head, text[i:i+120])) from None
                if word == "IFE":
                    if self.expr(head) == 0: self.process(body)
                elif word == "IFN":
                    if self.expr(head) != 0: self.process(body)
                elif word == "REPEAT":
                    for _ in range(self.expr(head)): self.process(body)
                # IF1, IF2, IFNDEF, IFDEF: only listing and PURGE: skip
                i = end; continue
            if word == "COMMENT":
                raise ValueError("COMMENT should have been removed")
            try:
                self.statement(s)
            except ValueError as e:
                raise ValueError("%s\n    in: %s" % (e, s)) from None
            i = j + 1

    # ------------------------------------------------------------ statements
    def statement(self, s):
        self.pc_stmt = self.pc
        m = re.match(r"([" + SYMCH + r"]+)\s*==?\s*(.+)$", s)
        if m:
            self.sym[m.group(1)[:6]] = self.expr(m.group(2))
            return
        m = re.match(r"([A-Z.][A-Z0-9]*)(.*)$", s)
        op, arg = (m.group(1), m.group(2).strip()) if m else ("", s)

        if op in IGNORE:
            return
        if op == "RADIX":
            self.radix = int(arg); return
        if op == "ORG":
            self.pc = self.expr(arg); return
        if op == "BLOCK":
            self.pc += self.expr(arg); return
        if op == "DT":
            t = re.match(r'\s*"(.*)"', arg).group(1)
            self.emit(*[ord(c) for c in t]); return
        if op == "DC":
            t = re.match(r'\s*\(?\s*"(.*)"\s*\)?', arg).group(1)
            bs = [ord(c) for c in t]; bs[-1] |= 0x80
            self.emit(*bs); return
        if op == "EXP":
            for a in self.split_args(arg):
                self.emit(self.expr(a))
            return
        if op == "XWD":
            self.emit(self.expr(self.split_args(arg)[1])); return
        if op == "ADR":
            v = self.expr(arg) & 0xFFFF
            self.emit(v & 0xFF, v >> 8); return
        if op in self.macros:
            self.expand(op, arg); return
        if op in IMPLIED and not arg:
            self.emit(IMPLIED[op]); return
        if op in BRANCH:
            target = self.expr(arg)
            off = target - (self.pc + 2)
            if self.final and not -128 <= off <= 127:
                raise ValueError("branch out of range")
            self.emit(BRANCH[op], off & 0xFF); return
        inst = self.instruction(op, arg)
        if inst:
            return
        # anything else is data: one byte per comma-separated value
        for a in self.split_args(s):
            self.emit(self.expr(a))

    def expand(self, name, arg):
        params, body = self.macros[name]
        args = self.split_args(arg) if params else []
        text = body
        for p, a in zip(params, args + [""] * (len(params) - len(args))):
            text = re.sub(r"(?<![" + SYMCH + r"])" + re.escape(p) + r"(?![" + SYMCH + r"])",
                          lambda _m: a, text)
        if "%Q" in text:                   # generated local label
            self.local += 1
            text = text.replace("%Q", "%%L%03d" % self.local)   # 6 characters
        self.process(text)

    def instruction(self, op, arg):
        base, suffix = op, ""
        if op not in OPS:
            for suf in ("DY", "DX", "I", "D"):
                if op.endswith(suf) and op[:-len(suf)] in OPS:
                    base, suffix = op[:-len(suf)], suf; break
            else:
                return False
        modes = OPS[base]
        parts = [p.strip() for p in self.split_args(arg)] if arg else []
        while parts and parts[-1] == "":
            parts.pop()                     # "LDA X,Y," has a trailing comma
        if suffix == "I":
            v = self.expr(arg); self.emit(modes["imm"], v); return True
        if suffix == "DY":
            v = self.expr(parts[0]); self.emit(modes["izy"], v); return True
        if suffix == "DX":
            v = self.expr(parts[0]); self.emit(modes["izx"], v); return True
        if suffix == "D":                   # JMPD: JMP (indirect)
            v = self.expr(parts[0]); self.emit(modes["ind"], v & 0xFF, (v >> 8) & 0xFF); return True
        if not parts or parts == ["A"]:
            self.emit(modes["acc"]); return True
        self.undefined = False
        v = self.expr(parts[0])
        index = parts[1] if len(parts) > 1 else ""
        zp_ok = 0 <= v <= 255 and not self.undefined   # unknown: assume absolute
        if index == "X":
            m = "zpx" if zp_ok and "zpx" in modes else "absx"
        elif index == "Y":
            m = "zpy" if zp_ok and "zpy" in modes else "absy"
        else:
            m = "zp" if zp_ok and "zp" in modes and base not in ("JMP", "JSR") else "abs"
        if m in ("zp", "zpx", "zpy"):
            self.emit(modes[m], v)
        else:
            self.emit(modes[m], v & 0xFF, (v >> 8) & 0xFF)
        return True


def load(path):
    src = open(path, encoding="latin-1").read().upper().replace("\r", "")
    # remove COMMENT blocks: COMMENT x ... x
    out, i = [], 0
    while True:
        m = re.search(r"^COMMENT\s*(\S)", src[i:], re.M)
        if not m:
            out.append(src[i:]); break
        out.append(src[i:i + m.start()])
        end = src.index(m.group(1), i + m.end())
        i = src.index("\n", end) + 1
    src = "".join(out)
    # remove ; comments (but not inside "...")
    lines = []
    for line in src.split("\n"):
        inq, cut = False, len(line)
        for k, c in enumerate(line):
            if c == '"': inq = not inq
            elif c == ";" and not inq:
                cut = k; break
        lines.append(line[:cut].rstrip())
    return "\n".join(lines) + "\n"


def main():
    src, out_bin, out_sym, start, end = sys.argv[1:6]
    start, end = int(start, 0), int(end, 0)
    presets = {}
    for a in sys.argv[6:]:
        k, v = a.split("=")
        presets[k.upper()] = int(v, 0)
    text = load(src)
    asm = Asm(presets)
    for p in range(1, 9):                   # repeat until labels stop moving
        sym = asm.run_pass(text, final=False)
        if sym == asm.prev:
            break
        asm.prev = sym
    asm.run_pass(text, final=True)
    image = bytes(asm.mem.get(a, 0xFF) for a in range(start, end + 1))
    open(out_bin, "wb").write(image)
    used = [a for a in asm.mem if start <= a <= end]
    with open(out_sym, "w") as f:
        for k in sorted(asm.sym):
            if re.match(r"^[A-Z][A-Z0-9]*$", k):
                f.write("%s = $%04X\n" % (k, asm.sym[k] & 0xFFFF))
    print("passes: %d   bytes in %04X-%04X: %d (top %04X)" % (
        p, start, end, len(used), max(used) if used else 0))


if __name__ == "__main__":
    main()
