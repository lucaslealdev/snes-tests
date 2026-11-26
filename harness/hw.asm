; Hardware initialization, NMI, joypad and the DMA flush of the UI buffers.
;
; Video: Mode 1 (BG3 on top). BG1 (4bpp, tiles at word $1000, map at $0000) holds the content; BG3 (2bpp, tiles
; at word $2000, map at $0400) holds the header and footer; sprites (tiles at $4000) hold the cursor.
; A gradient (HDMA, channel 7) animates the backdrop color. The UI is drawn in shadow buffers in WRAM and
; copied by DMA in the NMI. While tests run, NMI is off and the screen is updated by direct writes in vblank.

VRAM_BG1_MAP = $0000
VRAM_BG3_MAP = $0400
VRAM_BG1_CHR = $1000
VRAM_BG3_CHR = $2000
VRAM_OBJ_CHR = $4000

.segment "CODE"

; Initializes the PPU, uploads graphics and starts the HDMA gradient. The screen stays off (forced blank).
hw_init:
	A8
	XY16
	lda #$8F
	sta $2100        ; forced blank
	stz $4200        ; no NMI/IRQ/auto joypad
	stz $420B
	stz $420C
	lda #$09
	sta $2105        ; BG mode 1, BG3 priority
	stz $2106        ; no mosaic
	lda #(VRAM_BG1_MAP >> 10) << 2
	sta $2107        ; BG1 map, 32x32
	lda #(VRAM_BG3_MAP >> 10) << 2
	sta $2109        ; BG3 map, 32x32
	lda #(VRAM_BG1_CHR >> 12)
	sta $210B        ; BG1 tiles
	lda #(VRAM_BG3_CHR >> 12)
	sta $210C        ; BG3 tiles
	lda #(VRAM_OBJ_CHR >> 13)
	sta $2101        ; 8x8/16x16 sprites, tiles at $4000
	; scroll: the PPU shows the first line of a BG one line late, so use -1 (BG1, BG3)
	lda #$FF
	sta $210E
	sta $210E
	sta $2112
	sta $2112
	stz $210D
	stz $210D
	stz $2111
	stz $2111
	lda #$80
	sta $2115        ; VMAIN: increment after high byte
	lda #$15
	sta $212C        ; main screen: BG1, BG3, sprites
	stz $212D
	stz $212E
	stz $212F
	stz $2130
	stz $2131        ; no color math
	stz $2133

	; clear VRAM (64KB of zero)
	ldx #0
	stx $2116
	lda #$09
	sta $4300        ; fixed source, write 2 registers
	lda #$18
	sta $4301
	ldx #.loword(zero_byte)
	stx $4302
	lda #^zero_byte
	sta $4304
	ldx #0
	stx $4305        ; 65536 bytes
	lda #$01
	sta $420B

	; tiles
	ldx #VRAM_BG1_CHR
	stx $2116
	DMA0 $01, $18, gfx_font4, gfx_font4_end-gfx_font4
	ldx #VRAM_BG3_CHR
	stx $2116
	DMA0 $01, $18, gfx_font2, gfx_font2_end-gfx_font2
	ldx #VRAM_OBJ_CHR
	stx $2116
	DMA0 $01, $18, gfx_obj, gfx_obj_end-gfx_obj
	; palette
	stz $2121
	DMA0 $00, $22, gfx_palette, 512

	; HDMA gradient on the backdrop (color 0): channel 7, mode 3 (writes CGADD, CGADD, CGDATA, CGDATA)
	lda #$03
	sta $4370
	lda #$21
	sta $4371
	ldx #.loword(gfx_hdma)
	stx $4372
	lda #^gfx_hdma
	sta $4374
	lda #$80
	sta $420C

	; sprites: all hidden
	jsr oam_clear
	stz nmi_ui
	stz bg3_dirty
	stz pad_ev
	stz pad_ev+1
	stz pad_prev
	stz pad_prev+1
	stz rep_timer
	rts

; Hides all sprites in the shadow OAM
oam_clear:
	A8
	ldx #0
