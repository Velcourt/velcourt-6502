; ch14_first.s - five instructions that each finish in two cycles.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Run from hw/sim:  sh examples/ch14_trace.sh ch14_first

        .org $0000
        .res $0600              ; pages 0-5: nothing here yet

start:  lda #$41                ; A = $41
        tax                     ; X = A = $41
        inx                     ; X = $42
        sec                     ; C = 1
        adc #$10                ; A = $41 + $10 + C = $52
done:   jmp done                ; the harness stops on this loop
