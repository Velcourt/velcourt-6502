; ch16_branch.s - branches that take 2, 3 and 4 cycles.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch16_branch

.macro  at addr                 ; pad with zeros up to an address
        .res (addr) - *
.endmacro

        .org $0000
        at $0600

start:  ldx #$02
loop:   dex
        bne loop                ; taken once (3 cycles), then not (2)
        jmp edge                ; go to the end of the page

        at $06F0
back:   jmp done                ; target of the backward page crossing

        at $06FB
edge:   beq over                ; Z = 1: taken, $06FD -> $0710 (4 cycles)

        at $0710
over:   bne back                ; Z = 1: not taken (2 cycles)
        beq back                ; taken, $0714 -> $06F0 (4 cycles)

done:   jmp done
