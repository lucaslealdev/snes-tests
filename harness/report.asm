; Final report. A summary in natural language at the top, a scrolling list of the failures, and A shows the
; description of a failure. The sentences are composed from templates, the per-test record (instruction, inputs,
; mode: generated tables) and the failure entry (kind of check, expected and actual value, address).
; Only the first check that failed in a test is described.

MSGBUF = UI_WORK + $400      ; $7E3800: the text being composed (NUL-terminated)

REPORT_LIST_END = 22         ; last row of the list
BACK_TO_MENU = $FFFF

.segment "RODATA"
; -- summary
txt_all_passed:  .byte "All ", 0
txt_tests_passed: .byte " tests passed.", 0
txt_of:          .byte " of ", 0
txt_tests_passed2: .byte " tests passed.", 0
txt_failures_in: .byte " failures in ", 0
txt_failure_in:  .byte " failure in ", 0
txt_groups:      .byte " groups: ", 0
txt_group1:      .byte " group: ", 0
txt_and_more:    .byte "and ", 0
txt_more:        .byte " more", 0
txt_spc_prefix:  .byte "SPC ", 0
txt_not_run1:    .byte " SPC tests were not run because the SPC-700 stopped responding.", 0
txt_not_sel1:    .byte "Not selected: ", 0
txt_not_sel2:    .byte " tests (groups left unchecked or filtered out).", 0
txt_limit1:      .byte "Only the first ", 0
txt_limit2:      .byte " failures are listed in detail.", 0
txt_back:        .byte "<< Back to menu", 0
txt_report_title: .byte "Report", 0
txt_rhint1:      .byte "A:details  Up/Down:select", 0
txt_rhint2:      .byte "START:back to menu", 0
txt_dhint1:      .byte "L/R:previous/next failure", 0
txt_dhint2:      .byte "A or B:back to the list", 0
txt_spc_unresp_item: .byte "SPC-700 unresponsive", 0
; -- details
txt_cpu_test:    .byte "CPU test #", 0
txt_spc_test:    .byte "SPC test #", 0
txt_dash:        .byte " - ", 0
txt_with:        .byte " with ", 0
txt_8bit_acc:    .byte "8-bit accumulator", 0
txt_16bit_acc:   .byte "16-bit accumulator", 0
txt_8bit_idx:    .byte "8-bit index registers", 0
txt_16bit_idx:   .byte "16-bit index registers", 0
txt_native:      .byte "native mode", 0
txt_emulation:   .byte " in emulation mode (E=1)", 0
txt_spc_p1:      .byte " with the P flag set (direct page 1)", 0
txt_inputs:      .byte " Inputs: ", 0
txt_inp_a:       .byte "A=$", 0
txt_inp_x:       .byte " X=$", 0
txt_inp_y:       .byte " Y=$", 0
txt_inp_p:       .byte " P=$", 0
txt_inp_s:       .byte " S=$", 0
txt_inp_d:       .byte " D=$", 0
txt_inp_dbr:     .byte " DBR=$", 0
txt_was:         .byte " was $", 0
txt_but:         .byte " but $", 0
txt_was_expected: .byte " was expected", 0
txt_flag_pre:    .byte ": the ", 0
txt_flag_pre2:   .byte "; the ", 0
txt_flag:        .byte " flag was ", 0
txt_set:         .byte "set", 0
txt_clear:       .byte "clear", 0
txt_but_should:  .byte " but should be ", 0
txt_memory_at:   .byte " Memory at $", 0
txt_mem_was:     .byte " was $", 0
txt_mem_expected: .byte "; expected $", 0
txt_ctrl:        .byte " A branch or jump went the wrong way: code that should have been skipped was executed.", 0
txt_order1:      .byte " was entered out of order (the previous test was #", 0
txt_order2:      .byte "): probably an errant jump.", 0
txt_brk:         .byte " An unexpected BRK instruction was executed.", 0
txt_cop:         .byte " An unexpected COP instruction was executed.", 0
txt_hang_cpu:    .byte " never finished (hang) - testing resumed after the reset.", 0
txt_hang_spc:    .byte " stopped responding (hang) - the SPC program was reloaded and testing resumed.", 0
txt_hang_dead:   .byte " stopped responding (hang) and the SPC-700 could not be recovered.", 0
txt_unresp1:     .byte "The SPC-700 stopped responding; ", 0
txt_unresp2:     .byte " SPC tests were not run.", 0
txt_note_undoc:  .byte " Note: this test covers undocumented behavior.", 0
txt_note_dec:    .byte " Note: decimal mode is partly undocumented.", 0
txt_dot:         .byte ".", 0
txt_space:       .byte " ", 0
txt_comma_space: .byte ", ", 0
txt_open_paren:  .byte " (", 0
txt_close_paren: .byte ")", 0

