; ch21_timing.s - how many CPU cycles does the kernel need to draw
; one character? Timer 2 of the VIA counts CPU cycles for us.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 ch21_timing.s
;        ld65 -C ch09_ram.cfg -o ch21_timing.bin ch21_timing.o
; Load at $0600 with the monitor (L), run with G 0600, then D 0700 0707.
;
; Results (counter values, low byte first):
;   $0700/$0701  timer after an empty subroutine call
;   $0702/$0703  timer after a call to draw_char
;   $0704/$0705  timer after a call to CHROUT ($FF00)
; A routine's cycles, first instruction to RTS = (value at $0700)
; - (its value) + 4. Add 6 for the JSR that calls it.

        .setcpu "6502"
T2L       = $BF28             ; VIA timer 2, low byte
T2H       = $BF29             ; VIA timer 2, high byte (write starts it)
cur_x     = $0200             ; kernel text cursor
cur_y     = $0201
DRAW_CHAR = $E242             ; draw_char, from sw/kernel.lst ($E100+$142)
CHROUT    = $FF00
RESULT    = $0700

        .segment "CODE"
start:  lda #10               ; draw at column 10, row 12
        sta cur_x
        lda #12
        sta cur_y
        jsr start_t2          ; 1: an empty call
        jsr empty
        ldx #0
        jsr stop_t2
        jsr start_t2          ; 2: draw_char
        lda #'A'
        jsr DRAW_CHAR
        ldx #2
        jsr stop_t2
        jsr start_t2          ; 3: CHROUT (screen and serial)
        lda #'B'
        jsr CHROUT
        ldx #4
        jsr stop_t2
        rts                   ; back to the monitor

start_t2:
        lda #$FF
        sta T2L               ; latch low byte
        sta T2H               ; counter = $FFFF, counting down
empty:  rts

stop_t2:
        lda T2L               ; read the counter, low byte first
        sta RESULT,x
        lda T2H
        sta RESULT+1,x
        rts
