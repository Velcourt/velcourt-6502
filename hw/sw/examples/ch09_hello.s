; ch09_hello.s - a first 6502 program: print a line through the kernel
; Assemble:  ca65 -l ch09_hello.lst ch09_hello.s
; Link:      ld65 -C ch09_ram.cfg -o ch09_hello.bin ch09_hello.o
; Run it from the monitor with L (load) and G 0600 (go).

        .setcpu "6502"

CHROUT  = $FF00             ; kernel: print the character in A

        .segment "CODE"
start:  ldx #0              ; X walks along the message
loop:   lda message,x       ; absolute,X: the byte at message+X
        beq done            ; a zero byte ends the text
        jsr CHROUT
        inx
        bne loop            ; at most 256 characters
done:   rts                 ; back to the monitor

        .segment "RODATA"
message:
        .byte 13, 10, "HELLO FROM THE 6502", 13, 10, 0
