; Text output. Characters are drawn as tiles (tile number = ASCII code) either into the shadow tilemaps in WRAM
; (tmode = 0, copied to the PPU by the NMI) or directly into VRAM (tmode = 1, used while tests run: in vblank or
; forced blank only).
;   txt_at   X = column, Y = row, A = layer (0 = BG1 content, 1 = BG3 header/footer)
;   txt_style A = ST_* (palette of the text). Call it after txt_at, or before: both work.
; All routines expect A=8 bits, X/Y=16 bits.

.segment "RODATA"
; BG3 only has palettes with the colors of the first styles. Index: ST_*. See assets/make_assets.py
bg3_palette: .byte 0, 0, 2, 1, 0, 0, 3, 0
pow10: .word 10000, 1000, 100, 10, 1

.segment "CODE"

txt_at:
	sta tlayer
	A16
	tya
	and #$00FF
	asl a
	asl a
	asl a
	asl a
	asl a
	sta tpos
	txa
	and #$00FF
	clc
	adc tpos
	asl a
	sta tpos
	A8
	lda tlayer
	bne @bg3
	ldx #.loword(BG1_SHADOW)
	bra @base
@bg3:
	ldx #.loword(BG3_SHADOW)
@base:
	stx tbase
	jsr txt_apply_style
	lda tmode
	beq @ret
	; direct: VRAM word address
	lda tlayer
	beq @l1
	A16
	lda tpos
	lsr a
	clc
	adc #VRAM_BG3_MAP
	bra @set
@l1:
	A16
	lda tpos
	lsr a
	clc
	adc #VRAM_BG1_MAP
@set:
	sta $2116
	A8
@ret:
	rts

txt_style:
	sta tstyle
txt_apply_style:
	lda tlayer
	bne @bg3
	lda tstyle
	asl a
	asl a
	sta tattr
	rts
@bg3:
	A16
	lda tstyle
	and #$0007
	tax
	A8
	lda bg3_palette,x
	asl a
	asl a
	sta tattr
	rts

; A = tile number. Draws at the current position and advances
txt_putc:
	phx
	pha
	lda tmode
	bne @direct
	A16
	lda tpos
	clc
	adc tbase
	tax
	A8
	pla
	sta f:$7E0000,x
	inx
	lda tattr
	sta f:$7E0000,x
	bra @advance
@direct:
	pla
	sta $2118
	lda tattr
	sta $2119
@advance:
	A16
	inc tpos
	inc tpos
	A8
	plx
	rts

; Prints the NUL-terminated string at tptr (24-bit)
txt_puts:
	ldy #0
@loop:
	lda [tptr],y
	beq @end
	jsr txt_putc
	iny
	bra @loop
@end:
	rts

; Prints a string in bank 0 (X = address)
txt_puts0:
	stx tptr
	stz tptr+2
	jmp txt_puts

; Prints a string from the STRINGS bank (X = address)
txt_putsf:
	stx tptr
	lda #^strings_marker
	sta tptr+2
	jmp txt_puts

; Prints at most A characters of a string from the STRINGS bank (X = address)
txt_putsf_n:
	sta tcount
	stx tptr
	lda #^strings_marker
	sta tptr+2
	ldy #0
@loop:
	tya
	cmp tcount
	bcs @end
	lda [tptr],y
	beq @end
	jsr txt_putc
	iny
	bra @loop
@end:
	rts

; Prints A (count) copies of the tile X (low byte)
txt_fill:
	sta tcount
	stx tchar
@loop:
	lda tcount
	beq @end
	lda tchar
	jsr txt_putc
	dec tcount
	bra @loop
@end:
	rts

; A = nibble value (low 4 bits)
txt_nibble:
	and #$0F
	clc
	adc #'0'
	cmp #':'
	bcc @ok
	adc #6
@ok:
	jmp txt_putc

txt_hex8:
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr txt_nibble
	pla
	jmp txt_nibble