; flag names, by bit
cpu_flag_names: .word fn_c, fn_z, fn_i, fn_d, fn_x, fn_m, fn_v, fn_n, fn_e
spc_flag_names: .word fn_c, fn_z, fn_si, fn_h, fn_b, fn_p, fn_v, fn_n
fn_c:  .byte "Carry (C)", 0
fn_z:  .byte "Zero (Z)", 0
fn_i:  .byte "IRQ disable (I)", 0
fn_si: .byte "Interrupt enable (I)", 0
fn_d:  .byte "Decimal (D)", 0
fn_x:  .byte "Index size (X)", 0
fn_m:  .byte "Accumulator size (M)", 0
fn_v:  .byte "Overflow (V)", 0
fn_n:  .byte "Negative (N)", 0
fn_e:  .byte "Emulation (E)", 0
fn_h:  .byte "Half-carry (H)", 0
fn_b:  .byte "Break (B)", 0
fn_p:  .byte "Direct page (P)", 0

; names of the registers by kind of check (CHK_X..CHK_D)
reg_names: .word 0, rn_x, rn_y, rn_p, rn_a, rn_s, rn_dbr, rn_d
rn_x: .byte "X", 0
rn_y: .byte "Y", 0
rn_p: .byte "P", 0
rn_a: .byte "A", 0
rn_s: .byte "S", 0
rn_sp: .byte "SP", 0
rn_dbr: .byte "DBR", 0
rn_d: .byte "D", 0

.segment "CODE"

; --- message buffer ----------------------------------------------------------------------------------------

mb_init:
	A16
	stz mb_pos
	A8
	rts

mb_term:
	A16
	lda mb_pos
	tax
	A8
	lda #0
	sta f:MSGBUF,x
	rts

mb_char:
	phx
	pha
	A16
	lda mb_pos
	tax
	A8
	pla
	sta f:MSGBUF,x
	inx
	stx mb_pos
	plx
	rts

mb_str0:
	stx tptr
	stz tptr+2
	bra mb_str

mb_strf:
	stx tptr
	lda #^strings_marker
	sta tptr+2
mb_str:
	ldy #0
@loop:
	lda [tptr],y
	beq @end
	jsr mb_char
	iny
	bra @loop
@end:
	rts

mb_nibble:
	and #$0F
	clc
	adc #'0'
	cmp #':'
	bcc @ok
	adc #6
@ok:
	jmp mb_char

mb_hex8:
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr mb_nibble
	pla
	jmp mb_nibble

mb_hex16:
	A16
	pha
	xba
	A8
	jsr mb_hex8
	A16
	pla
	A8
	jmp mb_hex8

; A (16 bits) in decimal, with commas as thousands separators if commas = 1 (in r_cnt)
mb_dec:
	ldx #0
	bra mb_dec_common
mb_dec_commas:
	ldx #1
mb_dec_common:
	stx mb_comma
	jsr dec_to_buf
	ldx #0
@loop:
	cpx #2
	bne @digit
	lda mb_comma
	beq @digit
	lda numbuf+1
	cmp #' '
	beq @digit
	lda #','
	jsr mb_char
@digit:
	lda numbuf,x
	cmp #' '
	beq @skip
	jsr mb_char
@skip:
	inx
	cpx #5
	bne @loop
	rts

; --- entries -------------------------------------------------------------------------------------------------

; Loads the failure number A (16 bits: index in rsv_fails) into the e_* variables and finds the record of the test
r_load_entry:
	A16
	sta r_i
	asl a
	asl a
	sta r_tmp
	lda r_i
	asl a
	asl a
	asl a
	clc
	adc r_tmp
	tax
	lda f:rsv_fails+FE_TEST,x
	sta e_test
	lda f:rsv_fails+FE_ACTUAL,x
	sta e_actual
	lda f:rsv_fails+FE_EXPECTED,x
	sta e_expected
	lda f:rsv_fails+FE_ADDR,x
	sta e_addr
	A8
	lda f:rsv_fails+FE_KIND,x
	sta e_kind
	lda f:rsv_fails+FE_GROUP,x
	sta e_group
	lda f:rsv_fails+FE_BANK,x
	sta e_bank
	lda e_kind
	and #FAIL_SPC
	sta e_spc
	lda e_kind
	and #$7F
	sta e_kind
	; record of the test
	stz e_p
	stz e_tags
	lda e_kind
	cmp #CHK_UNRESP
	beq @done
	lda e_spc
	bne @spc
	A16
	lda e_test
	asl a
	asl a
	asl a
	asl a
	sta e_rec
	tax
	A8
	lda f:cpu_records+8,x
	sta e_p
	lda f:cpu_records+9,x
	sta e_tags
	rts
@spc:
	A16
	lda e_test
	asl a
	asl a
	asl a
	sta e_rec
	tax
	A8
	lda f:spc_records+5,x
	sta e_p
	lda f:spc_records+6,x
	sta e_tags
@done:
	A8
	rts

