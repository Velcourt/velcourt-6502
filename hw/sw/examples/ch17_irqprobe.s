; ch17_irqprobe.s - what BRK, IRQ and NMI leave behind on the stack.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
;
; We leave irq_vec and nmi_vec as the kernel set them, pointing at an
; RTI, so the interrupt itself is all we watch. Each interrupt pushes
; three bytes below the stack pointer and RTI pulls them again, but
; the bytes stay in memory. We read them back after the return.
;
; Build: ca65 ch17_irqprobe.s
;        ld65 -C ch09_ram.cfg -o ch17_irqprobe.bin ch17_irqprobe.o
; Load with L, run with G 0600, press S2 when asked, then D 0700 070F.
;
; Results (each frame is P, return low, return high):
;   $0700-$0702  frame pushed by BRK
;   $0703-$0705  frame pushed by the VIA timer IRQ after CLI, SEI
;   $0706        timer 2 low byte after CLI, SEI with the IRQ line low
;   $0707        timer 2 low byte after CLI, SEI with the IRQ line high
;   $0708-$070A  frame pushed by NMI (button S2) while I = 1

        .setcpu "6502"

CHROUT  = $FF00
T1CL    = $BF24             ; read: T1 counter low, clears the T1 flag
T1CH    = $BF25             ; write: load T1 from the latch and start it
T2L     = $BF28             ; read: T2 counter low
T2H     = $BF29             ; write: load T2 and start it
ACR     = $BF2B             ; bit 6 = 1: T1 free-running
IFR     = $BF2D             ; bit 7: some enabled flag is set
IER     = $BF2E             ; write bit 7 = 1 to set, 0 to clear
RES     = $0700

; copy the three bytes below the stack pointer saved in X
.macro  grab dst
        lda a:$00FE,x       ; P (a: = absolute, see text)
        sta dst
        lda a:$00FF,x       ; return address, low byte
        sta dst+1
        lda $0100,x         ; return address, high byte
        sta dst+2
.endmacro

        .segment "CODE"
start:
; ---- 1: BRK -------------------------------------------------------
        tsx
        brk
        .byte $EA           ; signature byte: RTI returns past it
        grab RES

; ---- 2: one IRQ from timer 1, let in by CLI then SEI --------------
        lda #$7F
        sta IER             ; every VIA interrupt off
        lda #0
        sta ACR             ; T1 one-shot
        lda #$C0
        sta IER             ; T1 interrupt on
        lda #100
        sta T1CL            ; latch low byte
        lda #0
        sta T1CH            ; load the counter and start
wait:   bit IFR
        bpl wait            ; N = IFR bit 7: the VIA pulls IRQ low now
        tsx
        cli
        sei                 ; the interrupt arrives after this SEI
        grab RES+3

; ---- 3: the cost of an interrupt -----------------------------------
        jsr block           ; T1 flag still set: one IRQ gets in
        sta RES+6
        lda T1CL            ; reading T1 low clears the flag
        jsr block           ; IRQ line high now: no interrupt
        sta RES+7
        lda #$7F
        sta IER             ; VIA interrupts off again

; ---- 4: NMI from the S2 button, with I = 1 -------------------------
        ldx #0
msg:    lda prompt,x
        beq :+
        jsr CHROUT
        inx
        bne msg
:       tsx
        lda #0
        sta a:$00FE,x       ; clear the three bytes below S
        sta a:$00FF,x
        sta $0100,x
spin:   lda a:$00FE,x       ; until an NMI writes P there
        beq spin
        grab RES+8
        rts                 ; back to the monitor

; block: time CLI, SEI with timer 2
block:  lda #$FF
        sta T2L
        sta T2H             ; T2 = $FFFF, counting down
        cli
        sei
        lda T2L
        rts

prompt: .byte "PRESS S2", 13, 10, 0
