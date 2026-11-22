; ch15_modes.s - one load or store in each addressing mode, with data
; placed so that the trace shows wrap-around and page crossing.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch15_modes

.macro  at addr                 ; pad with zeros up to an address
        .res (addr) - *
.endmacro

        .org $0000
        at $0003
        .byte $33               ; $0003: reached by LDA $FE,X with X=5
        at $0045
        .word $0250             ; $45/$46: pointer for LDA ($40,X)
        at $0050
        .word $0300             ; $50/$51: pointer for the (zp),Y loads
        .word $02F8             ; $52/$53: pointer that will cross a page
        at $0080
        .byte $11               ; $0080: LDA $80
        at $0085
        .byte $22               ; $0085: LDA $80,X
        at $0234
        .byte $44               ; $0234: LDA $0234
        at $0239
        .byte $55               ; $0239: LDA $0234,X
        at $0250
        .byte $77               ; $0250: LDA ($40,X)
        at $0303
        .byte $66               ; $0303: LDA $02FE,X
        at $0308
        .byte $99               ; $0308: LDA ($52),Y
        at $0310
        .byte $88               ; $0310: LDA ($50),Y
        at $0600

start:  ldx #$05
        ldy #$10
        lda $80                 ; zero page
        lda $80,x               ; zero page,X       -> $0085
        lda $FE,x               ; zero page,X wraps -> $0003
        lda $0234               ; absolute
        lda $0234,x             ; absolute,X        -> $0239
        lda $02FE,x             ; absolute,X        -> $0303, crosses
        sta $0234,x             ; store absolute,X  -> $0239
        lda ($40,x)             ; (zp,X): pointer at $45 -> $0250
        lda ($50),y             ; (zp),Y: $0300 + $10 = $0310
        lda ($52),y             ; (zp),Y: $02F8 + $10 = $0308, crosses
        sta ($50),y             ; store (zp),Y      -> $0310
        sta $10                 ; store zero page
done:   jmp done
