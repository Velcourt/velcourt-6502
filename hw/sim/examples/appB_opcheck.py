#!/usr/bin/env python3
# appB_opcheck.py - checks the opcode table of Appendices A and B two ways:
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
# Run from hw/:  python3 -I sim/examples/appB_opcheck.py
# Work files go to sim/out/appB/.
#  1. ca65 assembles every instruction form; the opcode byte and the
#     length must match the table.
#  2. hw/rtl/cpu6502.v runs a program with every form (Icarus Verilog);
#     the cycles between opcode fetches (sync) must match the table,
#     including page-crossing and branch penalties, and every
#     undocumented opcode must be a 2-cycle NOP of 1 byte ($89: 2 bytes).
import os, subprocess, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from appB_optable import T, BYTES, all_ops

HW = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(HW, 'sim', 'out', 'appB')
os.makedirs(HERE, exist_ok=True)
TOOLS = os.path.join(os.path.dirname(HW), 'tools')
os.environ['PATH'] = (TOOLS + '/oss-cad-suite/bin:' + TOOLS + '/cc65/bin:' + os.environ['PATH'])

def run(cmd):
    r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    if r.returncode:
        print(r.stdout, r.stderr); sys.exit('failed: ' + ' '.join(cmd))
    return r.stdout

CFG = """MEMORY { M: start=$0000, size=$10000, file=%O, fill=yes, fillval=$EA; }
SEGMENTS { CODE: load=M, type=rw, start=$1000;
           VEC: load=M, type=ro, start=$FFFA; }
"""
open(os.path.join(HERE, 'm.cfg'), 'w').write(CFG)

# ---------------- 1. opcode bytes and lengths ----------------
def operand(mode):
    return {'imp':'', 'acc':' a', 'imm':' #$44', 'zp':' $30', 'zpx':' $30,x',
            'zpy':' $30,y', 'abs':' $0300', 'absx':' $0300,x', 'absy':' $0300,y',
            'indx':' ($10,x)', 'indy':' ($10),y', 'ind':' ($0280)', 'rel':' *+2'}[mode]

ops = all_ops()
src = ['.setcpu "6502"', '.segment "CODE"']
for m, mode, code, cyc, pen in ops:
    src.append('  %s%s' % (m.lower(), operand(mode)))
src += ['.segment "VEC"', '.word 0,0,0']
open(os.path.join(HERE, 'forms.s'), 'w').write('\n'.join(src) + '\n')
run(['ca65', '-o', 'forms.o', '-l', 'forms.lst', 'forms.s'])
run(['ld65', '-C', 'm.cfg', '-o', 'forms.bin', 'forms.o'])
img = open(os.path.join(HERE, 'forms.bin'), 'rb').read()
pc, bad = 0x1000, 0
for m, mode, code, cyc, pen in ops:
    if img[pc] != code:
        print('OPCODE MISMATCH %s %s: table $%02X, ca65 $%02X' % (m, mode, code, img[pc])); bad += 1
    pc += BYTES[mode]
if bad: sys.exit('ca65 check failed')
print('ca65: %d forms, opcodes and lengths agree' % len(ops))

# ---------------- 2. cycles on cpu6502.v ----------------
tests = []      # (label, expected cycles, expected next pc offset or None, text)
lines = ['.setcpu "6502"', '.segment "CODE"', 'start:',
         '  ldx #$ff', '  txs', '  cld',
         '  lda #$00', '  sta $10', '  lda #$03', '  sta $11',     # ($10) -> $0300
         '  lda #$f0', '  sta $20', '  lda #$03', '  sta $21']     # ($20) -> $03F0
n = 0
def test(setup, body, cycles, desc, nxt=None):
    global n
    n += 1
    lab = 'T%d' % n
    lines.extend('  ' + s for s in setup)
    lines.append(lab + ':')
    lines.extend('  ' + b for b in body)
    tests.append((lab, cycles, nxt, desc))

flow = {'JMP', 'JSR', 'RTS', 'RTI', 'BRK', 'PHA', 'PLA', 'PHP', 'PLP', 'TXS'}
for m, mode, code, cyc, pen in ops:
    if pen == 'b' or m in flow:
        continue
    setup = ['ldx #0', 'ldy #0', 'cld']
    test(setup, ['%s%s' % (m.lower(), operand(mode))], cyc, '%s %s' % (m, mode))
    if pen == 1:   # the same form across a page
        op2 = {'absx':' $03f0,x', 'absy':' $03f0,y', 'indy':' ($20),y'}[mode]
        test(['ldx #$ff', 'ldy #$ff', 'cld'], ['%s%s' % (m.lower(), op2)], cyc + 1,
             '%s %s page crossed' % (m, mode))
# indexed writes and read-modify-write across a page: no extra cycle
for body, c in [('sta $03f0,x', 5), ('sta $03f0,y', 5), ('sta ($20),y', 6),
                ('inc $03f0,x', 7), ('asl $03f0,x', 7)]:
    test(['ldx #$ff', 'ldy #$ff'], [body], c, body + ' page crossed')
