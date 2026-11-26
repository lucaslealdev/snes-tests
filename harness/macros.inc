; Register size macros. The default state in the harness is A=8 bits, X/Y=16 bits (.a8 .i16).

.macro A8
	sep #$20
	.a8
.endmacro

.macro A16
	rep #$20
	.a16
.endmacro

.macro XY8
	sep #$10
	.i8
.endmacro

.macro XY16
	rep #$10
	.i16
.endmacro

.macro AXY16
	rep #$30
	.a16
	.i16
.endmacro

; Sets up DMA channel 0 and runs it (during vblank or forced blank).
; mode, B-bus register ($21xx -> xx), 24-bit source address, size
.macro DMA0 mode, breg, src, size
	lda #mode
	sta $4300
	lda #breg
	sta $4301
	ldx #.loword(src)
	stx $4302
	lda #^src
	sta $4304
	ldx #size
	stx $4305
	lda #$01
	sta $420B
.endmacro

; Long branches (the target is out of the range of a relative branch). They use anonymous labels, which don't
; end the scope of the cheap local labels (@name).
.macro jeq lbl
	bne :+
	jmp lbl
:
.endmacro
.macro jne lbl
	beq :+
	jmp lbl
:
.endmacro
.macro jcs lbl
	bcc :+
	jmp lbl
:
.endmacro
.macro jcc lbl
	bcs :+
	jmp lbl
:
.endmacro
