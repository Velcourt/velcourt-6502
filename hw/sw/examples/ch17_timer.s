; ch17_timer.s - a VIA timer 1 interrupt handler on the whole computer.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Timer 1 runs free with a period of 12,600 CPU cycles: one interrupt
; per millisecond at 12.6 MHz. The handler counts milliseconds in
; ticks and shows the count on the LEDs. The main program prints a
; digit every 10 ms, ten digits in all, then puts everything back.
;
; Build: ca65 ch17_timer.s
;        ld65 -C ch09_ram.cfg -o ch17_timer.bin ch17_timer.o
; Load with L, run with G 0600, then D 00F0 00F7 and D BF20 BF27.

        .setcpu "6502"

CHROUT  = $FF00
ORB     = $BF20             ; VIA port B: the LEDs
T1CL    = $BF24             ; read: clears the T1 flag
T1CH    = $BF25             ; write: load the counter and start
ACR     = $BF2B
IER     = $BF2E
irq_vec = $02F0             ; the kernel jumps through this on IRQ/BRK
PERIOD  = 12599             ; interrupt every PERIOD+1 = 12,600 cycles

ticks   = $F1               ; milliseconds, counted by the handler
target  = $F2               ; next value of ticks to wait for
old_vec = $F3               ; 2 bytes: irq_vec as we found it

        .segment "CODE"
start:  sei                 ; no interrupts while we rewire
        lda irq_vec         ; remember the old handler
        sta old_vec
        lda irq_vec+1
        sta old_vec+1
        lda #<handler       ; install ours
        sta irq_vec
        lda #>handler
        sta irq_vec+1
        lda #0
        sta ticks
        lda #$40
        sta ACR             ; T1 free-running
        lda #<PERIOD
        sta T1CL
        lda #>PERIOD
        sta T1CH            ; load and start T1
        lda #$C0
        sta IER             ; enable the T1 interrupt
        cli                 ; and let it in
        ldx #'0'
next:   lda ticks           ; wait for 10 more milliseconds
        clc
        adc #10
        sta target
wait:   lda ticks
        cmp target
        bne wait
        txa
        jsr CHROUT          ; print the next digit
        inx
        cpx #'9'+1
        bne next
        sei                 ; put everything back
        lda #$7F
        sta IER             ; VIA interrupts off
        lda T1CL            ; clear a flag that may be waiting
        lda old_vec
        sta irq_vec
        lda old_vec+1
        sta irq_vec+1
        rts                 ; back to the monitor (I stays 1)

; ---- the interrupt handler -------------------------------------
handler:
        pha                 ; A is the only register we touch
        lda T1CL            ; acknowledge: clears T1 flag, IRQ goes high
        inc ticks
        lda ticks
        sta ORB             ; LEDs show the low six bits
        pla
        rti