; Appends the name of the group of the entry
mb_group_name:
	A16
	lda e_group
	and #$00FF
	asl a
	asl a
	asl a
	tax
	A8
	lda e_spc
	bne @spc
	A16
	lda f:cpu_groups,x
	tax
	A8
	jmp mb_strf
@spc:
	A16
	lda f:spc_groups,x
	tax
	A8
	jmp mb_strf

; Appends the instruction text of the test
mb_ins:
	A16
	lda e_rec
	tax
	A8
	lda e_spc
	bne @spc
	A16
	lda f:cpu_records,x
	tax
	A8
	jmp mb_strf
@spc:
	A16
	lda f:spc_records,x
	tax
	A8
	jmp mb_strf

; "CPU test #0123 (ADC)"
mb_test_title:
	lda e_spc
	bne @spc
	ldx #txt_cpu_test
	bra @go
@spc:
	ldx #txt_spc_test
@go:
	jsr mb_str0
	A16
	lda e_test
	jsr mb_hex16
	A8
	ldx #txt_open_paren
	jsr mb_str0
	jsr mb_group_name
	ldx #txt_close_paren
	jmp mb_str0

; Composes the description of the failure that is loaded in e_*
compose_detail:
	A8
	XY16
	jsr mb_init
	lda e_kind
	cmp #CHK_UNRESP
	bne @not_unresp
	ldx #txt_unresp1
	jsr mb_str0
	A16
	lda e_expected
	jsr mb_dec_commas
	A8
	ldx #txt_unresp2
	jsr mb_str0
	jmp mb_term
@not_unresp:
	cmp #CHK_ORDER
	bne @test_kinds
	jsr mb_test_title
	ldx #txt_order1
	jsr mb_str0
	A16
	lda e_actual
	jsr mb_hex16
	A8
	ldx #txt_order2
	jsr mb_str0
	jmp @notes
@test_kinds:
	jsr mb_test_title
	ldx #txt_dash
	jsr mb_str0
	lda #'"'
	jsr mb_char
	jsr mb_ins
	lda #'"'
	jsr mb_char
	lda e_kind
	cmp #CHK_HANG
	bne @with_inputs
	; hang
	lda e_spc
	bne @hang_spc
	ldx #txt_hang_cpu
	jsr mb_str0
	jmp @notes
@hang_spc:
	; if the next failure is "unresponsive", the SPC wasn't recovered
	ldx #txt_hang_spc
	stx r_msgptr
	A16
	lda r_sel
	inc a
	cmp f:rsv_fail_count
	A8
	bcs @hang_spc_text
	A16
	lda r_sel
	inc a
	jsr r_kind_of
	.a8                    ; r_kind_of returns with A=8 bits
	cmp #CHK_UNRESP
	bne @hang_spc_text
	ldx #txt_hang_dead
	stx r_msgptr
@hang_spc_text:
	ldx r_msgptr
	jsr mb_str0
	jmp @notes
@with_inputs:
	jsr mb_mode
	ldx #txt_dot
	jsr mb_str0
	jsr mb_inputs
	ldx #txt_dot
	jsr mb_str0
	lda e_kind
	cmp #CHK_CTRL
	bne @not_ctrl
	ldx #txt_ctrl
	jsr mb_str0
	jmp @notes
@not_ctrl:
	cmp #CHK_BRK
	bne @not_brk
	ldx #txt_brk
	jsr mb_str0
	jmp @notes
@not_brk:
	cmp #CHK_COP
	bne @not_cop
	ldx #txt_cop
	jsr mb_str0
	jmp @notes
@not_cop:
	cmp #CHK_MEM
	bne @register
	ldx #txt_memory_at
	jsr mb_str0
	lda e_spc
	bne @mem_addr16
	lda e_bank
	jsr mb_hex8
@mem_addr16:
	A16
	lda e_addr
	jsr mb_hex16
	A8
	ldx #txt_mem_was
	jsr mb_str0
	lda e_actual
	jsr mb_hex8
	ldx #txt_mem_expected
	jsr mb_str0
	lda e_expected
	jsr mb_hex8
	ldx #txt_dot
	jsr mb_str0
	jmp @notes
@register:
	; "A was $1100 but $1101 was expected"
	lda #' '
	jsr mb_char
	lda e_kind
	cmp #CHK_S
	bne @reg_name
	lda e_spc
	beq @reg_name
	ldx #rn_sp
	bra @reg_print
@reg_name:
	A16
	lda e_kind
	and #$00FF
	asl a
	tax
	lda reg_names,x
	tax
	A8
@reg_print:
	jsr mb_str0
	ldx #txt_was
	jsr mb_str0
	jsr mb_reg_value_actual
	ldx #txt_but
	jsr mb_str0
	jsr mb_reg_value_expected
	ldx #txt_was_expected
	jsr mb_str0
	lda e_kind
	cmp #CHK_P
	bne @reg_end
	jsr mb_flag_diff