txt_hex16:           ; A = 16 bits
	A16
	pha
	xba
	A8
	jsr txt_hex8
	A16
	pla
	A8
	jmp txt_hex8

; Converts A (16 bits) to decimal, in numbuf (5 characters, leading spaces)
dec_to_buf:
	A16
	sta tmp16
	A8
	lda #1
	sta tlead
	ldx #0
@digit:
	A16
	lda tmp16
	ldy #0
@sub:
	cmp pow10,x
	bcc @got
	sec
	sbc pow10,x
	iny
	bra @sub
@got:
	sta tmp16
	A8
	tya
	bne @nonzero
	; zero digit: a space while it is a leading zero (but never in the last position)
	cpx #8
	beq @zero
	lda tlead
	beq @zero
	lda #' '
	bra @store
@zero:
	lda #'0'
	bra @store
@nonzero:
	clc
	adc #'0'
	ldy #0
	sty tlead
@store:
	phx
	pha
	A16
	txa
	lsr a
	tax
	A8
	pla
	sta numbuf,x
	plx
	inx
	inx
	cpx #10
	bne @digit
	rts

; Prints A (16 bits) in decimal, right aligned in X columns (1 to 5)
txt_dec:
	stx tcount
	jsr dec_to_buf
	A16
	lda #5
	sec
	sbc tcount
	and #$00FF
	tax
	A8
@loop:
	lda numbuf,x
	jsr txt_putc
	inx
	cpx #5
	bne @loop
	rts

; Prints A (16 bits) in decimal, left aligned (no padding)
txt_dec_left:
	jsr dec_to_buf
	ldx #0
@skip:
	lda numbuf,x
	cmp #' '
	bne @loop
	inx
	bra @skip
@loop:
	lda numbuf,x
	jsr txt_putc
	inx
	cpx #5
	bne @loop
	rts

; Prints the NUL-terminated string at tptr, wrapping at word boundaries between the columns wrap_x0 and wrap_x1
; (exclusive). Newline (10) forces a line break. wcol/wrow hold the position, and the layer is BG1.
; Returns the next free row in wrow.
txt_wrap:
	ldy #0
@loop:
	; skip spaces
	stz wspace
@skip:
	lda [tptr],y
	cmp #' '
	bne @word
	lda #1
	sta wspace
	iny
	bra @skip
@word:
	lda [tptr],y
	bne @notend
	rts
@notend:
	cmp #10
	bne @measure
	jsr wrap_newline
	iny
	bra @loop
@measure:
	; n = length of the word
	sty wy
	ldx #0
@len:
	lda [tptr],y
	beq @lendone
	cmp #' '
	beq @lendone
	cmp #10
	beq @lendone
	inx
	iny
	bra @len
@lendone:
	ldy wy
	stx wlen
	; does it fit?
	lda wcol
	cmp wrap_x0
	beq @fresh         ; at the start of a line: no space needed
	lda wspace
	beq @nospace
	lda wcol
	clc
	adc wlen
	inc a              ; the space
	cmp wrap_x1
	beq @spacefit
	bcs @newline
@spacefit:
	lda #' '
	jsr wrap_putc
	bra @print
@nospace:
	lda wcol
	clc
	adc wlen
	cmp wrap_x1
	beq @print
	bcc @print
@newline:
	jsr wrap_newline
	bra @print
@fresh:
@print:
	lda wlen
	sta tcount
@chars:
	lda tcount
	beq @loop
	lda [tptr],y
	jsr wrap_putc
	iny
	dec tcount
	bra @chars

wrap_putc:
	pha
	lda wcol
	cmp wrap_x1
	bcc @ok
	jsr wrap_newline
@ok:
	pla
	jsr txt_putc
	inc wcol
	rts

wrap_newline:
	phx
	phy
	lda wrap_x0
	sta wcol
	inc wrow
	A16
	lda wcol
	and #$00FF
	tax
	lda wrow
	and #$00FF
	tay
	A8
	lda #0
	jsr txt_at
	ply
	plx
	rts
