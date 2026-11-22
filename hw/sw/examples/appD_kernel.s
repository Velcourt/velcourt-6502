; appD_kernel.s - calling the kernel through its jump table (Appendix D)
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 -l appD_kernel.lst appD_kernel.s
;        ld65 -C ch09_ram.cfg -o appD_kernel.bin appD_kernel.o
; Load with L, run with G 0600.

        .setcpu "6502"

CHROUT  = $FF00             ; print A (keeps A, X, Y)
CLS     = $FF0F             ; fill with the paper colour, cursor home
COLOR   = $FF12             ; ink CFG, paper CBG
LINE    = $FF18             ; GX0,GY0 - GX1,GY1 in colour GCOL
SOUND   = $FF1B             ; voice SVOICE, SFREQ Hz, volume SVOL
PAUSE   = $FF1E             ; wait PTICKS sixtieths of a second

GX0     = $0280             ; the parameter block shared with BASIC
GY0     = $0282
GX1     = $0283
GY1     = $0285
GCOL    = $0286
SVOICE  = $0287
SFREQ   = $0288
SVOL    = $028A
PTICKS  = $028B
CFG     = $028C
CBG     = $028D

        .segment "CODE"
start:  lda #7              ; lemon ink...
        sta CFG
        lda #0              ; ...on black paper
        sta CBG
        jsr COLOR
        jsr CLS
        ldx #0
@text:  lda message,x
        beq @line
        jsr CHROUT
        inx
        bne @text
@line:  lda #<10            ; from (10, 20)...
        sta GX0
        lda #>10
        sta GX0+1
        lda #20
        sta GY0
        lda #<309           ; ...to (309, 189)
        sta GX1
        lda #>309
        sta GX1+1
        lda #189
        sta GY1
        lda #5              ; leaf green
        sta GCOL
        jsr LINE            ; GX0,GY0 end up equal to GX1,GY1
        lda #0              ; voice 0, 440 Hz, volume 8
        sta SVOICE
        lda #<440
        sta SFREQ
        lda #>440
        sta SFREQ+1
        lda #8
        sta SVOL
        jsr SOUND
        lda #30             ; half a second
        sta PTICKS
        jsr PAUSE
        lda #0              ; silence
        sta SVOL
        jsr SOUND
        rts                 ; back to the monitor

        .segment "RODATA"
message:
        .byte "KERNEL CALLS FROM MACHINE CODE", 13, 0
