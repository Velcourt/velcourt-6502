; kernel.s - the Velcourt kernel: screen, keyboards, SD card, files,
;            graphics, sound and a machine-code monitor.
;
; Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
; License: MIT
;
; The kernel lives at $E100-$FFFF, just above BASIC ($C000-$E0FF).
; Programs reach it through the jump table at $FF00, whose addresses
; never change, so BASIC and your own programs keep working when the
; kernel grows.

        .setcpu "6502"
        .include "basic_syms.inc"

; ------------------------------------------------------------------
; Hardware
; ------------------------------------------------------------------
SCREEN     = $4000          ; 320 x 200, two pixels per byte
UART_DATA  = $BF00
UART_STAT  = $BF01          ; bit0 byte waiting, bit1 sending
KBD_DATA   = $BF10
KBD_STAT   = $BF11          ; bit0 scan code waiting
VIA_ORB    = $BF20          ; LEDs on bits 0-5
VIA_ORA    = $BF21          ; button on bit 0
VIA_DDRB   = $BF22
VIA_DDRA   = $BF23
SPI_DATA   = $BF30
SPI_CTRL   = $BF31          ; write: bit0 select, bit1 fast. read: bit0 busy
SND        = $BF40
VID_BORDER = $BF50
VID_STATUS = $BF51          ; bit0 = outside the picture (once per frame)

; ------------------------------------------------------------------
; Memory used by the kernel
; ------------------------------------------------------------------
; Zero page $E0-$F0 (BASIC uses $00-$DE and $FF; $F1-$FE are free)
p0      = $E0               ; pointers
p1      = $E2
p2      = $E4               ; SD transfer address
p3      = $E6
t0      = $E8               ; scratch
t1      = $E9
t2      = $EA
t3      = $EB
kchar   = $EC
mp      = $ED               ; monitor address (the screen driver uses p0/p1)
pd      = $EF               ; number being printed by print_dec

; Page 2
cur_x   = $0200             ; text cursor, 0-39 (40 = wrap pending)
cur_y   = $0201             ; 0-24
fg      = $0202             ; ink colour
bg      = $0203             ; paper colour
pat     = $0204             ; 4 bytes: two-pixel patterns for the font
kbflags = $0208             ; keyboard state, see KB_ bits below
sd_hc   = $0209             ; nonzero: card uses block addresses (SDHC)
sd_spd  = $020A             ; 0 slow, 2 fast
sd_ok   = $020B             ; nonzero once the card has been set up
sd_lba  = $020C             ; 4 bytes, sector number, low byte first
sd_arg  = $0210             ; 4 bytes, command argument, high byte first
blink   = $0214             ; frame counter for the cursor
cur_on  = $0215             ; cursor currently drawn
vb_old  = $0216
fname   = $0218             ; 12 bytes, file name padded with spaces
fs_end  = $0224             ; 2 bytes
fs_len  = $0226             ; 2 bytes
fs_ent  = $0228             ; directory entry number
fs_cnt  = $0229             ; sectors left
L_dx    = $0230             ; LINE working storage
L_dy    = $0232
L_err   = $0234
L_e2    = $0236
L_sx    = $0238
L_sy    = $0239
hexval  = $023A             ; 2 bytes, monitor
hexsum  = $023C
rst_btn = $023D             ; S2 was held at reset
kb_head = $023E             ; type-ahead buffer: next to read
kb_tail = $023F             ;                    next free place
kbuf    = $0240             ; 64 keys, $0240-$027F

; Parameter block shared with BASIC (fixed addresses)
GX0     = $0280             ; 2 bytes, x (0-319)
GY0     = $0282             ; y (0-199)
GX1     = $0283             ; 2 bytes
GY1     = $0285
GCOL    = $0286             ; colour 0-15
SVOICE  = $0287             ; voice 0-2, or 3 for noise
SFREQ   = $0288             ; 2 bytes, frequency in Hz
SVOL    = $028A             ; volume 0-15
PTICKS  = $028B             ; sixtieths of a second
CFG     = $028C             ; ink
CBG     = $028D             ; paper

LBUF    = $0290             ; monitor input line, 64 bytes
nib0    = $02D0             ; 16 bytes: left two pixels of a 4-pixel nibble
nib1    = $02E0             ; 16 bytes: right two pixels
irq_vec = $02F0             ; 2 bytes: where IRQ and BRK go (your handler)
nmi_vec = $02F2             ; 2 bytes: where NMI goes
SDBUF   = $0300             ; one 512-byte sector, $0300-$04FF

KB_SHIFT = $01
KB_CTRL  = $02
KB_REL   = $04
KB_EXT   = $08

DIR_MAGIC_LEN = 8
SLOT_SECTORS  = 64          ; 32 KB per file

        .segment "CODE"

; ==================================================================
; Reset
; ==================================================================
reset:
        sei
        cld
        ldx #$FF
        txs
        lda VIA_ORA         ; is S2 held? (read it before anything else)
        and #1
        sta rst_btn
        lda #<int_return    ; interrupts do nothing until a program
        sta irq_vec         ; installs its own handler in irq_vec/nmi_vec
        sta nmi_vec
        lda #>int_return
        sta irq_vec+1
        sta nmi_vec+1
        lda #$3F
        sta VIA_DDRB        ; six LEDs are outputs
        lda #0
        sta VIA_ORB
        sta VIA_DDRA        ; the button is an input
        sta kbflags
        sta sd_ok
        sta cur_on
        sta kb_head
        sta kb_tail
        ldx #13             ; all voices silent
@snd:   sta SND,x
        dex
        bpl @snd
        lda #1
        sta fg
        sta CFG
        lda #6
        sta bg
        sta CBG
        sta VID_BORDER
        jsr set_colors
        jsr cls
        lda #<msg_hello
        ldy #>msg_hello
        jsr kprint
        lda rst_btn         ; S2 held at reset? then the monitor
        beq @basic
        jmp monitor
@basic: jmp BASIC_INIT

msg_hello:
        .byte "VELCOURT 6502 COMPUTER", 13, 10
        .byte "HOLD S2 AT RESET FOR THE MONITOR", 13, 10, 13, 10, 0

