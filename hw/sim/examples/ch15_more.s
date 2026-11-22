; ch15_more.s - the rest of the cycle table: stores, absolute,Y, zero
; page,Y and the read-modify-write cases, so every number in the chapter's
; summary table comes from a run.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch15_more +sum=1

        .org $0000
        .res $0600

start:  ldx #$05
        ldy #$10
        sta $80,x               ; zero page,X store     4
        stx $80,y               ; zero page,Y store     4
        ldx $80,y               ; zero page,Y load      4
        ldx #$05
        sta $0234               ; absolute store        4
        lda $0234,y             ; absolute,Y            4
        lda $02F8,y             ; absolute,Y crossing   5
        sta $0234,y             ; absolute,Y store      5
        sta ($40,x)             ; (zp,X) store          6
        inc $80,x               ; zero page,X RMW       6
        inc $0234,x             ; absolute,X RMW        7 (no crossing)
        lda #$00                ; immediate             2
        ora $0234,x             ; absolute,X read       4 (no crossing)
done:   jmp done
