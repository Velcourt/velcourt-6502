; ch16_uart_rmw.s - what INC does to the UART data register at $BF00.
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
; Runs under examples/ch16_uart_rmw_tb.v, which puts "A" and "B" into the
; receive FIFO before the CPU starts.

        .org $0000
        .res $0600

start:  inc $BF00               ; read, write the old value, write the new one
idle:   lda $BF01               ; wait until the transmitter is free
        and #$02
        bne idle
        lda $BF01               ; status: bit 0 = a byte is still waiting
        sta $10
        lda $BF00               ; and that byte
        sta $11
done:   jmp done
