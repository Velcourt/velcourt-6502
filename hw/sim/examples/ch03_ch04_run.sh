#!/bin/sh
# ch03_ch04_run.sh - build and run every test bench of chapters 3 and 4.
# Run from hw/sim:  sh examples/ch03_ch04_run.sh
R=../rtl
SOC="$R/soc.v $R/cpu6502.v $R/alu6502.v $R/video.v $R/uart.v $R/ps2_kbd.v $R/spi_sd.v $R/via.v $R/sound.v"
set -x
iverilog -o out/ch03_fa.vvp examples/ch03_fulladd.v examples/ch03_fulladd_tb.v && vvp out/ch03_fa.vvp
iverilog -o out/ch03_r4.vvp examples/ch03_fulladd.v examples/ch03_ripple4_tb.v && vvp out/ch03_r4.vvp
iverilog -DBUG -o out/ch03_r4bug.vvp examples/ch03_fulladd.v examples/ch03_ripple4_tb.v && vvp out/ch03_r4bug.vvp
iverilog -o out/ch03_decode.vvp examples/ch03_decode_tb.v $SOC && vvp out/ch03_decode.vvp
iverilog -o out/ch03_alu_add.vvp examples/ch03_alu_add_tb.v $R/alu6502.v && vvp out/ch03_alu_add.vvp
iverilog -o out/ch04_blocking.vvp examples/ch04_blocking_tb.v && vvp out/ch04_blocking.vvp
iverilog -o out/ch04_video_count.vvp examples/ch04_video_count_tb.v $R/video.v && vvp out/ch04_video_count.vvp
iverilog -o out/ch04_uart_rx.vvp examples/ch04_uart_rx_tb.v $R/uart.v && vvp out/ch04_uart_rx.vvp
iverilog -o out/ch04_ce.vvp examples/ch04_ce_tb.v $SOC && vvp out/ch04_ce.vvp
iverilog -o out/ch04_debounce.vvp examples/ch04_debounce_tb.v $SOC && vvp out/ch04_debounce.vvp
iverilog -DNO_INIT -o out/ch04_debounce_x.vvp examples/ch04_debounce_tb.v $SOC && vvp out/ch04_debounce_x.vvp