@reg_end:
	ldx #txt_dot
	jsr mb_str0
@notes:
	; notes for tests that cover undocumented behavior
	lda e_tags
	and #TAG_UNDOCUMENTED
	beq @no_undoc
	ldx #txt_note_undoc
	jsr mb_str0
@no_undoc:
	lda e_spc
	bne @done
	lda e_tags
	and #TAG_DECIMAL
	beq @done
	ldx #txt_note_dec
	jsr mb_str0
@done:
	jmp mb_term

; Kind of the entry A (16 bits) of the failure list -> A (8 bits), without the SPC bit
r_kind_of:
	sta r_i
	asl a
	asl a
	sta r_tmp
	lda r_i
	asl a
	asl a
	asl a
	clc
	adc r_tmp
	tax
	A8
	lda f:rsv_fails+FE_KIND,x
	and #$7F
	rts

; Value of the register of the failure: 16 bits (4 digits) for the CPU, except P and DBR; 8 bits for the SPC
mb_reg_value_actual:
	A16
	lda e_actual
	bra mb_reg_value
mb_reg_value_expected:
	A16
	lda e_expected
mb_reg_value:
	pha
	A8
	lda e_spc
	bne @byte
	lda e_kind
	cmp #CHK_P
	beq @byte
	cmp #CHK_DBR
	beq @byte
	A16
	pla
	jsr mb_hex16
	A8
	rts
@byte:
	A16
	pla
	A8
	jmp mb_hex8

; ": the Zero (Z) flag was set but should be clear; the ..."
mb_flag_diff:
	A16
	lda e_actual
	eor e_expected
	sta r_j
	A8
	stz r_buf          ; flag counter
	stz r_buf+1        ; bit number
@loop:
	lda r_buf+1
	cmp #9
	jcs @end
	lda e_spc
	beq @cpu_bits
	lda r_buf+1
	cmp #8
	jcs @end
@cpu_bits:
	A16
	lda r_buf+1
	and #$00FF
	tax
	lda r_j
@shift:
	cpx #0
	beq @shifted
	lsr a
	dex
	bra @shift
@shifted:
	A8
	and #$01
	jeq @next
	; this flag differs
	lda r_buf
	bne @sep
	ldx #txt_flag_pre
	bra @pre
@sep:
	ldx #txt_flag_pre2
@pre:
	jsr mb_str0
	inc r_buf
	A16
	lda r_buf+1
	and #$00FF
	asl a
	tax
	A8
	lda e_spc
	bne @spc_name
	A16
	lda cpu_flag_names,x
	tax
	A8
	bra @name
@spc_name:
	A16
	lda spc_flag_names,x
	tax
	A8
@name:
	jsr mb_str0
	ldx #txt_flag
	jsr mb_str0
	; was it set in the actual value?
	A16
	lda r_buf+1
	and #$00FF
	tax
	lda e_actual
@shift2:
	cpx #0
	beq @shifted2
	lsr a
	dex
	bra @shift2
@shifted2:
	A8
	and #$01
	beq @was_clear
	ldx #txt_set
	jsr mb_str0
	ldx #txt_but_should
	jsr mb_str0
	ldx #txt_clear
	jsr mb_str0
	bra @next
@was_clear:
	ldx #txt_clear
	jsr mb_str0
	ldx #txt_but_should
	jsr mb_str0
	ldx #txt_set
	jsr mb_str0
@next:
	inc r_buf+1
	jmp @loop
@end:
	rts

; " with 8-bit accumulator, 16-bit index registers, native mode" / " in emulation mode (E=1)"
mb_mode:
	lda e_spc
	bne @spc
	lda e_tags
	and #TAG_EMULATION
	beq @native
	ldx #txt_emulation
	jmp mb_str0
@native:
	ldx #txt_with
	jsr mb_str0
	lda e_p
	and #$20
	beq @acc16
	ldx #txt_8bit_acc
	bra @acc
@acc16:
	ldx #txt_16bit_acc
@acc:
	jsr mb_str0
	ldx #txt_comma_space
	jsr mb_str0
	lda e_p
	and #$10
	beq @idx16
	ldx #txt_8bit_idx
	bra @idx
@idx16:
	ldx #txt_16bit_idx
@idx:
	jsr mb_str0
	ldx #txt_comma_space
	jsr mb_str0
	ldx #txt_native
	jmp mb_str0
@spc:
	lda e_p
	and #$20
	beq @no_p
	ldx #txt_spc_p1
	jmp mb_str0
@no_p:
	rts

