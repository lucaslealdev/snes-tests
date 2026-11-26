; Starting a run, the run screen, and the totals.

.segment "RODATA"
txt_title:      .byte "65C816 + SPC-700 TEST ROM", 0
txt_running:    .byte "Running tests", 0
txt_spc_label:  .byte "SPC-700", 0
txt_cpu_label:  .byte "65C816", 0
txt_group:      .byte "Group", 0
txt_test:       .byte "Test", 0
txt_passed:     .byte "Passed", 0
txt_failed:     .byte "Failed", 0
txt_skipped:    .byte "Skipped", 0
txt_elapsed:    .byte "Elapsed", 0
txt_reset_hint: .byte "If the CPU hangs, press RESET: the", 0
txt_reset_hint2: .byte "run continues with the next test.", 0
txt_none:       .byte "-", 0

.segment "CODE"

; Computes which tests will run (rsv_cpu_map, rsv_cpu_total, rsv_spc_total) from the selection and the filters
compute_totals:
	A8
	XY16
	ldx #0
@clear:
	lda #0
	sta f:rsv_cpu_map,x
	inx
	cpx #MAX_TESTS/8
	bne @clear
	lda f:rsv_filters
	eor #$FF
	and #$07
	sta excl
	A16
	stz ct
	stz coff
	stz ccount
	A8
@loop:
	A16
	lda ct
	cmp #CPU_TEST_COUNT
	A8
	bcs @cpu_done
	ldx coff
	lda f:cpu_records+9,x    ; tags
	and excl
	bne @next                ; excluded by a filter
	lda f:cpu_records+15,x   ; group
	A16
	and #$00FF
	tax
	A8
	SET_BM rsv_sel_cpu
	jsr bitmap_test
	beq @next
	ldx ct
	SET_BM rsv_cpu_map
	jsr bitmap_set
	A16
	inc ccount
	A8
@next:
	A16
	inc ct
	lda coff
	clc
	adc #16
	sta coff
	A8
	bra @loop
@cpu_done:
	A16
	lda ccount
	sta f:rsv_cpu_total
	stz ccount
	A8
	ldx #0
	stx spc_gi
@spc:
	ldx spc_gi
	cpx #SPC_GROUP_COUNT
	bcs @end
	jsr spc_eligible
	bcc @spc_next
	A16
	lda f:spc_groups+4,x
	clc
	adc ccount
	sta ccount
	A8
@spc_next:
	ldx spc_gi
	inx
	stx spc_gi
	bra @spc
@end:
	A16
	lda ccount
	sta f:rsv_spc_total
	A8
	rts

; Runs all the selected tests: SPC first, then CPU. The CPU tests end in run_finished.
start_run:
	A8
	XY16
	jsr state_clear_run
	jsr compute_totals
	lda #PHASE_SPC
	sta f:rsv_phase
	jsr run_screen_init
	jsr spc_phase
	lda #PHASE_CPU
	sta f:rsv_phase
	jmp cpu_start

; Builds the run screen
run_screen_init:
	A8
	XY16
	jsr nmi_off
	jsr screen_off
	jsr ui_clear
	jsr oam_clear
	jsr draw_header
	lda #ST_ACCENT
	jsr txt_style
	ldx #1
	ldy #3
	lda #0
	jsr txt_at
	ldx #txt_running
	jsr txt_puts0
	lda #ST_CAT
	jsr txt_style
	ldx #1
	ldy #5
	lda #0
	jsr txt_at
	ldx #txt_spc_label
	jsr txt_puts0
	ldx #1
	ldy #9
	lda #0
	jsr txt_at
	ldx #txt_cpu_label
	jsr txt_puts0
	lda #ST_NORMAL
	jsr txt_style
	ldx #1
	ldy #13
	lda #0
	jsr txt_at
	ldx #txt_group
	jsr txt_puts0
	ldx #1
	ldy #14
	lda #0
	jsr txt_at
	ldx #txt_test
	jsr txt_puts0
	ldx #1
	ldy #16
	lda #0
	jsr txt_at
	ldx #txt_passed
	jsr txt_puts0
	ldx #1
	ldy #17
	lda #0
	jsr txt_at
	ldx #txt_failed
	jsr txt_puts0
	ldx #1
	ldy #18
	lda #0
	jsr txt_at
	ldx #txt_skipped
	jsr txt_puts0
	ldx #1
	ldy #20
	lda #0
	jsr txt_at
	ldx #txt_elapsed
	jsr txt_puts0
	lda #ST_DIM
	jsr txt_style
	ldx #1
	ldy #23
	lda #0
	jsr txt_at
	ldx #txt_reset_hint
	jsr txt_puts0
	ldx #1
	ldy #24
	lda #0
	jsr txt_at
	ldx #txt_reset_hint2
	jsr txt_puts0
	jsr draw_run_dynamic
	jsr ui_flush
	jmp screen_on

