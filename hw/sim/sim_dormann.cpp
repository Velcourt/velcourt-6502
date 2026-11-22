// sim_dormann.cpp - Verilator test bench: Klaus Dormann's 6502 functional
// test (and optionally the decimal test) on cpu6502.
#include "Vcpu6502.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
static unsigned char mem[65536];
int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s image.bin success_hex [start_hex]\n", argv[0]); return 2; }
    FILE* f = fopen(argv[1], "rb"); fread(mem, 1, 65536, f); fclose(f);
    unsigned success = strtoul(argv[2], 0, 16);
    unsigned start = argc > 3 ? strtoul(argv[3], 0, 16) : 0x400;
    mem[0xFFFC] = start & 0xFF; mem[0xFFFD] = start >> 8;
    Vcpu6502* cpu = new Vcpu6502;
    cpu->ce = 1; cpu->irq_n = 1; cpu->nmi_n = 1; cpu->rst = 1;
    for (int i = 0; i < 4; i++) { cpu->clk = 0; cpu->eval(); cpu->clk = 1; cpu->eval(); }
    cpu->rst = 0;
    unsigned long cycles = 0; unsigned last = 0xFFFFF; int same = 0;
    while (cycles < 400000000UL) {
        cpu->clk = 0; cpu->eval();
        cpu->din = mem[cpu->ab]; cpu->eval();        // memory answers in the cycle
        if (cpu->sync) {
            if (cpu->ab == last) same++; else same = 0;
            last = cpu->ab;
            if (same == 3) {
                if (argc > 4) { unsigned chk = strtoul(argv[4], 0, 16);
                    printf("trap at $%04X after %lu cycles; memory $%04X = %02X (%s)\n", cpu->ab, cycles,
                           chk, mem[chk], mem[chk] == 0 ? "PASS" : "FAIL"); return mem[chk] != 0; }
                if (cpu->ab == success) printf("PASS: reached $%04X after %lu cycles\n", success, cycles);
                else printf("FAIL: stuck at $%04X after %lu cycles\n", cpu->ab, cycles);
                return cpu->ab == success ? 0 : 1;
            }
        }
        if (cpu->we) mem[cpu->ab] = cpu->dout;
        cpu->clk = 1; cpu->eval();
        cycles++;
    }
    printf("TIMEOUT at $%04X\n", cpu->ab); return 1;
}