; " Inputs: A=$1234 X=$3456 Y=$5678 P=$31 [S=$.... D=$.... DBR=$..]"
mb_inputs:
	ldx #txt_inputs
	jsr mb_str0
	A16
	lda e_rec
	tax
	A8
	lda e_spc
	jne @spc
	ldx #txt_inp_a
	jsr mb_str0
	A16
	lda e_rec
	tax
	lda f:cpu_records+2,x
	jsr mb_hex16
	ldx #txt_inp_x
	A8
	jsr mb_str0
	A16
	lda e_rec
	tax
	lda f:cpu_records+4,x
	jsr mb_hex16
	ldx #txt_inp_y
	A8
	jsr mb_str0
	A16
	lda e_rec
	tax
	lda f:cpu_records+6,x
	jsr mb_hex16
	ldx #txt_inp_p
	A8
	jsr mb_str0
	lda e_p
	jsr mb_hex8
	lda e_tags
	and #HAS_S
	beq @no_s
	ldx #txt_inp_s
	jsr mb_str0
	A16
	lda e_rec
	tax
	lda f:cpu_records+10,x
	jsr mb_hex16
	A8
@no_s:
	lda e_tags
	and #HAS_D
	beq @no_d
	ldx #txt_inp_d
	jsr mb_str0
	A16
	lda e_rec
	tax
	lda f:cpu_records+12,x
	jsr mb_hex16
	A8
@no_d:
	lda e_tags
	and #HAS_DBR
	beq @end
	ldx #txt_inp_dbr
	jsr mb_str0
	A16
	lda e_rec
	tax
	A8
	lda f:cpu_records+14,x
	jsr mb_hex8
@end:
	rts
@spc:
	ldx #txt_inp_a
	jsr mb_str0
	A16
	lda e_rec
	tax
	A8
	lda f:spc_records+2,x
	jsr mb_hex8
	ldx #txt_inp_x
	jsr mb_str0
	A16
	lda e_rec
	tax
	A8
	lda f:spc_records+3,x
	jsr mb_hex8
	ldx #txt_inp_y
	jsr mb_str0
	A16
	lda e_rec
	tax
	A8
	lda f:spc_records+4,x
	jsr mb_hex8
	ldx #txt_inp_p
	jsr mb_str0
	lda e_p
	jsr mb_hex8
	rts

; --- summary -------------------------------------------------------------------------------------------------

; Total of failed tests -> A (16 bits)
r_failed_total:
	A16
	lda f:rsv_fail_cpu
	clc
	adc f:rsv_fail_spc
	A8
	rts

; Prints the NUL-terminated message in MSGBUF with word wrap at the current position (wrow/wcol)
r_print_msg:
	ldx #.loword(MSGBUF)
	stx tptr
	lda #^MSGBUF
	sta tptr+2
	jmp txt_wrap

; Starts a new line of the wrapped text if not already at the start of one
r_newline:
	lda wcol
	cmp wrap_x0
	beq @done
	jsr wrap_newline
@done:
	rts

; Draws the summary starting at row 3
draw_summary:
	A8
	XY16
	lda #1
	sta wrap_x0
	lda #31
	sta wrap_x1
	lda #3
	sta wrow
	lda #1
	sta wcol
	ldx #1
	ldy #3
	lda #0
	jsr txt_at
	; sentence 1
	jsr r_failed_total
	A16
	cmp #0
	A8
	bne @some_failed
	; no failures, but if some SPC tests were not run, "All N tests passed" would be wrong
	A16
	lda f:rsv_notrun
	A8
	beq @all_passed
	lda #ST_WARN
	jsr txt_style
	jsr mb_init
	A16
	lda f:rsv_cpu_done
	clc
	adc f:rsv_spc_done
	jsr mb_dec_commas
	A8
	ldx #txt_of
	jsr mb_str0
	A16
	lda f:rsv_cpu_total
	clc
	adc f:rsv_spc_total
	jsr mb_dec_commas
	A8
	ldx #txt_tests_passed2
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
	jmp @after1
@all_passed:
	lda #ST_PASS
	jsr txt_style
	jsr mb_init
	ldx #txt_all_passed
	jsr mb_str0
	A16
	lda f:rsv_cpu_total
	clc
	adc f:rsv_spc_total
	jsr mb_dec_commas
	A8
	ldx #txt_tests_passed
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
	jmp @after1
@some_failed:
	lda #ST_FAIL
	jsr txt_style
	jsr mb_init
	; passed = tests started - failed tests
	A16
	lda f:rsv_cpu_done
	clc
	adc f:rsv_spc_done
	sec
	sbc f:rsv_fail_cpu
	sbc f:rsv_fail_spc
	jsr mb_dec_commas
	A8
	ldx #txt_of
	jsr mb_str0
	A16
	lda f:rsv_cpu_total
	clc
	adc f:rsv_spc_total
	jsr mb_dec_commas
	A8
	ldx #txt_tests_passed2
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
	jsr r_newline
	; N failures in M groups: ...
	jsr mb_init
	jsr r_failed_total
	A16
	jsr mb_dec_commas
	A8
	jsr r_count_groups
	A16
	lda r_groups
	cmp #1
	A8
	bne @plural
	ldx #txt_failure_in
	bra @fi