; Interrupts jump through vectors in RAM, so a program can install its
; own handler: store its address in irq_vec (IRQ and BRK) or nmi_vec
; (NMI, the S2 button) and end the handler with RTI. Until then they
; just return. IRQ is level-triggered: a handler must clear the cause
; (for example by reading the VIA's T1 low counter) before RTI.
nmi:    jmp (nmi_vec)
irq:    jmp (irq_vec)
int_return:
        rti

; ==================================================================
; Character output: to the serial port and to the screen
; ==================================================================
; CHROUT: print the character in A. Keeps A, X and Y.
; Like a Teletype, it ignores bit 7: BASIC 1.1 marks the end of its
; two-letter error codes that way ("?SN ERROR").
chrout:
        pha
        and #$7F
        sta kchar
        txa
        pha
        tya
        pha
        lda kchar
        jsr uart_put
        jsr scr_put
        pla
        tay
        pla
        tax
        pla
        rts

uart_put:
        pha
@wait:  lda UART_STAT
        and #2
        bne @wait
        pla
        sta UART_DATA
        rts

; kprint: print the zero-terminated string at A (low) / Y (high)
kprint:
        sta p3
        sty p3+1
        ldy #0
@loop:  lda (p3),y
        beq @done
        jsr chrout
        iny
        bne @loop
@done:  rts

; ------------------------------------------------------------------
; The screen: 40 x 25 characters drawn into the framebuffer
; ------------------------------------------------------------------
scr_put:
        cmp #13
        beq newline
        cmp #8
        beq @bs
        cmp #12
        bne :+
        jmp cls
:       cmp #7
        bne :+
        jmp beep
:       cmp #32
        bcc @rts
        cmp #127
        bcs @rts
        ldx cur_x
        cpx #40
        bcc @draw
        pha                 ; a character after column 39: wrap first
        jsr newline
        pla
@draw:  jsr draw_char
        inc cur_x
@rts:   rts
@bs:    lda cur_x
        beq @rts
        cmp #40
        bcc @back
        lda #39             ; wrap pending: step onto the last column
        sta cur_x
@back:  dec cur_x
        lda #' '
        jmp draw_char

newline:
        lda #0
        sta cur_x
        inc cur_y
        lda cur_y
        cmp #25
        bcc @done
        dec cur_y
        jmp scroll
@done:  rts

; draw_char: draw character A at (cur_x, cur_y). Uses A, X, Y.
draw_char:
        sec
        sbc #32             ; the font starts at the space
        sta p1
        lda #0
        sta p1+1
        asl p1              ; x 8 bytes per glyph
        rol p1+1
        asl p1
        rol p1+1
        asl p1
        rol p1+1
        clc
        lda p1
        adc #<font
        sta p1
        lda p1+1
        adc #>font
        sta p1+1
        jsr cell_addr       ; p0 = top-left byte of the cell
        lda #0
        sta t0              ; glyph row 0..7
@row:   ldy t0
        lda (p1),y          ; one row of the glyph: 8 pixels
        sta t1
        lsr a               ; left nibble: 4 pixels = 2 bytes
        lsr a
        lsr a
        lsr a
        tax
        ldy #0
        lda nib0,x
        sta (p0),y
        iny
        lda nib1,x
        sta (p0),y
        iny
        lda t1              ; right nibble: 2 more bytes
        and #$0F
        tax
        lda nib0,x
        sta (p0),y
        iny
        lda nib1,x
        sta (p0),y
        clc                 ; next screen line: 160 bytes further on
        lda p0
        adc #160
        sta p0
        bcc :+
        inc p0+1
:       inc t0
        lda t0
        cmp #8
        bne @row
        rts

; cell_addr: p0 = address of the top-left byte of text cell (cur_x, cur_y)
cell_addr:
        ldx cur_y
        lda trow_lo,x
        sta p0
        lda trow_hi,x
        sta p0+1
        lda cur_x
        asl a               ; 4 bytes per character
        asl a
        clc
        adc p0
        sta p0
        bcc :+
        inc p0+1
:       rts

; set_colors: build the four two-pixel patterns from fg and bg
set_colors:
        lda bg
        asl a
        asl a
        asl a
        asl a
        sta t0              ; bg in the high nibble
        ora bg
        sta pat+0           ; paper paper
        lda t0
        ora fg
        sta pat+1           ; paper ink
        lda fg
        asl a
        asl a
        asl a
        asl a
        sta t0              ; fg in the high nibble
        ora bg
        sta pat+2           ; ink paper
        lda t0
        ora fg
        sta pat+3           ; ink ink
        ldx #15             ; nibble b3 b2 b1 b0 -> two bytes:
@nib:   txa                 ;   nib0 = pattern for b3 b2, nib1 = for b1 b0
        lsr a
        lsr a
        tay
        lda pat,y
        sta nib0,x
        txa
        and #3
        tay
        lda pat,y
        sta nib1,x
        dex
        bpl @nib
        rts

; cls: fill the picture with the paper colour, cursor home
cls:
        lda #<SCREEN
        sta p0
        lda #>SCREEN
        sta p0+1
        lda pat
        ldx #125            ; 125 pages = 32000 bytes
        ldy #0
@loop:  sta (p0),y
        iny
        bne @loop
        inc p0+1
        dex
        bne @loop
        lda #0
        sta cur_x
        sta cur_y
        rts

; scroll: move text rows 1-24 up one row, clear the bottom row
scroll:
        lda #0
        sta p0
        sta p1
        lda #>SCREEN        ; to   $4000
        sta p0+1
        lda #>SCREEN+5      ; from $4500 (one text row = 1280 bytes)
        sta p1+1
        ldx #120            ; 24 rows x 1280 = 120 pages
        ldy #0
@copy:  lda (p1),y
        sta (p0),y
        iny
        bne @copy
        inc p0+1
        inc p1+1
        dex
        bne @copy
        lda pat             ; p0 is now $B800: clear the last row
        ldx #5
@clr:   sta (p0),y
        iny
        bne @clr
        inc p0+1
        dex
        bne @clr
        rts

; cursor: swap ink and paper in the cursor cell (doing it twice undoes it)
cursor_flip:
        lda cur_x
        cmp #40
        bcs @rts
        jsr cell_addr
        lda fg
        eor bg
        sta t0
        asl a
        asl a
        asl a
        asl a
        ora t0
        sta t0              ; (fg^bg) in both nibbles
        ldx #8
@row:   ldy #3
@col:   lda (p0),y
        eor t0
        sta (p0),y
        dey
        bpl @col
        clc
        lda p0
        adc #160
        sta p0
        bcc :+
        inc p0+1
:       dex
        bne @row
        lda cur_on
        eor #1
        sta cur_on
@rts:   rts

cursor_off:
        lda cur_on
        beq @rts
        jmp cursor_flip
@rts:   rts

; called while waiting for a key: blink every 20 frames
cursor_poll:
        lda VID_STATUS
        and #1
        cmp vb_old
        beq @rts
        sta vb_old
        cmp #1              ; a new frame starts when the flag goes to 1
        bne @rts
        inc blink
        lda blink
        cmp #20
        bcc @rts
        lda #0
        sta blink
        jmp cursor_flip
@rts:   rts

; ==================================================================
; Keyboard input: PS/2 keyboard and the serial port
; ==================================================================
; GETKEY: A = next character, or 0 (Z set) if none. Keeps X and Y.
getkey:
        txa
        pha
        tya
        pha
        jsr key_raw
        sta kchar
        pla
        tay
        pla
        tax
        lda kchar
        rts

; CHRIN: wait for a character and echo it, like a terminal would.
; Return is not echoed (BASIC prints the new line itself).
; Backspace erases on screen and is passed to BASIC as "_", which is
; how BASIC 1.1 deletes a character.
chrin:
        txa
        pha
        tya
        pha
@wait:  jsr cursor_poll
        jsr key_raw
        beq @wait
        sta kchar
        jsr cursor_off
        lda kchar
        cmp #127
        beq @bs
        cmp #8
        bne @nbs
@bs:    lda #8              ; erase: back, space, back on the terminal
        jsr uart_put
        lda #' '
        jsr uart_put
        lda #8
        jsr uart_put
        lda #8
        jsr scr_put
        lda #'_'
        sta kchar
        bne @done
@nbs:   cmp #32
        bcc @done           ; control characters are not echoed
        jsr chrout
@done:  pla
        tay
        pla
        tax
        lda kchar
        rts

; key_raw: one character, letters in capitals, A = 0 if none. Keys kept
; in the type-ahead buffer come first. Uses X, Y.
key_raw:
        ldx kb_head
        cpx kb_tail
        beq key_hw
        inx
        txa
        and #63
        sta kb_head
        lda kbuf-1,x        ; (X was head+1)
        rts

; STOPKEY: has Ctrl-C been pressed? A = 3 if so, else 0. Any other key
; goes into the 64-key type-ahead buffer so that it is not lost.
; Keeps X and Y.
; BASIC calls this between statements.
stopkey:
        txa
        pha
        tya
        pha
        lda kb_tail         ; buffer full? then leave keys in the
        clc                 ; keyboard's own FIFO for now
        adc #1
        and #63
        cmp kb_head
        beq @none
        jsr key_hw
        beq @done
        cmp #3
        beq @done
        ldx kb_tail         ; keep it for later
        sta kbuf,x
        inx
        txa
        and #63
        sta kb_tail
@none:  lda #0
@done:  sta kchar
        pla
        tay
        pla
        tax
        lda kchar
        rts

; key_hw: one character straight from the keyboards (see key_raw)
key_hw:
@kb:    lda KBD_STAT
        lsr a
        bcc @uart
        lda KBD_DATA
        jsr ps2_decode
        beq @kb             ; a code that makes no character
        bne @have
@uart:  lda UART_STAT
        lsr a
        bcc @none
        lda UART_DATA
        cmp #10             ; terminals that send CR LF: drop the LF
        beq @none
@have:  cmp #'a'
        bcc @ok
        cmp #'z'+1
        bcs @ok
        and #$DF            ; a-z to A-Z
@ok:    ora #0              ; set Z from A
        rts
@none:  lda #0
        rts

; ps2_decode: A = scan code in, A = character out (0 if none)
ps2_decode:
        cmp #$F0            ; the next code is a key being released
        bne @n1
        lda kbflags
        ora #KB_REL
        sta kbflags
        lda #0
        rts
@n1:    cmp #$E0            ; the next code is an extended key
        bne @n2
        lda kbflags
        ora #KB_EXT
        sta kbflags
        lda #0
        rts
@n2:    tax
        lda kbflags
        and #KB_REL
        beq @press
        lda kbflags         ; a release: only Shift and Ctrl matter
        and #<~(KB_REL|KB_EXT)
        sta kbflags
        cpx #$12
        beq @shoff
        cpx #$59
        beq @shoff
        cpx #$14
        beq @ctoff
        lda #0
        rts
@shoff: lda kbflags
        and #<~KB_SHIFT
        sta kbflags
        lda #0
        rts
@ctoff: lda kbflags
        and #<~KB_CTRL
        sta kbflags
        lda #0
        rts
@press: lda kbflags
        and #KB_EXT
        sta t0
        lda kbflags
        and #<~KB_EXT
        sta kbflags
        cpx #$12
        beq @shon
        cpx #$59
        beq @shon
        cpx #$14
        beq @cton
        lda t0
        beq @normal
        cpx #$4A            ; extended keys we use: keypad / and Enter
        bne @e1
        lda #'/'
        rts
@e1:    cpx #$5A
        bne @e2
        lda #13
        rts
@e2:    cpx #$71            ; Delete
        bne @zero
        lda #8
        rts
@shon:  lda kbflags
        ora #KB_SHIFT
        sta kbflags
        lda #0
        rts
@cton:  lda kbflags
        ora #KB_CTRL
        sta kbflags
        lda #0
        rts
@normal:
        cpx #$80
        bcs @zero
        lda kbflags
        and #KB_SHIFT
        bne @sh
        lda ps2_lo,x
        jmp @ctl
@sh:    lda ps2_hi,x
@ctl:   beq @rts
        sta t1
        lda kbflags
        and #KB_CTRL
        beq @plain
        lda t1
        and #$1F            ; Ctrl-letter: 1 to 26 (Ctrl-C = 3)
        rts
@plain: lda t1
        rts
@zero:  lda #0
@rts:   rts

; ==================================================================
; Waiting and sound
; ==================================================================
; wait_frames: wait A frames (sixtieths of a second), A=0 means 256
wait_frames:
        sta t3
@f:     lda VID_STATUS      ; wait while the flag is 1...
        lsr a
        bcs @f
@g:     lda VID_STATUS      ; ...then until it becomes 1 again
        lsr a
        bcc @g
        dec t3
        bne @f
        rts

beep:
        lda #<1172          ; 880 Hz: 880 x 65536 / 49219
        sta SND+0
        lda #>1172
        sta SND+1
        lda #10
        sta SND+2
        lda #6
        jsr wait_frames
        lda #0
        sta SND+2
        rts

; KSOUND: voice SVOICE, frequency SFREQ (Hz), volume SVOL
; step = Hz x 65536 / 49219 = Hz x 1.3315, done as
; Hz + Hz/4 + Hz/16 + Hz/64 + Hz/256 (= Hz x 1.3320).
ksound:
        lda SFREQ
        sta p0
        sta p1
        lda SFREQ+1
        sta p0+1
        sta p1+1            ; p0 = running total, p1 = Hz shifted
        ldx #4
@term:  lsr p1+1            ; p1 = p1 / 4
        ror p1
        lsr p1+1
        ror p1
        clc
        lda p0
        adc p1
        sta p0
        lda p0+1
        adc p1+1
        sta p0+1
        dex
        bne @term
        lda SVOICE
        cmp #3
        beq @noise
        bcs @rts
        asl a
        asl a
        tax                 ; voice registers are 4 apart
        lda p0
        sta SND,x
        lda p0+1
        sta SND+1,x
        lda SVOL
        sta SND+2,x
@rts:   rts
@noise: lda SFREQ           ; noise: the low byte is the rate
        sta SND+12
        lda SVOL
        sta SND+13
        rts

kpause:
        lda PTICKS
        beq @rts
        jmp wait_frames
@rts:   rts

; ==================================================================
; Graphics for BASIC: COLOR, PLOT, LINE
; ==================================================================
kcolor:
        lda CFG
        and #15
        sta fg
        lda CBG
        and #15
        sta bg
        jmp set_colors

; KPLOT: pixel (GX0, GY0) in colour GCOL. Off-screen points are ignored.
kplot:
        lda GY0
        cmp #200
        bcs @rts
        lda GX0+1
        beq @xok
        cmp #1
        bne @rts
        lda GX0
        cmp #64             ; 320 = $140
        bcs @rts
@xok:   ldx GY0
        lda prow_lo,x
        sta p0
        lda prow_hi,x
        sta p0+1
        lda GX0+1
        lsr a
        lda GX0
        ror a               ; byte = x / 2
        tay
        lda GX0
        lsr a
        bcs @right
        lda (p0),y          ; left pixel: the high nibble
        and #$0F
        sta t0
        lda GCOL
        asl a
        asl a
        asl a
        asl a
        ora t0
        sta (p0),y
        rts
@right: lda (p0),y          ; right pixel: the low nibble
        and #$F0
        sta t0
        lda GCOL
        and #$0F
        ora t0
        sta (p0),y
@rts:   rts

; KLINE: from (GX0,GY0) to (GX1,GY1) in colour GCOL, Bresenham's method.
;   dx = |x1-x0|, dy = -|y1-y0|, err = dx+dy
;   loop: plot; stop at the end;
;         e2 = 2 err; if e2 >= dy: err += dy, x += sx
;                     if e2 <= dx: err += dx, y += sy
kline:
        lda #0
        sta L_sx
        sta L_sy
        sec
        lda GX1
        sbc GX0
        sta L_dx
        lda GX1+1
        sbc GX0+1
        sta L_dx+1
        bpl @dxok
        inc L_sx            ; going left
        sec
        lda #0
        sbc L_dx
        sta L_dx
        lda #0
        sbc L_dx+1
        sta L_dx+1
@dxok:  sec
        lda GY1
        sbc GY0
        bcs @dyok
        inc L_sy            ; going up
        lda GY0
        sec
        sbc GY1
@dyok:  eor #$FF            ; L_dy = -|dy|
        clc
        adc #1
        sta L_dy
        lda #$FF
        adc #0
        sta L_dy+1
        clc
        lda L_dx
        adc L_dy
        sta L_err
        lda L_dx+1
        adc L_dy+1
        sta L_err+1
@loop:  jsr kplot
        lda GX0
        cmp GX1
        bne @go
        lda GX0+1
        cmp GX1+1
        bne @go
        lda GY0
        cmp GY1
        bne @go
        rts
@go:    lda L_err
        asl a
        sta L_e2
        lda L_err+1
        rol a
        sta L_e2+1
        sec                 ; e2 >= dy ?  (signed)
        lda L_e2
        sbc L_dy
        lda L_e2+1
        sbc L_dy+1
        bvc :+
        eor #$80
:       bmi @noxs
        clc
        lda L_err
        adc L_dy
        sta L_err
        lda L_err+1
        adc L_dy+1
        sta L_err+1
        lda L_sx
        bne @left
        inc GX0
        bne @noxs
        inc GX0+1
        jmp @noxs
@left:  lda GX0
        bne :+
        dec GX0+1
:       dec GX0
@noxs:  sec                 ; e2 <= dx ?  i.e. dx - e2 >= 0 (signed)
        lda L_dx
        sbc L_e2
        lda L_dx+1
        sbc L_e2+1
        bvc :+
        eor #$80
:       bmi @loop
        clc
        lda L_err
        adc L_dx
        sta L_err
        lda L_err+1
        adc L_dx+1
        sta L_err+1
        lda L_sy
        bne @up
        inc GY0
        jmp @loop
@up:    dec GY0
        jmp @loop

; ==================================================================
; SD card over SPI
; ==================================================================
; spi_xfer: send A, return the byte received in A. Keeps X and Y.
spi_xfer:
        sta SPI_DATA
@wait:  lda SPI_CTRL
        lsr a
        bcs @wait
        lda SPI_DATA
        rts

sd_select:
        lda sd_spd
        ora #1
        sta SPI_CTRL
        rts

sd_deselect:
        lda sd_spd
        sta SPI_CTRL
        lda #$FF            ; eight more clocks let the card let go of MISO
        jmp spi_xfer

arg0:   lda #0
        sta sd_arg
        sta sd_arg+1
        sta sd_arg+2
        sta sd_arg+3
        rts

; sd_cmd: command A, argument sd_arg, CRC X. Returns the R1 answer in A
; ($FF if the card never answered). The card stays selected.
sd_cmd:
        sta t0
        stx t1
        jsr sd_select
        lda #$FF
        jsr spi_xfer
        lda t0
        ora #$40
        jsr spi_xfer
        lda sd_arg
        jsr spi_xfer
        lda sd_arg+1
        jsr spi_xfer
        lda sd_arg+2
        jsr spi_xfer
        lda sd_arg+3
        jsr spi_xfer
        lda t1
        jsr spi_xfer
        ldx #16
@r:     lda #$FF
        jsr spi_xfer
        bpl @got            ; the answer has bit 7 clear
        dex
        bne @r
@got:   rts

; sd_init: wake the card up. Carry clear on success.
sd_init:
        lda #0
        sta sd_spd
        sta sd_hc
        sta sd_ok
        sta SPI_CTRL        ; deselected, slow clock
        ldx #10
@pre:   lda #$FF            ; at least 74 clocks with the card deselected
        jsr spi_xfer
        dex
        bne @pre
        jsr arg0
        lda #0              ; CMD0: go to the idle state
        ldx #$95
        jsr sd_cmd
        cmp #1
        beq :+
        jmp @fail
:       jsr sd_deselect
        lda #1              ; CMD8: which voltages? (version 2 cards only)
        sta sd_arg+2
        lda #$AA
        sta sd_arg+3
        lda #8
        ldx #$87
        jsr sd_cmd
        sta t2              ; 1 = version 2 card, otherwise version 1
        ldx #4
@r7:    lda #$FF
        jsr spi_xfer
        dex
        bne @r7
        lda #8
        sta t3              ; about a second of tries
        ldy #0
@acmd:  jsr sd_deselect
        jsr arg0
        lda #55             ; CMD55: the next command is an application one
        ldx #1
        jsr sd_cmd
        jsr sd_deselect
        jsr arg0
        lda t2
        cmp #1
        bne @v1
        lda #$40            ; we can handle high-capacity cards
        sta sd_arg
@v1:    lda #41             ; ACMD41: start up
        ldx #1
        jsr sd_cmd
        beq @ready          ; 0 = ready
        dey
        bne @acmd
        dec t3
        bne @acmd
        beq @fail
@ready: jsr sd_deselect
        lda t2
        cmp #1
        bne @blk
        jsr arg0
        lda #58             ; CMD58: read OCR; bit 30 = block addressing
        ldx #1
        jsr sd_cmd
        lda #$FF
        jsr spi_xfer
        and #$40
        sta sd_hc
        ldx #3
@ocr:   lda #$FF
        jsr spi_xfer
        dex
        bne @ocr
        jsr sd_deselect
@blk:   lda sd_hc
        bne @ok
        jsr arg0
        lda #2              ; CMD16: blocks of 512 bytes
        sta sd_arg+2
        lda #16
        ldx #1
        jsr sd_cmd
        jsr sd_deselect
@ok:    lda #2
        sta sd_spd          ; full speed from now on
        lda #1
        sta sd_ok
        clc
        rts
@fail:  jsr sd_deselect
        sec
        rts

; sd_setaddr: sd_lba -> sd_arg (bytes for old cards, blocks for SDHC)
sd_setaddr:
        lda sd_hc
        beq @bytes
        lda sd_lba+3
        sta sd_arg
        lda sd_lba+2
        sta sd_arg+1
        lda sd_lba+1
        sta sd_arg+2
        lda sd_lba
        sta sd_arg+3
        rts
@bytes: lda sd_lba          ; byte address = sector x 512
        asl a
        sta sd_arg+2
        lda sd_lba+1
        rol a
        sta sd_arg+1
        lda sd_lba+2
        rol a
        sta sd_arg
        lda #0
        sta sd_arg+3
        rts

; sd_read: sector sd_lba into 512 bytes at p2. Carry set on error.
sd_read:
        jsr sd_setaddr
        lda #17             ; CMD17: read one block
        ldx #1
        jsr sd_cmd
        bne @fail
        lda #8
        sta t3
        ldx #0
@tok:   lda #$FF            ; wait for the start token $FE
        jsr spi_xfer
        cmp #$FE
        beq @data
        dex
        bne @tok
        dec t3
        bne @tok
        beq @fail
@data:  ldy #0
@b1:    lda #$FF
        jsr spi_xfer
        sta (p2),y
        iny
        bne @b1
        inc p2+1
@b2:    lda #$FF
        jsr spi_xfer
        sta (p2),y
        iny
        bne @b2
        dec p2+1
        lda #$FF            ; two CRC bytes, ignored
        jsr spi_xfer
        lda #$FF
        jsr spi_xfer
        jsr sd_deselect
        clc
        rts
@fail:  jsr sd_deselect
        sec
        rts

; sd_write: 512 bytes from p2 to sector sd_lba. Carry set on error.
sd_write:
        jsr sd_setaddr
        lda #24             ; CMD24: write one block
        ldx #1
        jsr sd_cmd
        bne @fail
        lda #$FF
        jsr spi_xfer
        lda #$FE            ; start token
        jsr spi_xfer
        ldy #0
@b1:    lda (p2),y
        jsr spi_xfer
        iny
        bne @b1
        inc p2+1
@b2:    lda (p2),y
        jsr spi_xfer
        iny
        bne @b2
        dec p2+1
        lda #$FF            ; dummy CRC
        jsr spi_xfer
        lda #$FF
        jsr spi_xfer
        lda #$FF            ; data response: xxx00101 = accepted
        jsr spi_xfer
        and #$1F
        cmp #$05
        bne @fail
        lda #255
        sta t3
        ldx #0
@busy:  lda #$FF            ; the card holds MISO low while it writes
        jsr spi_xfer
        bne @done
        dex
        bne @busy
        dec t3
        bne @busy
        beq @fail
@done:  jsr sd_deselect
        clc
        rts
@fail:  jsr sd_deselect
        sec
        rts

; ==================================================================
; A small file system
; ==================================================================
; Sector 0: "VELCFS01", 8 spare bytes, then 31 entries of 16 bytes:
;   name (12 bytes, padded with spaces), length (2), $A5 if used, spare.
; File n lives in sectors 64 + n x 64 (up to 32 KB each).
; Use a card that holds nothing else: SAVE writes to it directly.

fs_magic: .byte "VELCFS01"

; fs_setname: name of length A at (BASIC_INDEX) -> fname
fs_setname:
        sta t0
        ldy #0
@copy:  cpy t0
        bcs @pad
        cpy #12
        bcs @done
        lda (BASIC_INDEX),y
        cmp #'a'
        bcc :+
        cmp #'z'+1
        bcs :+
        and #$DF
:       sta fname,y
        iny
        bne @copy
@pad:   lda #' '
@p2:    cpy #12
        bcs @done
        sta fname,y
        iny
        bne @p2
@done:  rts

lba_zero:
        lda #0
        sta sd_lba
        sta sd_lba+1
        sta sd_lba+2
        sta sd_lba+3
        rts

lba_inc:
        inc sd_lba
        bne @rts
        inc sd_lba+1
@rts:   rts

; fs_mount: make sure the card is ready and the directory is in SDBUF.
; Carry set (and a message printed) if there is no card.
fs_mount:
        lda sd_ok
        bne @read
        jsr sd_init
        bcs @nocard
@read:  jsr lba_zero
        lda #<SDBUF
        sta p2
        lda #>SDBUF
        sta p2+1
        jsr sd_read
        bcs @nocard
        ldx #DIR_MAGIC_LEN-1
@chk:   lda SDBUF,x
        cmp fs_magic,x
        bne @new
        dex
        bpl @chk
        clc
        rts
@new:   ldx #0              ; not ours yet: an empty directory
        txa
@z:     sta SDBUF,x
        sta SDBUF+256,x
        inx
        bne @z
        ldx #DIR_MAGIC_LEN-1
@m:     lda fs_magic,x
        sta SDBUF,x
        dex
        bpl @m
        clc
        rts
@nocard:
        lda #0
        sta sd_ok
        lda #<msg_nocard
        ldy #>msg_nocard
        jsr kprint
        sec
        rts

; fs_entry: p3 = SDBUF + 16 x (X+1), the entry for file X
fs_entry:
        inx
        txa
        dex
        sta t0
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<SDBUF
        sta p3
        lda t0
        lsr a
        lsr a
        lsr a
        lsr a
        adc #>SDBUF
        sta p3+1
        rts

; fs_find: X = entry holding fname, carry clear; carry set if none
fs_find:
        ldx #0
@next:  jsr fs_entry
        ldy #14
        lda (p3),y
        cmp #$A5
        bne @skip
        ldy #11
@cmp:   lda (p3),y
        cmp fname,y
        bne @skip
        dey
        bpl @cmp
        clc
        rts
@skip:  inx
        cpx #31
        bcc @next
        sec
        rts

; fs_free: X = first unused entry, carry set if the directory is full
fs_free:
        ldx #0
@next:  jsr fs_entry
        ldy #14
        lda (p3),y
        cmp #$A5
        bne @found
        inx
        cpx #31
        bcc @next
        sec
        rts
@found: clc
        rts

; fs_slot: sd_lba = 64 + 64 x fs_ent
fs_slot:
        jsr lba_zero
        lda fs_ent
        clc
        adc #1              ; (n+1) x 64
        sta t0
        lda #0
        ldx #6
@sh:    asl t0
        rol a
        dex
        bne @sh
        sta sd_lba+1
        lda t0
        sta sd_lba
        rts

; fs_nsec: A = number of 512-byte sectors in fs_len (rounded up)
fs_nsec:
        lda fs_len
        clc
        adc #$FF
        lda fs_len+1
        adc #1
        lsr a
        rts

; KSAVE: save BASIC's program. A = name length, name at (BASIC_INDEX),
; X/Y = address just after the program.
ksave:
        stx fs_end
        sty fs_end+1
        jsr fs_setname
        jsr fs_mount
        bcc :+
        rts
:       jsr fs_find
        bcc @have
        jsr fs_free
        bcc @have
        lda #<msg_full
        ldy #>msg_full
        jmp kprint
@have:  stx fs_ent
        sec
        lda fs_end
        sbc BASIC_TXTTAB
        sta fs_len
        lda fs_end+1
        sbc BASIC_TXTTAB+1
        sta fs_len+1
        lda BASIC_TXTTAB
        sta p2
        lda BASIC_TXTTAB+1
        sta p2+1
        jsr fs_slot
        jsr fs_nsec
        sta fs_cnt
        beq @dir
@wr:    jsr sd_write
        bcs @err
        inc p2+1
        inc p2+1
        jsr lba_inc
        dec fs_cnt
        bne @wr
@dir:   ldx fs_ent          ; fill in the directory entry
        jsr fs_entry
        ldy #11
@nm:    lda fname,y
        sta (p3),y
        dey
        bpl @nm
        ldy #12
        lda fs_len
        sta (p3),y
        iny
        lda fs_len+1
        sta (p3),y
        iny
        lda #$A5
        sta (p3),y
        jsr lba_zero
        lda #<SDBUF
        sta p2
        lda #>SDBUF
        sta p2+1
        jsr sd_write
        bcs @err
        lda #<msg_saved
        ldy #>msg_saved
        jmp kprint
@err:   lda #<msg_ioerr
        ldy #>msg_ioerr
        jmp kprint
@rts:   rts

; KLOAD: load a program to TXTTAB. A = name length, name at (BASIC_INDEX).
; Returns carry clear and X/Y = the end of the program, or carry set.
; LOAD "$" lists the directory instead.
kload:
        jsr fs_setname
        jsr fs_mount
        bcs @fail
        lda fname
        cmp #'$'
        bne @find
        lda fname+1
        cmp #' '
        bne @find
        jsr fs_list
        sec
        rts
@find:  jsr fs_find
        bcc @got
        lda #<msg_notfound
        ldy #>msg_notfound
        jsr kprint
@fail:  sec
        rts
@got:   stx fs_ent
        jsr fs_entry
        ldy #12
        lda (p3),y
        sta fs_len
        iny
        lda (p3),y
        sta fs_len+1
        lda BASIC_TXTTAB
        sta p2
        lda BASIC_TXTTAB+1
        sta p2+1
        jsr fs_slot
        jsr fs_nsec
        sta fs_cnt
        beq @end
@rd:    jsr sd_read
        bcs @err
        inc p2+1
        inc p2+1
        jsr lba_inc
        dec fs_cnt
        bne @rd
@end:   clc
        lda BASIC_TXTTAB
        adc fs_len
        tax
        lda BASIC_TXTTAB+1
        adc fs_len+1
        tay
        clc
        rts
@err:   lda #<msg_ioerr
        ldy #>msg_ioerr
        jsr kprint
        sec
        rts

; fs_list: print the directory
fs_list:
        lda #<msg_dir
        ldy #>msg_dir
        jsr kprint
        ldx #0
@next:  stx fs_ent
        jsr fs_entry
        ldy #14
        lda (p3),y
        cmp #$A5
        bne @skip
        ldy #0
@nm:    lda (p3),y
        jsr chrout
        iny
        cpy #12
        bne @nm
        lda #' '
        jsr chrout
        ldy #12
        lda (p3),y
        tax
        iny
        lda (p3),y
        jsr print_dec       ; length in bytes
        lda #<msg_bytes
        ldy #>msg_bytes
        jsr kprint
@skip:  ldx fs_ent
        inx
        cpx #31
        bcc @next
        rts

; print_dec: print the 16-bit number A (high) / X (low) in decimal
print_dec:
        sta pd+1
        stx pd
        lda #0
        sta t2              ; nonzero once a digit has been printed
        ldx #4
@digit: ldy #0              ; count how many times the power of ten fits
@sub:   sec
        lda pd
        sbc pow10_lo,x
        sta t0
        lda pd+1
        sbc pow10_hi,x
        bcc @show
        sta pd+1
        lda t0
        sta pd
        iny
        bne @sub
@show:  tya
        bne @print
        lda t2
        bne @print
        cpx #0
        bne @skip
@print: tya
        ora #'0'
        jsr chrout
        inc t2
@skip:  dex
        bpl @digit
        rts
pow10_lo: .byte <1, <10, <100, <1000, <10000
pow10_hi: .byte >1, >10, >100, >1000, >10000

msg_nocard:   .byte "?NO SD CARD", 13, 10, 0
msg_full:     .byte "?DIRECTORY FULL", 13, 10, 0
msg_saved:    .byte "SAVED", 13, 10, 0
msg_notfound: .byte "?FILE NOT FOUND", 13, 10, 0
msg_ioerr:    .byte "?SD CARD ERROR", 13, 10, 0
msg_dir:      .byte "NAME         BYTES", 13, 10, 0
msg_bytes:    .byte 13, 10, 0

; ==================================================================
; The monitor
; ==================================================================
;   D aaaa [bbbb]   show memory           E aaaa bb bb ...  change memory
;   G aaaa          run code (JSR)        L                 load Intel HEX
;   B               start BASIC           ?                 help
monitor:
        lda #<msg_mon
        ldy #>msg_mon
        jsr kprint
mon_loop:
        lda #13
        jsr chrout
        lda #10
        jsr chrout
        lda #'*'
        jsr chrout
        jsr getline
        ldx #0
        jsr skipsp
        lda LBUF,x
        beq mon_loop
        inx
        cmp #'D'
        bne :+
        jmp mon_dump
:       cmp #'E'
        bne :+
        jmp mon_enter
:       cmp #'G'
        bne :+
        jmp mon_go
:       cmp #'L'
        bne :+
        jmp mon_load
:       cmp #'B'
        bne :+
        jmp BASIC_INIT
:       lda #<msg_mon
        ldy #>msg_mon
        jsr kprint
        jmp mon_loop

mon_dump:
        jsr gethex
        bcs mon_err
        lda hexval
        sta mp
        lda hexval+1
        sta mp+1
        jsr gethex          ; optional end address
        bcc @range
        lda mp              ; none: 64 bytes
        clc
        adc #63
        sta hexval
        lda mp+1
        adc #0
        sta hexval+1
@range: jsr crlf
        lda mp+1
        jsr prhex
        lda mp
        jsr prhex
        lda #':'
        jsr chrout
        ldy #0
@byte:  lda #' '
        jsr chrout
        lda (mp),y
        jsr prhex
        iny
        cpy #8
        bne @byte
        clc
        lda mp
        adc #8
        sta mp
        bcc :+
        inc mp+1
:       lda hexval+1        ; done when mp has passed the end
        cmp mp+1
        bcc @done
        bne @range
        lda hexval
        cmp mp
        bcs @range
@done:  jmp mon_loop

mon_err:
        lda #'?'
        jsr chrout
        jmp mon_loop

mon_enter:
        jsr gethex
        bcs mon_err
        lda hexval
        sta mp
        lda hexval+1
        sta mp+1
@next:  jsr gethex
        bcs @done
        lda hexval
        ldy #0
        sta (mp),y
        inc mp
        bne @next
        inc mp+1
        bne @next
@done:  jmp mon_loop

mon_go:
        jsr gethex
        bcs mon_err
        jsr @call
        jmp mon_loop
@call:  jmp (hexval)

; L: Intel HEX records from the serial port, ":LLAAAATT<data>CC".
; Prints "." for each good line and "?" for a bad checksum.
mon_load:
        lda #<msg_send
        ldy #>msg_send
        jsr kprint
@line:  jsr ser_get
        cmp #':'
        bne @line
        lda #0
        sta hexsum
        jsr ser_byte        ; length
        sta t2
        jsr ser_byte        ; address
        sta mp+1
        jsr ser_byte
        sta mp
        jsr ser_byte        ; type
        sta t3
        ldy #0
@data:  cpy t2
        beq @sum
        jsr ser_byte
        sta (mp),y
        iny
        bne @data
@sum:   jsr ser_byte        ; checksum: everything adds up to zero
        lda hexsum
        beq @good
        lda #'?'
        jsr chrout
        jmp @line
@good:  lda t3
        cmp #1              ; type 1 = end of file
        beq @end
        lda #'.'
        jsr chrout
        jmp @line
@end:   jmp mon_loop

ser_get:
        lda UART_STAT
        lsr a
        bcc ser_get
        lda UART_DATA
        rts

; ser_byte: two hex digits from the serial port, added to hexsum
ser_byte:
        jsr ser_get
        jsr hexdig
        asl a
        asl a
        asl a
        asl a
        sta t0
        jsr ser_get
        jsr hexdig
        ora t0
        pha
        clc
        adc hexsum
        sta hexsum
        pla
        rts

; hexdig: ASCII hex digit to 0-15 (anything else gives junk)
hexdig:
        cmp #'a'
        bcc :+
        and #$DF
:       cmp #'A'
        bcc @num
        sbc #'A'-10
        rts
@num:   and #$0F
        rts

; getline: read a line into LBUF (zero-terminated), echoing it
getline:
        ldx #0
@key:   jsr cursor_poll
        txa
        pha
        jsr key_raw
        sta kchar
        pla
        tax
        lda kchar
        beq @key
        pha
        jsr cursor_off
        pla
        cmp #13
        beq @end
        cmp #8
        beq @bs
        cmp #127
        beq @bs
        cmp #32
        bcc @key
        cpx #63
        bcs @key
        sta LBUF,x
        inx
        jsr chrout
        jmp @key
@bs:    cpx #0
        beq @key
        dex
        lda #8
        jsr uart_put
        lda #' '
        jsr uart_put
        lda #8
        jsr uart_put
        lda #8
        jsr scr_put
        jmp @key
@end:   lda #0
        sta LBUF,x
        rts

skipsp:
        lda LBUF,x
        cmp #' '
        bne @rts
        inx
        bne skipsp
@rts:   rts

; gethex: read up to four hex digits at LBUF,x into hexval.
; Carry set if there were none.
gethex:
        jsr skipsp
        lda #0
        sta hexval
        sta hexval+1
        sta t3              ; digits seen
@dig:   lda LBUF,x
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcc @ok
        cmp #'A'
        bcc @end
        cmp #'F'+1
        bcs @end
@ok:    jsr hexdig
        ldy #4
@sh:    asl hexval
        rol hexval+1
        dey
        bne @sh
        ora hexval
        sta hexval
        inc t3
        inx
        bne @dig
@end:   lda t3              ; any digits?
        beq @none
        clc
        rts
@none:  sec
        rts

crlf:   lda #13
        jsr chrout
        lda #10
        jmp chrout

prhex:  pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @dig
        pla
        and #$0F
@dig:   cmp #10
        bcc :+
        adc #6              ; carry is set: +7 for A-F
:       adc #'0'
        jmp chrout

msg_mon:  .byte 13, 10, "MONITOR: D ADDR [END], E ADDR BYTES, G ADDR,", 13, 10
          .byte "L (INTEL HEX FROM SERIAL), B (BASIC)", 0
msg_send: .byte 13, 10, "SEND THE HEX FILE NOW", 13, 10, 0

; ==================================================================
; Tables
; ==================================================================
        .segment "RODATA"

; address of each text row: SCREEN + row x 1280
trow_lo:
        .repeat 25, I
        .byte <(SCREEN + I * 1280)
        .endrepeat
trow_hi:
        .repeat 25, I
        .byte >(SCREEN + I * 1280)
        .endrepeat

; address of each pixel row: SCREEN + y x 160
prow_lo:
        .repeat 200, I
        .byte <(SCREEN + I * 160)
        .endrepeat
prow_hi:
        .repeat 200, I
        .byte >(SCREEN + I * 160)
        .endrepeat

        .include "ps2map.inc"

font:
        .include "font.inc"

; ==================================================================
; Jump table: fixed addresses for BASIC and your programs
; ==================================================================
        .segment "JUMPS"
        jmp chrout          ; $FF00  print A
        jmp chrin           ; $FF03  wait for a key, echo it
        jmp getkey          ; $FF06  key or 0
        jmp ksave           ; $FF09  SAVE
        jmp kload           ; $FF0C  LOAD
        jmp cls             ; $FF0F  clear the screen
        jmp kcolor          ; $FF12  ink CFG, paper CBG
        jmp kplot           ; $FF15  plot GX0,GY0 in GCOL
        jmp kline           ; $FF18  line GX0,GY0 - GX1,GY1 in GCOL
        jmp ksound          ; $FF1B  voice SVOICE, Hz SFREQ, volume SVOL
        jmp kpause          ; $FF1E  wait PTICKS sixtieths
        jmp sd_read         ; $FF21  sector sd_lba to (p2)
        jmp sd_write        ; $FF24  (p2) to sector sd_lba
        jmp monitor         ; $FF27  the monitor
        jmp stopkey         ; $FF2A  Ctrl-C pressed? (keeps other keys)

        .segment "VECTORS"
        .word nmi           ; $FFFA
        .word reset         ; $FFFC
        .word irq           ; $FFFE
