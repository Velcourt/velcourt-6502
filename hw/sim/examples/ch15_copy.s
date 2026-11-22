; ch15_copy.s - copy one page (256 bytes) from $0300 to $0400 with (zp),Y.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch15_copy +sum=1 +max=5000

src     = $20                   ; pointer to the source page
dst     = $22                   ; pointer to the destination page

        .org $0000
        .res $0600

start:  lda #$00
        sta src
        sta dst
        lda #$03
        sta src+1
        lda #$04
        sta dst+1
        ldy #$00
copy:   lda (src),y             ; 5 cycles: the pointer is page-aligned
        sta (dst),y             ; 6 cycles: a store always takes 6
        iny                     ; 2 cycles
        bne copy                ; 3 cycles while taken, 2 at the end
done:   jmp done