; Header and footer of every screen (BG3)
draw_header:
	A8
	lda #ST_ACCENT
	jsr txt_style
	ldx #1
	ldy #1
	lda #1
	jsr txt_at
	ldx #txt_title
	jsr txt_puts0
	lda #1
	sta bg3_dirty
	rts

; Redraws the numbers of the run screen and sends the result to the PPU in the next vblank
run_update:
	A8
	XY16
	jsr time_flush
	jsr draw_run_dynamic
	jsr wait_vblank
	jmp ui_flush

; Adds the frames counted by the polling loops (frame_acc) to the elapsed time
time_flush:
	A8
@loop:
	lda frame_acc
	beq @done
	dec frame_acc
	lda f:rsv_frames
	inc a
	cmp #60
	bcc @store
	A16
	lda f:rsv_seconds
	inc a
	sta f:rsv_seconds
	A8
	lda #0
@store:
	sta f:rsv_frames
	bra @loop
@done:
	rts

draw_run_dynamic:
	A8
	XY16
	; SPC bar
	A16
	lda f:rsv_spc_done
	sta bar_done
	lda f:rsv_spc_total
	sta bar_total
	A8
	ldx #1
	ldy #6
	lda #0
	jsr txt_at
	lda #ST_ACCENT
	jsr txt_style
	jsr draw_bar
	ldx #1
	ldy #7
	lda #0
	jsr txt_at
	lda #ST_NORMAL
	jsr txt_style
	jsr draw_counts
	; CPU bar
	A16
	lda f:rsv_cpu_done
	sta bar_done
	lda f:rsv_cpu_total
	sta bar_total
	A8
	ldx #1
	ldy #10
	lda #0
	jsr txt_at
	lda #ST_ACCENT
	jsr txt_style
	jsr draw_bar
	ldx #1
	ldy #11
	lda #0
	jsr txt_at
	lda #ST_NORMAL
	jsr txt_style
	jsr draw_counts
	jsr draw_current
	; counters
	A16
	lda f:rsv_spc_done
	clc
	adc f:rsv_cpu_done
	sec
	sbc f:rsv_fail_spc
	sbc f:rsv_fail_cpu
	bcs @pass_ok
	lda #0
@pass_ok:
	pha
	A8
	lda #ST_PASS
	jsr txt_style
	ldx #10
	ldy #16
	lda #0
	jsr txt_at
	A16
	pla
	ldx #5
	jsr txt_dec
	A8
	lda #ST_FAIL
	jsr txt_style
	ldx #10
	ldy #17
	lda #0
	jsr txt_at
	A16
	lda f:rsv_fail_spc
	clc
	adc f:rsv_fail_cpu
	ldx #5
	jsr txt_dec
	A8
	lda #ST_DIM
	jsr txt_style
	ldx #10
	ldy #18
	lda #0
	jsr txt_at
	A16
	lda #SPC_TEST_COUNT+CPU_TEST_COUNT
	sec
	sbc f:rsv_spc_total
	sbc f:rsv_cpu_total
	ldx #5
	jsr txt_dec
	A8
	; elapsed time mm:ss
	lda #ST_NORMAL
	jsr txt_style
	ldx #10
	ldy #20
	lda #0
	jsr txt_at
	A16
	lda f:rsv_seconds
	sta $4204
	A8
	lda #60
	sta $4206
	.repeat 8
	nop
	.endrepeat
	A16
	lda $4214
	sta tmpa
	lda $4216
	sta tmpb
	lda tmpa
	ldx #2
	jsr txt_dec_zero
	A8
	lda #':'
	jsr txt_putc
	A16
	lda tmpb
	and #$00FF
	ldx #2
	jsr txt_dec_zero
	A8
	rts

; A (16 bits) in decimal with leading zeros, X columns (1 to 5)
txt_dec_zero:
	A16
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
	cmp #' '
	bne @put
	lda #'0'
