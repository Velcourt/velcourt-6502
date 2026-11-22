; appD_timer.s - installing an IRQ handler through irq_vec (Appendix D)
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; Build: ca65 -l appD_timer.lst appD_timer.s
;        ld65 -C ch09_ram.cfg -o appD_timer.bin appD_timer.o
; Load with L, run with G 0600. The handler keeps running after the
; program returns to the monitor: D 00F1 00F1 shows the count growing.

        .setcpu "6502"

irq_vec = $02F0             ; the kernel's IRQ/BRK vector in RAM
VIA_ORB = $BF20             ; LEDs on bits 0-5
VIA_DDRB = $BF22
T1CL    = $BF24             ; reading it clears the T1 flag
T1CH    = $BF25
VIA_ACR = $BF2B
VIA_IER = $BF2E
count   = $F1               ; free zero-page byte

        .segment "CODE"
start:  sei                 ; no interrupts while the vector changes
        lda #<handler
        sta irq_vec
        lda #>handler
        sta irq_vec+1
        lda #0
        sta count
        lda #$3F            ; six LEDs are outputs
        sta VIA_DDRB
        lda #$40            ; timer 1 free-running
        sta VIA_ACR
        lda #<62999         ; every 63,000 cycles: 200 per second
        sta T1CL
        lda #>62999
        sta T1CH            ; load and start
        lda #$C0            ; enable the T1 interrupt (bit 7 = set)
        sta VIA_IER
        cli
        rts                 ; back to the monitor; the timer keeps going

handler:
        pha
        lda T1CL            ; clear the cause first: IRQ is level-triggered
        inc count
        lda count
        sta VIA_ORB         ; show the count on the LEDs
        pla
        rti
