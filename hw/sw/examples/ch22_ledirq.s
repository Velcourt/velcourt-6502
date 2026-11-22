; ch22_ledirq.s - the LED counter again, driven by the timer 1 interrupt.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 ch22_ledirq.s
;        ld65 -C ch09_ram.cfg -o ch22_ledirq.bin ch22_ledirq.o
; Load with L, run with G 0600. Any key returns to the monitor.
; Then D 0700 0707 shows ticks, count and the main loop's 3-byte count.

        .setcpu "6502"

ORB     = $BF20             ; port B: LEDs on bits 0-5 (1 = lit)
DDRB    = $BF22
T1CL    = $BF24             ; read: counter low, clears the T1 flag
T1CH    = $BF25             ; write: latch high, load counter, start
ACR     = $BF2B             ; bit 6 = 1: T1 reloads itself
IER     = $BF2E             ; bit 7 = 1 sets, 0 clears the named bits
GETKEY  = $FF06             ; kernel: A = key or 0
irq_vec = $02F0             ; kernel: IRQ and BRK jump through here
PERIOD  = 62999             ; 63,000 cycles = 5 ms at 12.6 MHz
STEPS   = 20                ; 20 x 5 ms = 100 ms per count
ticks   = $0700
count   = $0701
loops   = $0702             ; 3 bytes: the main program's own work
old_vec = $0705             ; 2 bytes: the kernel's handler, put back later

        .segment "CODE"
start:  sei                 ; no interrupts while we change things
        lda irq_vec         ; keep the old handler address
        sta old_vec
        lda irq_vec+1
        sta old_vec+1
        lda #<irq           ; install ours
        sta irq_vec
        lda #>irq
        sta irq_vec+1
        lda #0
        sta ticks
        sta count
        sta loops
        sta loops+1
        sta loops+2
        sta ORB             ; all LEDs off
        lda #$40
        sta ACR             ; T1 free-running
        lda #<PERIOD
        sta T1CL
        lda #>PERIOD
        sta T1CH            ; load and start
        lda #$C0            ; bit 7 = set, bit 6 = timer 1
        sta IER
        cli                 ; from here on the timer interrupts us
main:   inc loops           ; the main program does its own work:
        bne :+              ; a 24-bit count of its turns...
        inc loops+1
        bne :+
        inc loops+2
:       jsr GETKEY          ; ...and a look at the keyboard
        beq main
        sei                 ; a key: put everything back
        lda #$40
        sta IER             ; bit 7 = 0: clear the T1 enable
        lda old_vec
        sta irq_vec
        lda old_vec+1
        sta irq_vec+1
        cli
        rts                 ; back to the monitor

; Timer 1 interrupt: 200 times a second
irq:    pha
        lda T1CL            ; clear the flag, or IRQ stays low
        inc ticks
        lda ticks
        cmp #STEPS
        bne @out
        lda #0
        sta ticks
        inc count
        lda count
        sta ORB
@out:   pla
        rti