@put:
	jsr txt_putc
	inx
	cpx #5
	bne @loop
	rts

; "dddd / dddd" for the bar counters
draw_counts:
	A16
	lda bar_done
	ldx #4
	jsr txt_dec
	A8
	lda #' '
	jsr txt_putc
	lda #'/'
	jsr txt_putc
	lda #' '
	jsr txt_putc
	A16
	lda bar_total
	ldx #4
	jsr txt_dec
	A8
	rts

; Progress bar of 20 tiles at the current position: bar_done of bar_total
draw_bar:
	A16
	stz barpx
	lda bar_total
	beq @draw
	ldx bar_done
	stx bar_sd
	sta bar_st
@scale:
	lda bar_st
	cmp #$0100
	bcc @div
	lsr bar_st
	lsr bar_sd
	bra @scale
@div:
	lda bar_sd           ; sd * 160 = sd * 128 + sd * 32
	asl a
	asl a
	asl a
	asl a
	asl a
	sta tmp16
	lda bar_sd
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	clc
	adc tmp16
	sta $4204
	A8
	lda bar_st
	sta $4206
	.repeat 8
	nop
	.endrepeat
	A16
	lda $4214
	cmp #161
	bcc @store
	lda #160
@store:
	sta barpx
@draw:
	A8
	ldx #0
@cell:
	A16
	txa
	asl a
	asl a
	asl a
	sta tmp16
	lda barpx
	sec
	sbc tmp16
	bcs @pos
	lda #0
@pos:
	cmp #9
	bcc @ok
	lda #8
@ok:
	clc
	adc #T_BAR0
	A8
	jsr txt_putc
	inx
	cpx #20
	bne @cell
	rts

; Group and test being run (row 13 and 14)
draw_current:
	A8
	lda #ST_NORMAL
	jsr txt_style
	; which phase
	lda f:rsv_phase
	cmp #PHASE_CPU
	beq @cpu
	; SPC
	A16
	lda f:rsv_spc_done
	bne :+
	jmp @nothing
:
	lda f:rsv_spc_cur
	sta cur_test
	asl a
	asl a
	asl a
	tax
	A8
	lda f:spc_records+7,x
	sta cur_group
	A16
	lda f:spc_records,x
	sta cur_ins
	bra @show
@cpu:
	A16
	lda f:rsv_cpu_done
	bne :+
	jmp @nothing
:
	lda f:rsv_cpu_cur
	sta cur_test
	asl a
	asl a
	asl a
	asl a
	tax
	A8
	lda f:cpu_records+15,x
	sta cur_group
	A16
	lda f:cpu_records,x
	sta cur_ins
@show:
	A8
	lda f:rsv_phase
	cmp #PHASE_CPU
	beq @cpu_group
	A16
	lda cur_group
	and #$00FF
	asl a
	asl a
	asl a
	tax
	A8
	lda f:spc_groups,x
	sta cur_name
	lda f:spc_groups+1,x
	sta cur_name+1
	bra @print
@cpu_group:
	A16
	lda cur_group
	and #$00FF
	asl a
	asl a
	asl a
	tax
	A8
	lda f:cpu_groups,x
	sta cur_name
	lda f:cpu_groups+1,x
	sta cur_name+1
@print:
	ldx #10
	ldy #13
	lda #0
	jsr txt_at
	ldx cur_name
	jsr txt_putsf
	jsr txt_clear_eol
	ldx #10
	ldy #14
	lda #0
	jsr txt_at
	lda #'#'
	jsr txt_putc
	A16
	lda cur_test
	jsr txt_hex16
	A8
	lda #' '
	jsr txt_putc
	ldx cur_ins
	jsr txt_putsf
	jmp txt_clear_eol
@nothing:
	A8
	ldx #10
	ldy #13
	lda #0
	jsr txt_at
	ldx #txt_none
	jsr txt_puts0
	jsr txt_clear_eol
	ldx #10
	ldy #14
	lda #0
	jsr txt_at
	ldx #txt_none
	jsr txt_puts0
	jmp txt_clear_eol

; Fills the rest of the row with blanks
txt_clear_eol:
	A16
	lda tpos
	lsr a
	and #$001F
	beq @done
	A8
	lda #' '
	jsr txt_putc
	bra txt_clear_eol
@done:
	A8
	rts