# stack and flow
test([], ['pha'], 3, 'PHA'); test([], ['pla'], 4, 'PLA')
test([], ['php'], 3, 'PHP'); test([], ['plp'], 4, 'PLP')
test(['tsx'], ['txs'], 2, 'TXS')
test([], ['jmp *+3'], 3, 'JMP abs')
lines += ['  lda #<jt', '  sta $0280', '  lda #>jt', '  sta $0281']
test([], ['jmp ($0280)', 'jt:'], 5, 'JMP ind')
test([], ['jsr sub'], 6, 'JSR')
test([], ['brk', '.byte $00'], 7, 'BRK')
# branches
cond = {'BCC':(['clc'],['sec']), 'BCS':(['sec'],['clc']), 'BEQ':(['lda #0'],['lda #1']),
        'BNE':(['lda #1'],['lda #0']), 'BMI':(['lda #$80'],['lda #0']),
        'BPL':(['lda #0'],['lda #$80']), 'BVC':(['clv'],['lda #$40','clc','adc #$40']),
        'BVS':(['lda #$40','clc','adc #$40'],['clv'])}
for b, (yes, no) in cond.items():
    test(yes, [b.lower() + ' *+2'], 3, b + ' taken')
    test(no, [b.lower() + ' *+2'], 2, b + ' not taken')
    # taken, forward across a page: branch at $xxFD, target $(xx+1)00
    lab = 'X' + b
    lines.extend('  ' + s for s in yes)
    lines += ['  jmp ' + lab, '.align 256', '.res $FD, $EA', lab + ':']
    n += 1; lines.append('T%d:' % n); lines += ['  %s *+3' % b.lower(), '  nop']
    tests.append(('T%d' % n, 4, None, b + ' taken across a page'))
# taken, backward across a page
lines += ['  clc', '  jmp XBACK', '.align 256', '.res $FE, $EA', 'back: jmp cont', 'XBACK:']
n += 1; lines += ['T%d:' % n, '  bcc back', 'cont:']
tests.append(('T%d' % n, 4, None, 'BCC taken backward across a page'))
# undocumented opcodes
documented = {o[2] for o in ops}
for code in range(256):
    if code in documented:
        continue
    if code == 0x89:
        test([], ['.byte $89, $EA'], 2, 'undocumented $89', nxt=2)
    else:
        test([], ['.byte $%02X' % code], 2, 'undocumented $%02X' % code, nxt=1)
lines += ['done: jmp done', 'sub:']
n += 1; lines += ['T%d:' % n, '  rts']; tests.append(('T%d' % n, 6, None, 'RTS'))
lines += ['irqh:']
n += 1; lines += ['T%d:' % n, '  rti']; tests.append(('T%d' % n, 6, None, 'RTI'))
lines += ['.segment "VEC"', '.word irqh, start, irqh']
open(os.path.join(HERE, 'cycles.s'), 'w').write('\n'.join(lines) + '\n')
run(['ca65', '-g', '-o', 'cycles.o', '-l', 'cycles.lst', 'cycles.s'])
run(['ld65', '-C', 'm.cfg', '-o', 'cycles.bin', '-Ln', 'cycles.lbl', 'cycles.o'])
img = open(os.path.join(HERE, 'cycles.bin'), 'rb').read()
with open(os.path.join(HERE, 'cycles.hex'), 'w') as f:
    for b in img:
        f.write('%02x\n' % b)
labels = {}
for l in open(os.path.join(HERE, 'cycles.lbl')):
    _, addr, name = l.split()
    labels[name.lstrip('.')] = int(addr, 16)

TB = """`timescale 1ns/1ns
module tb;
reg clk = 0, rst = 1;
wire [15:0] ab; wire [7:0] dout; wire we, sync;
reg [7:0] mem [0:65535];
wire [7:0] din = mem[ab];
cpu6502 u (.clk(clk), .ce(1'b1), .rst(rst), .ab(ab), .dout(dout), .we(we),
           .din(din), .irq_n(1'b1), .nmi_n(1'b1), .sync(sync));
integer cyc = 0;
always #5 clk = ~clk;
initial begin
    $readmemh("cycles.hex", mem);
    #22 rst = 0;
end
always @(posedge clk) if (!rst) begin
    if (we) mem[ab] <= dout;
    if (sync) $display("S %h %0d", ab, cyc);
    if (sync && ab == 16'hDONEADDR) $finish;
    cyc <= cyc + 1;
    if (cyc > 200000) $finish;
end
endmodule
""".replace('DONEADDR', '%04x' % labels['done'])
open(os.path.join(HERE, 'tb.v'), 'w').write(TB)
run(['iverilog', '-o', 'tb.vvp', 'tb.v', HW + '/rtl/cpu6502.v', HW + '/rtl/alu6502.v'])
out = run(['vvp', '-n', 'tb.vvp'])
syncs = [(int(a, 16), int(c)) for a, c in re.findall(r'^S ([0-9a-f]{4}) (\d+)$', out, re.M)]
first = {}
for i in range(len(syncs) - 1):
    a, c = syncs[i]
    if a not in first:
        first[a] = (syncs[i + 1][1] - c, syncs[i + 1][0])
bad = 0
for lab, cyc, nxt, desc in tests:
    a = labels[lab]
    if a not in first:
        print('NOT EXECUTED', desc, hex(a)); bad += 1; continue
    got, npc = first[a]
    if got != cyc or (nxt is not None and npc != a + nxt):
        print('MISMATCH %-30s table %d, cpu6502.v %d, next pc $%04X' % (desc, cyc, got, npc)); bad += 1
print('cpu6502.v: %d timing checks, %d mismatches' % (len(tests), bad))