@plural:
	ldx #txt_failures_in
@fi:
	; "1 failure in 1 group" / "N failures in M groups"
	A16
	lda f:rsv_fail_cpu
	clc
	adc f:rsv_fail_spc
	cmp #1
	A8
	beq @singular_failure
	ldx #txt_failures_in
	bra @fi2
@singular_failure:
	ldx #txt_failure_in
@fi2:
	jsr mb_str0
	A16
	lda r_groups
	jsr mb_dec
	A8
	A16
	lda r_groups
	cmp #1
	A8
	beq @group_singular
	ldx #txt_groups
	bra @gs
@group_singular:
	ldx #txt_group1
@gs:
	jsr mb_str0
	jsr r_list_groups
	jsr mb_term
	jsr r_print_msg
@after1:
	lda #ST_WARN
	jsr txt_style
	; SPC tests not run
	A16
	lda f:rsv_notrun
	A8
	beq @no_notrun
	A16
	lda f:rsv_notrun
	A8
	jsr r_newline
	jsr mb_init
	A16
	lda f:rsv_notrun
	jsr mb_dec_commas
	A8
	ldx #txt_not_run1
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
@no_notrun:
	; not selected
	A16
	lda #SPC_TEST_COUNT+CPU_TEST_COUNT
	sec
	sbc f:rsv_spc_total
	sbc f:rsv_cpu_total
	sta r_cnt
	A8
	beq @none_unselected
	A16
	lda r_cnt
	A8
	jsr r_newline
	lda #ST_DIM
	jsr txt_style
	jsr mb_init
	ldx #txt_not_sel1
	jsr mb_str0
	A16
	lda r_cnt
	jsr mb_dec_commas
	A8
	ldx #txt_not_sel2
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
@none_unselected:
	; limit of detailed failures
	A16
	lda f:rsv_fail_cpu
	clc
	adc f:rsv_fail_spc
	cmp #FAIL_MAX+1
	A8
	bcc @done
	jsr r_newline
	lda #ST_WARN
	jsr txt_style
	jsr mb_init
	ldx #txt_limit1
	jsr mb_str0
	A16
	lda #FAIL_MAX
	jsr mb_dec_commas
	A8
	ldx #txt_limit2
	jsr mb_str0
	jsr mb_term
	jsr r_print_msg
@done:
	rts

; r_groups = number of groups that have failures (CPU and SPC)
r_count_groups:
	A16
	stz r_groups
	ldx #0
@cpu:
	lda f:rsv_group_fail_cpu,x
	beq @c_next
	inc r_groups
@c_next:
	inx
	inx
	cpx #MAX_GROUPS*2
	bne @cpu
	ldx #0
@spc:
	lda f:rsv_group_fail_spc,x
	beq @s_next
	inc r_groups
@s_next:
	inx
	inx
	cpx #MAX_GROUPS*2
	bne @spc
	A8
	rts

; Appends "MVN (5), PLB (1), SPC DIV (2)" (the first groups; "and N more" for the rest)
r_list_groups:
	A16
	stz r_cnt              ; groups listed
	A8
	ldx #0
	stx r_i
@cpu:
	A16
	lda r_i
	asl a
	tax
	lda f:rsv_group_fail_cpu,x
	A8
	beq @c_next
	A16
	sta r_j
	A8
	lda #0
	jsr r_list_one
@c_next:
	ldx r_i
	inx
	stx r_i
	cpx #CPU_GROUP_COUNT
	bne @cpu
	ldx #0
	stx r_i
@spc:
	A16
	lda r_i
	asl a
	tax
	lda f:rsv_group_fail_spc,x
	A8
	beq @s_next
	A16
	sta r_j
	A8
	lda #1
	jsr r_list_one
@s_next:
	ldx r_i
	inx
	stx r_i
	cpx #SPC_GROUP_COUNT
	bne @spc
	; the ones that were not listed
	A16
	lda r_groups
	sec
	sbc r_cnt
	A8
	beq @end
	ldx #txt_comma_space
	jsr mb_str0
	ldx #txt_and_more
	jsr mb_str0
	A16
	lda r_groups
	sec
	sbc r_cnt
	jsr mb_dec
	A8
	ldx #txt_more
	jsr mb_str0
@end:
	rts

; A = 0 (CPU) / 1 (SPC): appends group r_i with r_j failures, if there is room (6 groups)
r_list_one:
	sta r_buf+2
	A16
	lda r_cnt
	cmp #6
	A8
	bcs @skip
	A16
	lda r_cnt
	A8
	beq @first
	ldx #txt_comma_space
	jsr mb_str0
@first:
	lda r_buf+2
	beq @cpu_name
	ldx #txt_spc_prefix
	jsr mb_str0
