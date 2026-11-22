; ch22_ledcount.s - count in binary on the six LEDs, ten steps a second.
; Timer 1 of the VIA runs free and sets its flag every 5 ms; the program
; watches the flag (polling) and steps the count every 20 flags.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 ch22_ledcount.s
;        ld65 -C ch09_ram.cfg -o ch22_ledcount.bin ch22_ledcount.o
; Load with L, run with G 0600. Any key returns to the monitor.
; Then D 0700 shows ticks ($0700) and the count ($0701).

        .setcpu "6502"

ORB     = $BF20             ; port B: LEDs on bits 0-5 (1 = lit)
DDRB    = $BF22             ; 1 = output
T1CL    = $BF24             ; read: counter low, clears the T1 flag
T1CH    = $BF25             ; write: latch high, load counter, start
ACR     = $BF2B             ; bit 6 = 1: T1 reloads itself
IFR     = $BF2D             ; bit 6: T1 has reached zero
GETKEY  = $FF06             ; kernel: A = key or 0
PERIOD  = 62999             ; 63,000 cycles = 5 ms at 12.6 MHz
STEPS   = 20                ; 20 x 5 ms = 100 ms per count
ticks   = $0700
count   = $0701

        .segment "CODE"
start:  lda #$3F
        sta DDRB            ; six outputs (the kernel set this already)
        lda #0
        sta ticks
        sta count
        sta ORB             ; all LEDs off
        lda #$40
        sta ACR             ; T1 free-running
        lda #<PERIOD
        sta T1CL            ; writing T1CL fills the latch only
        lda #>PERIOD
        sta T1CH            ; now the counter loads and starts
wait:   jsr GETKEY          ; a key ends the program
        bne done
        lda IFR
        and #$40            ; has T1 reached zero?
        beq wait
        lda T1CL            ; yes: reading T1CL clears the flag
        inc ticks
        lda ticks
        cmp #STEPS
        bne wait
        lda #0
        sta ticks
        inc count
        lda count
        sta ORB             ; bits 6 and 7 go nowhere
        jmp wait
done:   rts                 ; back to the monitor
