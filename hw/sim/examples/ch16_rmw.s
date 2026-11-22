; ch16_rmw.s - read-modify-write instructions in four addressing modes.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch16_rmw

.macro  at addr                 ; pad with zeros up to an address
        .res (addr) - *
.endmacro

        .org $0000
        at $0010
        .byte $7F               ; $0010: INC makes it $80
        .byte $81               ; $0011: LSR $10,X makes it $40, C = 1
        at $0234
        .byte $C0               ; $0234: ASL makes it $80, C = 1
        at $0300
        .byte $01               ; $0300: DEC $02FF,X makes it $00, Z = 1
        at $0600

start:  ldx #$01
        lda #$41
        inc $10                 ; zero page         5 cycles
        lsr $10,x               ; zero page,X       6 cycles
        asl $0234               ; absolute          6 cycles
        dec $02FF,x             ; absolute,X        7 cycles (always)
        asl a                   ; accumulator       2 cycles: A = $82, C = 0
done:   jmp done