@loop:
	lda #$00
	sta f:OAM_SHADOW,x   ; x
	inx
	lda #$F0
	sta f:OAM_SHADOW,x   ; y (off screen)
	inx
	lda #$00
	sta f:OAM_SHADOW,x   ; tile
	inx
	sta f:OAM_SHADOW,x   ; attributes
	inx
	cpx #512
	bne @loop
@high:
	sta f:OAM_SHADOW,x   ; high table: x bit 8 = 0, small
	inx
	cpx #544
	bne @high
	rts

; Copies the shadow buffers to the PPU. Must be called in vblank or forced blank.
ui_flush:
	A8
	ldx #0
	stx $2102
	DMA0 $00, $04, OAM_SHADOW, 544
	lda #$80
	sta $2115
	ldx #VRAM_BG1_MAP
	stx $2116
	DMA0 $01, $18, BG1_SHADOW, $800
	lda bg3_dirty
	beq @done
	ldx #VRAM_BG3_MAP
	stx $2116
	DMA0 $01, $18, BG3_SHADOW, $800
	stz bg3_dirty
@done:
	rts

; Clears the shadow tilemaps (blank tiles) and marks BG3 as dirty
ui_clear:
	A8
	XY16
	ldx #0
@loop:
	lda #$20
	sta f:BG1_SHADOW,x
	sta f:BG3_SHADOW,x
	inx
	lda #$00
	sta f:BG1_SHADOW,x
	sta f:BG3_SHADOW,x
	inx
	cpx #$800
	bne @loop
	lda #1
	sta bg3_dirty
	rts

; Turns the screen on/off. The off state is forced blank
screen_on:
	lda #$0F
	sta $2100
	rts

screen_off:
	lda #$8F
	sta $2100
	rts

; Enables the NMI (menu/report) and waits for the first one
nmi_on:
	A8
	lda #1
	sta nmi_ui
	lda #$81
	sta $4200
	rts

nmi_off:
	A8
	lda #$01
	sta $4200
	stz nmi_ui
	rts

; Waits for the next NMI (needs nmi_on)
wait_frame:
	A8
	lda nmi_frames
@wait:
	cmp nmi_frames
	beq @wait
	rts

; Waits for the start of the next vblank by polling (used when the NMI is off)
wait_vblank:
	A8
@wait1:
	bit $4210
	bmi @wait1
@wait2:
	bit $4210
	bpl @wait2
	inc frame_acc
	rts

; NMI: copies the UI to the PPU, reads the joypad. Only enabled while the menu/report are shown.
nmi:
	AXY16
	pha
	phx
	phy
	phd
	phb
	AXY16
	lda #0
	tcd
	A8
	lda #0
	pha
	plb
	lda $4210        ; acknowledge
	lda nmi_ui
	beq @exit
	jsr ui_flush
	; joypad (auto-read finishes a few lines after vblank starts)
@wait_pad:
	lda $4212
	and #$01
	bne @wait_pad
	A16
	lda $4218
	sta pad_cur
	; newly pressed buttons
	lda pad_prev
	eor #$FFFF
	and pad_cur
	sta pad_new
	; auto repeat for the directions and shoulder buttons
	lda pad_cur
	and #PAD_UP|PAD_DOWN|PAD_LEFT|PAD_RIGHT|PAD_L|PAD_R
	beq @no_rep
	cmp rep_last
	bne @rep_reset
	A8
	inc rep_timer
	lda rep_timer
	cmp #20
	bcc @rep_done
	and #$03
	bne @rep_done
	A16
	lda pad_cur
	and #PAD_UP|PAD_DOWN|PAD_LEFT|PAD_RIGHT|PAD_L|PAD_R
	ora pad_new
	sta pad_new
	bra @rep_done16
@rep_reset:
	sta rep_last
	A8
	stz rep_timer
	bra @rep_done
@no_rep:
	A8
	stz rep_timer
	A16
	stz rep_last
@rep_done16:
	A8
@rep_done:
	A16
	lda pad_cur
	sta pad_prev
	lda pad_ev
	ora pad_new
	sta pad_ev
	A8
	inc nmi_frames
@exit:
	AXY16
	plb
	pld
	ply
	plx
	pla
	rti

; Returns the pad events since the last call in A (16 bits)
get_pad:
	A16
	lda pad_ev
	stz pad_ev
	rts
