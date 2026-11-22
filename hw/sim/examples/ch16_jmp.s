; ch16_jmp.s - JMP absolute, JMP indirect, and the $xxFF page-wrap bug.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch16_jmp

.macro  at addr                 ; pad with zeros up to an address
        .res (addr) - *
.endmacro

        .org $0000
        at $0200
        .byte $08               ; $0200: the high byte the NMOS chip uses
        at $0280
        .word step3             ; $0280/$0281: an ordinary pointer
        at $02FF
        .byte $20               ; $02FF: low byte of the pointer
        .byte $07               ; $0300: the high byte you might expect
        at $0600

start:  jmp step2               ; absolute: 3 cycles
step2:  jmp ($0280)             ; indirect: 5 cycles, goes to step3
step3:  .byte $6C, $FF, $02     ; JMP ($02FF): ca65 refuses to assemble it,
                                ; so we write the three bytes by hand.
                                ; It reads $02FF and $0200, not $0300.

        at $0720
        jmp wrong               ; $0720: where a 65C02 would go

        at $0820
        jmp done                ; $0820: where the NMOS 6502 goes
wrong:  nop
done:   jmp done
