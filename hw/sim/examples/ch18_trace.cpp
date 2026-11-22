// ch18_trace.cpp - sim_dormann.cpp plus a flight recorder: when the CPU
// is caught in a trap, print the test number and the last instructions.
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
//
//   sh examples/ch18_trace.sh [cpu6502.v]          (from hw/sim)
#include "Vcpu6502.h"
#include "Vcpu6502___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
static unsigned char mem[65536];
struct Step { unsigned pc, op, a, x, y, p, s; };
static Step ring[16];

int main(int argc, char** argv) {
    FILE* f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 2; }
    fread(mem, 1, 65536, f); fclose(f);
    unsigned success = strtoul(argv[2], 0, 16);
    mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x04;          // start at $0400
    Vcpu6502* cpu = new Vcpu6502;
    Vcpu6502___024root* r = cpu->rootp;              // internal signals
    cpu->ce = 1; cpu->irq_n = 1; cpu->nmi_n = 1; cpu->rst = 1;
    for (int i = 0; i < 4; i++) {
        cpu->clk = 0; cpu->eval(); cpu->clk = 1; cpu->eval();
    }
    cpu->rst = 0;
    unsigned long cycles = 0, n = 0; unsigned last = 0xFFFFF; int same = 0;
    while (cycles < 400000000UL) {
        cpu->clk = 0; cpu->eval();
        cpu->din = mem[cpu->ab]; cpu->eval();
        if (cpu->sync) {
            unsigned p = r->cpu6502__DOT__fn << 7 | r->cpu6502__DOT__fv << 6
                | 0x20 | r->cpu6502__DOT__fd << 3 | r->cpu6502__DOT__fi << 2
                | r->cpu6502__DOT__fz << 1 | r->cpu6502__DOT__fc;
            ring[n++ % 16] = { cpu->ab, mem[cpu->ab], r->cpu6502__DOT__a,
                r->cpu6502__DOT__x, r->cpu6502__DOT__y, p,
                r->cpu6502__DOT__s };
            if (cpu->ab == last) same++; else same = 0;
            last = cpu->ab;
            if (same == 3) break;
        }
        if (cpu->we) mem[cpu->ab] = cpu->dout;
        cpu->clk = 1; cpu->eval();
        cycles++;
    }
    printf("%s at $%04X after %lu cycles, test case $%02X\n",
           last == success ? "PASS" : "TRAP", last, cycles, mem[0x200]);
    printf(" pc   op   a  x  y  p  s\n");
    for (unsigned i = n - 16; i < n - 3; i++) {
        Step& s = ring[i % 16];
        printf("%04X  %02X  %02X %02X %02X %02X %02X\n",
               s.pc, s.op, s.a, s.x, s.y, s.p, s.s);
    }
    return last != success;
}
