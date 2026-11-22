; ch24_decode.s - feed ps2_decode the scan codes of some keystrokes and
; print what it returns, in hex. Load with the monitor's L command, run
; with G 0600.
; ps2_decode and prhex are not in the jump table, so their addresses
; come from sw/kernel.lst (CODE starts at $E100): check them again if
; the kernel changes.
ps2_decode = $E48E
prhex      = $EEB6
chrout     = $FF00

        .segment "CODE"
        ldx #0
loop:   stx $10             ; ps2_decode uses X
        lda codes,x
        beq done            ; 0 ends the list
        jsr ps2_decode
        jsr prhex           ; print A as two hex digits
        lda #' '
        jsr chrout
        ldx $10
        inx
        bne loop
done:   rts

codes:  .byte $14,$21,$F0,$21,$F0,$14          ; Ctrl + C
        .byte $12,$1C,$F0,$1C,$F0,$12          ; Shift + A
        .byte $E0,$71,$E0,$F0,$71              ; Delete
        .byte $E0,$74,$E0,$F0,$74              ; right arrow
        .byte $E0,$14,$21,$E0,$F0,$14,$F0,$21  ; right Ctrl + C
        .byte $1C, $76, $83, $AA               ; A, Esc, F7, self-test OK
        .byte 0
