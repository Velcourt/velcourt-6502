; ch17_ticks.s - a timer interrupt handler: VIA timer 1 interrupts the
; main loop every 1,001 cycles, and the handler counts the ticks on the
; LEDs. This version brings its own vectors and runs on the CPU test
; bench sim/examples/ch17_irq_tb.v (cpu6502 + via + 64 KB of memory),
; which prints every bus cycle we ask for. ch17_timer.s is the version
; for the whole computer.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build and run (from hw/sim): sh examples/ch17_irq.sh
; NOACK=1 sh examples/ch17_irq.sh leaves out the acknowledge (Debug clinic).

        .setcpu "6502"

ORB     = $BF20             ; port B: the LEDs
DDRB    = $BF22
T1CL    = $BF24             ; read: clears the T1 flag
T1CH    = $BF25             ; write: load and start T1
ACR     = $BF2B
IER     = $BF2E
PERIOD  = 1000              ; an interrupt every PERIOD+1 cycles

        .segment "ZEROPAGE"
ticks:  .res 1              ; written by the handler
spins:  .res 2              ; written by the main loop

        .segment "CODE"
reset:  sei
        cld
        clv                 ; V is undefined after reset
        ldx #$FF
        txs
        lda #0
        sta ticks
        sta spins
        sta spins+1
        lda #$3F
        sta DDRB            ; LEDs are outputs
        lda #$40
        sta ACR             ; T1 free-running
        lda #<PERIOD
        sta T1CL
        lda #>PERIOD
        sta T1CH            ; start counting
        lda #$C0
        sta IER             ; enable the T1 interrupt
        cli
main:   inc spins           ; the "real work": count loop passes
        bne :+
        inc spins+1
:       lda ticks
        cmp #8
        bne main
        sei
done:   jmp done            ; the test bench stops here

; ---- the interrupt handler ----
irq:    pha                 ; save what we use
.ifndef NOACK
        lda T1CL            ; acknowledge: clears the T1 flag
.endif
        inc ticks
        lda ticks
        sta ORB             ; show the count on the LEDs
        pla
        rti

nmi:    rti

        .segment "VECTORS"
        .word nmi           ; $FFFA
        .word reset         ; $FFFC
        .word irq           ; $FFFE