@cpu_name:
	A16
	lda r_i
	asl a
	asl a
	asl a
	tax
	A8
	lda r_buf+2
	bne @spc_group_name
	A16
	lda f:cpu_groups,x
	tax
	A8
	bra @name
@spc_group_name:
	A16
	lda f:spc_groups,x
	tax
	A8
@name:
	jsr mb_strf
	ldx #txt_open_paren
	jsr mb_str0
	A16
	lda r_j
	jsr mb_dec
	A8
	ldx #txt_close_paren
	jsr mb_str0
	A16
	inc r_cnt
	A8
@skip:
	rts

; --- screen ----------------------------------------------------------------------------------------------------

; Draws one row of the list: entry r_i (or BACK_TO_MENU) at the row Y
r_draw_row:
	A16
	lda r_i
	cmp r_n
	A8
	bcc @entry
	; "<< Back to menu"
	jsr r_row_style
	ldx #1
	lda #0
	jsr txt_at
	lda #' '
	jsr txt_putc
	ldx #txt_back
	jsr txt_puts0
	jmp txt_clear_eol
@entry:
	jsr r_row_style
	ldx #1
	lda #0
	jsr txt_at
	A16
	lda r_i
	jsr r_load_entry
	A8
	lda #' '
	jsr txt_putc
	lda e_kind
	cmp #CHK_UNRESP
	bne @normal
	ldx #txt_spc_unresp_item
	jsr txt_puts0
	jmp txt_clear_eol
@normal:
	lda e_spc
	bne @spc
	ldx #txt_cpu_short
	bra @who
@spc:
	ldx #txt_spc_short
@who:
	jsr txt_puts0
	A16
	lda e_test
	jsr txt_hex16
	A8
	lda #' '
	jsr txt_putc
	A16
	lda e_rec
	tax
	A8
	lda e_spc
	bne @spc_ins
	A16
	lda f:cpu_records,x
	tax
	A8
	bra @ins
@spc_ins:
	A16
	lda f:spc_records,x
	tax
	A8
@ins:
	lda #20
	jsr txt_putsf_n
	jmp txt_clear_eol

.segment "RODATA"
txt_cpu_short: .byte "CPU #", 0
txt_spc_short: .byte "SPC #", 0
.segment "CODE"

; Style of the row r_i: accent if selected, else failure color. Y = screen row (kept)
r_row_style:
	A16
	lda r_i
	cmp r_sel
	A8
	bne @normal
	lda #ST_ACCENT
	jmp txt_style
@normal:
	lda #ST_NORMAL
	jmp txt_style

; Draws the list part of the screen (rows r_list_top to REPORT_LIST_END)
r_draw_list:
	A8
	ldy #0
	; scroll: keep the selection visible
	A16
	lda r_sel
	cmp r_scroll
	bcs @not_above
	sta r_scroll
@not_above:
	lda #REPORT_LIST_END
	sec
	sbc r_list_top2
	inc a                 ; rows available
	sta r_rows
	lda r_sel
	sec
	sbc r_scroll
	cmp r_rows
	bcc @visible
	lda r_sel
	sec
	sbc r_rows
	inc a
	sta r_scroll
@visible:
	A8
	stz r_buf+3           ; row counter
@row:
	A16
	lda r_buf+3
	and #$00FF
	cmp r_rows
	A8
	bcs @done
	A16
	lda r_buf+3
	and #$00FF
	clc
	adc r_scroll
	sta r_i
	lda r_buf+3
	and #$00FF
	clc
	adc r_list_top2
	tay
	A8
	phy
	A16
	lda r_i
	cmp r_n
	A8
	bcc @draw
	beq @draw
	; beyond the "back" item: blank row
	ply
	ldx #0
	lda #0
	jsr txt_at
	lda #32
	ldx #' '
	jsr txt_fill
	bra @next
@draw:
	ply
	jsr r_draw_row
@next:
	inc r_buf+3
	bra @row
@done:
	rts

; Cursor sprite at the selected row of the list
r_cursor:
	A16
	lda r_sel
	sec
	sbc r_scroll
	clc
	adc r_list_top2
	asl a
	asl a
	asl a
	dec a
	A8
	sta f:OAM_SHADOW+1
	lda m_anim
	lsr a
	lsr a
	lsr a
	lsr a
	and #$01
	sta f:OAM_SHADOW+2
	lda #0
	sta f:OAM_SHADOW+0
	lda #$30
	sta f:OAM_SHADOW+3
	rts

; Shows the report. Returns when the user goes back to the menu.
report_enter:
	A8
	XY16
	jsr nmi_off
	jsr screen_off
	jsr ui_clear
	jsr oam_clear
	jsr draw_header
	jsr draw_summary
	; list area: from the row after the summary
	A16
	lda f:rsv_fail_count
	sta r_n
	A8
	lda wrow
	clc
	adc #2
	cmp #REPORT_LIST_END-3
	bcc @top_ok
	lda #REPORT_LIST_END-3
