; ch17_stack.s - the stack instructions, cycle by cycle.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch17_stack

        .org $0000
        .res $0600              ; pages 0-5: nothing here yet

start:  cld                     ; D, C and V are unknown after reset
        clc
        clv
        ldx #$FF
        txs                     ; S = $FF
        lda #$5A
        pha                     ; $01FF = $5A, S = $FE
        php                     ; $01FE = P with B = 1, S = $FD
        jsr sub                 ; pushes $06, $0C: its own last byte
        plp                     ; flags back, S = $FE
        pla                     ; A = $5A, S = $FF
done:   jmp done                ; the harness stops on this loop

sub:    lda #$00                ; Z = 1, so P changes inside
        rts
