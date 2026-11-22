# appB_optable.py - the NMOS 6502 instruction table used for Appendices A and B.
# Each entry: mnemonic -> list of (mode, opcode, cycles, page_penalty)
# page_penalty: 0 none, 1 = +1 when an index crosses a page (reads only),
#               'b' = branch (+1 taken, +2 taken across a page)

T = {
 'ADC': [('imm',0x69,2,0),('zp',0x65,3,0),('zpx',0x75,4,0),('abs',0x6D,4,0),('absx',0x7D,4,1),('absy',0x79,4,1),('indx',0x61,6,0),('indy',0x71,5,1)],
 'AND': [('imm',0x29,2,0),('zp',0x25,3,0),('zpx',0x35,4,0),('abs',0x2D,4,0),('absx',0x3D,4,1),('absy',0x39,4,1),('indx',0x21,6,0),('indy',0x31,5,1)],
 'ASL': [('acc',0x0A,2,0),('zp',0x06,5,0),('zpx',0x16,6,0),('abs',0x0E,6,0),('absx',0x1E,7,0)],
 'BCC': [('rel',0x90,2,'b')], 'BCS': [('rel',0xB0,2,'b')], 'BEQ': [('rel',0xF0,2,'b')],
 'BIT': [('zp',0x24,3,0),('abs',0x2C,4,0)],
 'BMI': [('rel',0x30,2,'b')], 'BNE': [('rel',0xD0,2,'b')], 'BPL': [('rel',0x10,2,'b')],
 'BRK': [('imp',0x00,7,0)],
 'BVC': [('rel',0x50,2,'b')], 'BVS': [('rel',0x70,2,'b')],
 'CLC': [('imp',0x18,2,0)], 'CLD': [('imp',0xD8,2,0)], 'CLI': [('imp',0x58,2,0)], 'CLV': [('imp',0xB8,2,0)],
 'CMP': [('imm',0xC9,2,0),('zp',0xC5,3,0),('zpx',0xD5,4,0),('abs',0xCD,4,0),('absx',0xDD,4,1),('absy',0xD9,4,1),('indx',0xC1,6,0),('indy',0xD1,5,1)],
 'CPX': [('imm',0xE0,2,0),('zp',0xE4,3,0),('abs',0xEC,4,0)],
 'CPY': [('imm',0xC0,2,0),('zp',0xC4,3,0),('abs',0xCC,4,0)],
 'DEC': [('zp',0xC6,5,0),('zpx',0xD6,6,0),('abs',0xCE,6,0),('absx',0xDE,7,0)],
 'DEX': [('imp',0xCA,2,0)], 'DEY': [('imp',0x88,2,0)],
 'EOR': [('imm',0x49,2,0),('zp',0x45,3,0),('zpx',0x55,4,0),('abs',0x4D,4,0),('absx',0x5D,4,1),('absy',0x59,4,1),('indx',0x41,6,0),('indy',0x51,5,1)],
 'INC': [('zp',0xE6,5,0),('zpx',0xF6,6,0),('abs',0xEE,6,0),('absx',0xFE,7,0)],
 'INX': [('imp',0xE8,2,0)], 'INY': [('imp',0xC8,2,0)],
 'JMP': [('abs',0x4C,3,0),('ind',0x6C,5,0)],
 'JSR': [('abs',0x20,6,0)],
 'LDA': [('imm',0xA9,2,0),('zp',0xA5,3,0),('zpx',0xB5,4,0),('abs',0xAD,4,0),('absx',0xBD,4,1),('absy',0xB9,4,1),('indx',0xA1,6,0),('indy',0xB1,5,1)],
 'LDX': [('imm',0xA2,2,0),('zp',0xA6,3,0),('zpy',0xB6,4,0),('abs',0xAE,4,0),('absy',0xBE,4,1)],
 'LDY': [('imm',0xA0,2,0),('zp',0xA4,3,0),('zpx',0xB4,4,0),('abs',0xAC,4,0),('absx',0xBC,4,1)],
 'LSR': [('acc',0x4A,2,0),('zp',0x46,5,0),('zpx',0x56,6,0),('abs',0x4E,6,0),('absx',0x5E,7,0)],
 'NOP': [('imp',0xEA,2,0)],
 'ORA': [('imm',0x09,2,0),('zp',0x05,3,0),('zpx',0x15,4,0),('abs',0x0D,4,0),('absx',0x1D,4,1),('absy',0x19,4,1),('indx',0x01,6,0),('indy',0x11,5,1)],
 'PHA': [('imp',0x48,3,0)], 'PHP': [('imp',0x08,3,0)], 'PLA': [('imp',0x68,4,0)], 'PLP': [('imp',0x28,4,0)],
 'ROL': [('acc',0x2A,2,0),('zp',0x26,5,0),('zpx',0x36,6,0),('abs',0x2E,6,0),('absx',0x3E,7,0)],
 'ROR': [('acc',0x6A,2,0),('zp',0x66,5,0),('zpx',0x76,6,0),('abs',0x6E,6,0),('absx',0x7E,7,0)],
 'RTI': [('imp',0x40,6,0)], 'RTS': [('imp',0x60,6,0)],
 'SBC': [('imm',0xE9,2,0),('zp',0xE5,3,0),('zpx',0xF5,4,0),('abs',0xED,4,0),('absx',0xFD,4,1),('absy',0xF9,4,1),('indx',0xE1,6,0),('indy',0xF1,5,1)],
 'SEC': [('imp',0x38,2,0)], 'SED': [('imp',0xF8,2,0)], 'SEI': [('imp',0x78,2,0)],
 'STA': [('zp',0x85,3,0),('zpx',0x95,4,0),('abs',0x8D,4,0),('absx',0x9D,5,0),('absy',0x99,5,0),('indx',0x81,6,0),('indy',0x91,6,0)],
 'STX': [('zp',0x86,3,0),('zpy',0x96,4,0),('abs',0x8E,4,0)],
 'STY': [('zp',0x84,3,0),('zpx',0x94,4,0),('abs',0x8C,4,0)],
 'TAX': [('imp',0xAA,2,0)], 'TAY': [('imp',0xA8,2,0)], 'TSX': [('imp',0xBA,2,0)],
 'TXA': [('imp',0x8A,2,0)], 'TXS': [('imp',0x9A,2,0)], 'TYA': [('imp',0x98,2,0)],
}

BYTES = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'rel':2,'indx':2,'indy':2,
         'abs':3,'absx':3,'absy':3,'ind':3}

# ca65 syntax for each mode (operand values chosen for the test program)
def syntax(m, mode, zp='$10', ab='$0300'):
    return {'imp':m, 'acc':m+' a', 'imm':m+' #$44', 'zp':m+' '+zp, 'zpx':m+' '+zp+',x',
            'zpy':m+' '+zp+',y', 'abs':m+' '+ab, 'absx':m+' '+ab+',x', 'absy':m+' '+ab+',y',
            'indx':m+' ('+zp+',x)', 'indy':m+' ('+zp+'),y', 'ind':m+' ('+ab+')', 'rel':m+' *+2'}[mode]

def all_ops():
    out = []
    for m, forms in T.items():
        for f in forms:
            out.append((m,) + f)
    return out

if __name__ == '__main__':
    ops = all_ops()
    codes = [o[2] for o in ops]
    assert len(codes) == len(set(codes)), 'duplicate opcode'
    print(len(T), 'mnemonics', len(ops), 'opcodes')