@top_ok:
	sta r_list_top2
	A16
	stz r_sel
	stz r_scroll
	A8
	stz r_mode
	stz m_anim
	; hints
	jsr r_draw_hints
	jsr r_draw_list
	jsr ui_flush
	jsr screen_on
	jsr nmi_on

@loop:
	jsr wait_frame
	jsr get_pad
	sta m_pad
	A8
	inc m_anim
	lda r_mode
	jne @detail_mode
	; --- list
	A16
	lda m_pad
	and #PAD_START
	A8
	beq @l1
	jmp @exit
@l1:
	A16
	lda m_pad
	and #PAD_DOWN
	A8
	beq @l2
	A16
	lda r_sel
	cmp r_n               ; the "back" item has index r_n
	bcs @l2_wrap_to_top
	inc a
	bra @l_set
@l2_wrap_to_top:
	lda #0
	bra @l_set
@l2:
	A16
	lda m_pad
	and #PAD_UP
	A8
	beq @l3
	A16
	lda r_sel
	beq @l2_wrap_to_end
	dec a
	bra @l_set
@l2_wrap_to_end:
	lda r_n
	bra @l_set
@l3:
	A16
	lda m_pad
	and #PAD_R
	A8
	beq @l4
	A16
	lda r_sel
	clc
	adc #8
	cmp r_n
	bcc @l_set
	lda r_n
	bra @l_set
@l4:
	A16
	lda m_pad
	and #PAD_L
	A8
	beq @l5
	A16
	lda r_sel
	sec
	sbc #8
	bcs @l_set
	lda #0
	bra @l_set
@l5:
	A16
	lda m_pad
	and #PAD_A
	A8
	beq @l_cursor
	A16
	lda r_sel
	cmp r_n
	A8
	bcs @exit             ; "back to menu"
	; open the detail
	lda #1
	sta r_mode
	jsr r_show_detail
	jmp @loop
@l_set:
	A16
	sta r_sel
	A8
	jsr r_draw_list
@l_cursor:
	jsr r_cursor
	jmp @loop
	; --- detail
@detail_mode:
	A16
	lda m_pad
	and #PAD_A|PAD_B|PAD_START
	A8
	beq @d1
	stz r_mode
	jsr r_back_to_list
	jmp @loop
@d1:
	A16
	lda m_pad
	and #PAD_R
	A8
	beq @d2
	A16
	lda r_sel
	inc a
	cmp r_n
	A8
	bcs @d_loop
	A16
	inc r_sel
	A8
	jsr r_show_detail
	bra @d_loop
@d2:
	A16
	lda m_pad
	and #PAD_L
	A8
	beq @d_loop
	A16
	lda r_sel
	A8
	beq @d_loop
	A16
	dec r_sel
	A8
	jsr r_show_detail
@d_loop:
	jmp @loop
@exit:
	jsr nmi_off
	rts

r_draw_hints:
	lda #ST_DIM
	jsr txt_style
	ldx #1
	ldy #26
	lda #1
	jsr txt_at
	ldx #txt_rhint1
	jsr txt_puts0
	jsr txt_clear_eol
	ldx #1
	ldy #27
	lda #1
	jsr txt_at
	ldx #txt_rhint2
	jsr txt_puts0
	jsr txt_clear_eol
	lda #1
	sta bg3_dirty
	rts

; Clears the content area (rows 3-24) of BG1
r_clear_content:
	A8
	ldx #0
	ldy #3
	lda #0
	jsr txt_at
	ldy #22
@row:
	lda #32
	ldx #' '
	phy
	jsr txt_fill
	ply
	dey
	bne @row
	rts

; Shows the description of the failure r_sel on the whole content area
r_show_detail:
	A8
	XY16
	jsr r_clear_content
	A16
	lda r_sel
	jsr r_load_entry
	A8
	jsr compose_detail
	lda #1
	sta wrap_x0
	lda #31
	sta wrap_x1
	lda #3
	sta wrow
	lda #1
	sta wcol
	ldx #1
	ldy #3
	lda #0
	jsr txt_at
	lda #ST_NORMAL
	jsr txt_style
	jsr r_print_msg
	; hints
	lda #ST_DIM
	jsr txt_style
	ldx #1
	ldy #26
	lda #1
	jsr txt_at
	ldx #txt_dhint1
	jsr txt_puts0
	jsr txt_clear_eol
	ldx #1
	ldy #27
	lda #1
	jsr txt_at
	ldx #txt_dhint2
	jsr txt_puts0
	jsr txt_clear_eol
	lda #1
	sta bg3_dirty
	; hide the cursor
	lda #$F0
	sta f:OAM_SHADOW+1
	rts

; Back to the summary and the list
r_back_to_list:
	A8
	XY16
	jsr r_clear_content
	jsr draw_summary
	jsr r_draw_hints
	jmp r_draw_list
