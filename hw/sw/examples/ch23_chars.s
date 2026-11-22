; ch23_chars.s - print every character of the font, 16 to a line, each
; line starting with the hex code of its first character.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 ch23_chars.s
;        ld65 -C ch09_ram.cfg -o ch23_chars.bin ch23_chars.o
; Then:  python3 -I tools/bin2ihex.py (see Chapter 23) to make the HEX file.
; Load with L, run with G 0600.

        .setcpu "6502"

CHROUT  = $FF00             ; kernel: print A, keeps A, X and Y

        .segment "CODE"
start:  ldx #$20            ; the space is the first character
line:   jsr crlf
        txa
        jsr hex2            ; "20"
        lda #':'
        jsr CHROUT
char:   lda #' '
        jsr CHROUT
        txa
        jsr CHROUT          ; the character itself
        inx
        cpx #$7F            ; $7E is the last one in the font
        beq done
        txa
        and #$0F            ; a new line every 16 characters
        bne char
        beq line
done:   jmp crlf            ; its RTS takes us back to the monitor

crlf:   lda #13
        jsr CHROUT
        lda #10
        jmp CHROUT

; hex2: print A as two hex digits
hex2:   pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr digit
        pla
        and #$0F
digit:  cmp #10
        bcc :+
        adc #6              ; carry is set here: +7 skips to "A"
:       adc #'0'
        jmp CHROUT
