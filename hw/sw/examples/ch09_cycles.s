; ch09_cycles.s - the 6502 times its own instructions
; VIA timer 2 counts down by one on every CPU cycle. We load it with
; $FFFF, call a short fragment of code, and read the low byte back.
; The empty fragment measures the cost of the harness itself; every
; other result is printed as (empty reading) - (reading).
; Build: ca65 ch09_cycles.s && ld65 -C ch09_ram.cfg -o ch09_cycles.bin
;        ch09_cycles.o, then load with L and run with G 0600.

        .setcpu "6502"

CHROUT  = $FF00             ; kernel: print the character in A
T2L     = $BF28             ; VIA timer 2 low byte (read = counter)
T2H     = $BF29             ; write: load the counter and start it

vec     = $F8               ; 2 bytes: the fragment being timed
tn      = $FA               ; its number
base    = $FB               ; timer reading for the empty fragment
num     = $FC               ; number to print
ptr     = $FD               ; 2 bytes: pointer to a name

NFRAG   = 16

        .segment "CODE"
start:  ldx #0
:       lda title,x         ; print the heading
        beq :+
        jsr CHROUT
        inx
        bne :-
:       lda #0
        sta tn
next:   jsr time            ; A = timer low byte after the fragment
        ldx tn
        bne :+
        sta base            ; fragment 0 is empty: it times the harness
:       sta num
        sec
        lda base
        sbc num             ; cycles = empty reading - this reading
        sta num
        jsr print_name
        jsr print_num
        lda #13
        jsr CHROUT
        lda #10
        jsr CHROUT
        inc tn
        lda tn
        cmp #NFRAG
        bne next
        rts                 ; back to the monitor

; time: run fragment tn with X from its table and Y = 0
time:   ldx tn
        lda frag_lo,x
        sta vec
        lda frag_hi,x
        sta vec+1
        ldy #0
        lda xval,x
        tax
        lda #$FF            ; also leaves Z = 0 and N = 1 for the branches
        sta T2L             ; latch the low byte
        sta T2H             ; counter = $FFFF, counting starts
        jsr call
        lda T2L             ; read the counter
        rts
call:   jmp (vec)

; print_name: print the name of fragment tn (padded to 16 characters)
print_name:
        ldx tn
        lda name_lo,x
        sta ptr
        lda name_hi,x
        sta ptr+1
        ldy #0
@loop:  lda (ptr),y         ; (zp),Y: the pointer lives in zero page
        beq @done
        jsr CHROUT
        iny
        bne @loop
@done:  rts

; print_num: print num (0-99) as two characters, a space for no tens
print_num:
        lda num
        ldy #'0'            ; Y counts the tens, in ASCII
@tens:  cmp #10
        bcc @ones
        sbc #10             ; carry is set, so this subtracts exactly 10
        iny
        bne @tens           ; always taken: Y is never zero
@ones:  pha                 ; keep the units
        tya
        cmp #'0'
        bne @put
        lda #' '            ; no tens: print a space instead
@put:   jsr CHROUT
        pla
        ora #'0'            ; 0-9 becomes '0'-'9'
        jmp CHROUT          ; CHROUT's RTS returns for us

; ------------------------------------------------------------------
; The fragments. Each one ends with RTS.
; ------------------------------------------------------------------
f_none: rts
f_nop:  nop
        rts
f_imm:  lda #$12
        rts
f_zp:   lda vec
        rts
f_abs:  lda $0300
        rts
f_absx: lda $0300,x         ; X = $10: stays in page 3
        rts
f_absxp:
        lda $03F8,x         ; X = $10: $0408 is in the next page
        rts
f_stax: sta $0300,x         ; a store always takes the extra cycle
        rts
f_indy: lda (vec),y
        rts
f_inc:  inc $0300
        rts
f_incx: inc $0300,x
        rts
f_beq:  beq :+              ; Z = 0: not taken
:       rts
f_bne:  bne :+              ; taken, same page
:       rts
f_loop: ldx #5
:       dex
        bne :-
        rts
f_jsr:  jsr f_none
        rts
f_stack:
        pha
        pla
        rts

        .segment "RODATA"
frag_lo: .lobytes f_none, f_nop, f_imm, f_zp, f_abs, f_absx, f_absxp
         .lobytes f_stax, f_indy, f_inc, f_incx, f_beq, f_bne, f_loop
         .lobytes f_jsr, f_stack
frag_hi: .hibytes f_none, f_nop, f_imm, f_zp, f_abs, f_absx, f_absxp
         .hibytes f_stax, f_indy, f_inc, f_incx, f_beq, f_bne, f_loop
         .hibytes f_jsr, f_stack
xval:   .byte 0, 0, 0, 0, 0, $10, $10, $10, 0, 0, $10, 0, 0, 0, 0, 0

title:  .byte 13, 10, "FRAGMENT        CYCLES", 13, 10, 0

name_lo: .lobytes n0, n1, n2, n3, n4, n5, n6, n7
         .lobytes n8, n9, n10, n11, n12, n13, n14, n15
name_hi: .hibytes n0, n1, n2, n3, n4, n5, n6, n7
         .hibytes n8, n9, n10, n11, n12, n13, n14, n15
n0:     .byte "(NOTHING)       ", 0
n1:     .byte "NOP             ", 0
n2:     .byte "LDA #$12        ", 0
n3:     .byte "LDA $F8         ", 0
n4:     .byte "LDA $0300       ", 0
n5:     .byte "LDA $0300,X     ", 0
n6:     .byte "LDA $03F8,X     ", 0
n7:     .byte "STA $0300,X     ", 0
n8:     .byte "LDA ($F8),Y     ", 0
n9:     .byte "INC $0300       ", 0
n10:    .byte "INC $0300,X     ", 0
n11:    .byte "BEQ (NOT TAKEN) ", 0
n12:    .byte "BNE (TAKEN)     ", 0
n13:    .byte "LDX #5 DEX BNE  ", 0
n14:    .byte "JSR + RTS       ", 0
n15:    .byte "PHA PLA         ", 0
