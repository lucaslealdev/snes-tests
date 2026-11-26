; Selection menu.
;
; A scrolling list: three filters (Emulation mode, Undocumented behavior, Decimal mode), "Select all/none", and
; two collapsible categories (SPC-700, 65C816) with one checkbox per group of tests. The item "Start tests" is
; fixed under the list. Controls: Up/Down move, L/R page, A activates (toggle, expand/collapse, start),
; Y toggles the checkbox (on a category: all its groups), X toggles all the groups of the category of the item,
; Start runs the tests. The first time the menu is shown after power on there is an auto-start after 10 s
; (any button cancels it), so the ROM can be used without a controller.
;
; Items are 16 bit values in the list at UI_WORK: low byte = type, high byte = index.

ITEM_FILTER = 0
ITEM_ALL    = 1
ITEM_NONE   = 2
ITEM_CAT    = 3
ITEM_GSPC   = 4
ITEM_GCPU   = 5

LIST_ROWS = 21
LIST_TOP  = 3
START_ROW = 24
AUTOSTART_FRAMES = 600

.segment "RODATA"
txt_subtitle:  .byte "Choose the tests to run", 0
txt_filter0:   .byte "Emulation mode (E=1)", 0
txt_filter1:   .byte "Undocumented behavior", 0
txt_filter2:   .byte "Decimal mode (D=1)", 0
filter_names:  .word txt_filter0, txt_filter1, txt_filter2
txt_all:       .byte "Select all tests", 0
txt_none_item: .byte "Select no tests", 0
txt_cat_spc:   .byte "SPC-700 instructions", 0
txt_cat_cpu:   .byte "65C816 instructions", 0
txt_start:     .byte ">> Start tests", 0
txt_no_tests:  .byte "No tests selected", 0
txt_ft_spc:    .byte "SPC-700: ", 0
txt_ft_cpu:    .byte "  65C816: ", 0
txt_ft_total:  .byte "  Total: ", 0
txt_hint1:     .byte "A:toggle  Y:check  X:category", 0
txt_hint2:     .byte "L/R:page  START:run tests", 0
txt_auto1:     .byte "Auto-start ", 0
txt_auto2:     .byte " s: press any key", 0
txt_tests_word: .byte " tests", 0

.segment "CODE"

; Entered after power on (the first time: auto-start is possible) or after the report / a reset (no auto-start)
menu_enter:
	A8
	XY16
	stz m_auto_on
	lda f:rsv_autostart_used
	bne menu_common
	lda #1
	sta f:rsv_autostart_used
	sta m_auto_on
	ldx #AUTOSTART_FRAMES
	stx m_auto
	lda #$FF
	sta m_auto_sec
	bra menu_common

menu_enter_keep:
	A8
	XY16
	stz m_auto_on

menu_common:
	lda #PHASE_MENU
	sta f:rsv_phase
	jsr nmi_off
	jsr screen_off
	jsr ui_clear
	jsr oam_clear
	jsr draw_header
	lda #ST_DIM
	jsr txt_style
	ldx #1
	ldy #2
	lda #1
	jsr txt_at
	ldx #txt_subtitle
	jsr txt_puts0
	ldx #0
	stx m_cursor
	stx m_scroll
	stx m_exp
	ldx #1
	lda #1
	sta m_exp
	sta m_exp+1
	stz m_anim
	jsr compute_totals
	jsr build_vis
	jsr menu_redraw
	jsr ui_flush
	jsr screen_on
	jsr nmi_on

menu_loop:
	jsr wait_frame
	jsr get_pad
	sta m_pad
	A8
	; animation of the cursor
	inc m_anim
	; auto-start
	lda m_auto_on
	beq @input
	A16
	lda m_pad
	A8
	beq @countdown
	stz m_auto_on         ; any button cancels
	lda #1
	sta m_dirty
	jmp @input_noauto
@countdown:
	ldx m_auto
	dex
	stx m_auto
	bne @auto_tick
	; time is up: start (if something is selected)
	stz m_auto_on
	lda #1
	sta m_dirty
	jsr menu_total
	A16
	cmp #0
	A8
	beq @input
	jmp menu_start
@auto_tick:
	jsr menu_footer_auto
@input_noauto:
@input:
	A16
	lda m_pad
	A8
	bne @has_input
	jmp @refresh
@has_input:
	A16
	lda m_pad
	and #PAD_START
	A8
	beq @no_start
	jsr menu_total
	A16
	cmp #0
	A8
	beq @no_start
	jmp menu_start
@no_start:
	A16
	lda m_pad
	and #PAD_DOWN
	A8
	beq @no_down
	ldx m_cursor
	cpx m_nvis
	bcc @down1
	ldx #0
	jmp @set_cursor
@down1:
	inx
	bra @set_cursor
@no_down:
	A16
	lda m_pad
	and #PAD_UP
	A8
	beq @no_up
	ldx m_cursor
	bne @up1
	ldx m_nvis
	bra @set_cursor
@up1:
	dex
	bra @set_cursor
@no_up:
	A16
	lda m_pad
	and #PAD_R
	A8
	beq @no_r
	A16
	lda m_cursor
	clc
	adc #LIST_ROWS-1
	cmp m_nvis
	bcc @r_ok
	lda m_nvis
@r_ok:
	tax
	A8
	bra @set_cursor
@no_r:
	A16
	lda m_pad
	and #PAD_L
	A8
	beq @no_l
	A16
	lda m_cursor
	sec
	sbc #LIST_ROWS-1
	bcs @l_ok
	lda #0
@l_ok:
	tax
	A8
	bra @set_cursor
@no_l:
	A16
	lda m_pad
	and #PAD_A|PAD_Y
	A8
	beq @no_act
	jsr menu_activate
	jmp @changed
@no_act:
	A16
	lda m_pad
	and #PAD_X
	A8
	beq @refresh
	jsr menu_toggle_category
	jmp @changed
@set_cursor:
	stx m_cursor
	lda #1
	sta m_dirty
	bra @refresh
@changed:
	jsr compute_totals
	jsr state_update_checksum
	lda #1
	sta m_dirty
@refresh:
	lda m_dirty
	beq @cursor
	stz m_dirty
	jsr menu_scroll_fix
	jsr menu_redraw
@cursor:
	jsr menu_cursor
	jmp menu_loop

menu_start:
	jsr nmi_off
	lda #0
	sta f:OAM_SHADOW+1
	jmp start_run

; Total number of tests to run -> A (16 bits)
menu_total:
	A16
	lda f:rsv_cpu_total
	clc
	adc f:rsv_spc_total
	A8
	rts

; Keeps the cursor visible
menu_scroll_fix:
	A16
	lda m_cursor
	cmp m_nvis
	bcs @done                 ; the Start item is not in the list
	cmp m_scroll
	bcs @below_top
	sta m_scroll
	bra @done
@below_top:
	sec
	sbc m_scroll
	cmp #LIST_ROWS
	bcc @done
	lda m_cursor
	sec
	sbc #LIST_ROWS-1
	sta m_scroll
@done:
	A8
	rts

; Rebuilds the list of items from the expanded state of the categories
build_vis:
	A8
	XY16
	A16
	stz m_nvis
	A8
	stz m_i
@filters:
	lda #ITEM_FILTER
	sta m_type
	lda m_i
	sta m_idx
	jsr vis_add
	inc m_i
	lda m_i
	cmp #3
	bne @filters
	lda #ITEM_ALL
	sta m_type
	stz m_idx
	jsr vis_add
	lda #ITEM_NONE
	sta m_type
	jsr vis_add
	; SPC category
	lda #ITEM_CAT
	sta m_type
	stz m_idx
	jsr vis_add
	lda m_exp
	beq @cpu_cat
	lda #ITEM_GSPC
	sta m_type
	stz m_idx
@spc_groups:
	jsr vis_add
	inc m_idx
	lda m_idx
	cmp #<SPC_GROUP_COUNT
	bne @spc_groups
@cpu_cat:
	lda #ITEM_CAT
	sta m_type
	lda #1
	sta m_idx
	jsr vis_add
	lda m_exp+1
	beq @end
	lda #ITEM_GCPU
	sta m_type
	stz m_idx
@cpu_groups:
	jsr vis_add
	inc m_idx
	lda m_idx
	cmp #<CPU_GROUP_COUNT
	bne @cpu_groups
@end:
	rts

vis_add:
	A16
	lda m_nvis
	asl a
	tax
	lda m_type            ; low byte = m_type, high byte = m_idx
	sta f:UI_WORK,x
	inc m_nvis
	A8
	rts

; m_i = item index -> m_type, m_idx
menu_get_item:
	A16
	lda m_i
	asl a
	tax
	lda f:UI_WORK,x
	sta m_type
	A8
	rts

; Draws the whole screen (list, start item, footer)
menu_redraw:
	A8
	XY16
	stz m_row
@row:
	A16
	lda m_row
	and #$00FF
	clc
	adc m_scroll
	sta m_i
	cmp m_nvis
	A8
	bcs @blank
	jsr menu_draw_item
	bra @next
@blank:
	jsr menu_row_at
	lda #32
	ldx #' '
	jsr txt_fill
@next:
	inc m_row
	lda m_row
	cmp #LIST_ROWS
	bne @row
	jsr menu_draw_start
	jmp menu_footer

; Positions the text at the start of the row m_row of the list
menu_row_at:
	A16
	lda m_row
	and #$00FF
	clc
	adc #LIST_TOP
	tay
	A8
	ldx #0
	lda #0
	jmp txt_at

; Draws the item m_i at the row m_row
menu_draw_item:
	jsr menu_get_item
	jsr menu_row_at
	; style
	lda m_type
	cmp #ITEM_CAT
	bne @not_cat
	lda #ST_CAT
	bra @style
@not_cat:
	lda #ST_NORMAL
@style:
	pha
	A16
	lda m_i
	cmp m_cursor
	A8
	bne @use_style
	pla
	lda #ST_ACCENT
	pha
@use_style:
	pla
	jsr txt_style
	lda #' '
	jsr txt_putc
	lda m_type
	cmp #ITEM_FILTER
	beq @filter
	cmp #ITEM_ALL
	beq @all
	cmp #ITEM_NONE
	beq @none
	cmp #ITEM_CAT
	beq @cat
	jmp @group
@filter:
	A16
	lda m_idx
	and #$00FF
	tax
	A8
	lda f:rsv_filters
	and filter_bit,x
	beq @f_off
	lda #T_BOX_ON
	bra @f_box
@f_off:
	lda #T_BOX_OFF
@f_box:
	jsr txt_putc
	lda #' '
	jsr txt_putc
	A16
	lda m_idx
	and #$00FF
	asl a
	tax
	lda filter_names,x
	tax
	A8
	jsr txt_puts0
	jmp txt_clear_eol
@all:
	ldx #3
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	ldx #txt_all
	jsr txt_puts0
	jmp txt_clear_eol
@none:
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	ldx #txt_none_item
	jsr txt_puts0
	jmp txt_clear_eol
@cat:
	lda m_idx
	and #$01
	tax
	A16
	txa
	and #$00FF
	tax
	A8
	lda m_exp,x
	beq @collapsed
	lda #T_EXPANDED
	bra @cat_glyph
@collapsed:
	lda #T_COLLAPSED
@cat_glyph:
	jsr txt_putc
	lda #' '
	jsr txt_putc
	lda m_idx
	bne @cat_cpu
	ldx #txt_cat_spc
	bra @cat_name
@cat_cpu:
	ldx #txt_cat_cpu
@cat_name:
	jsr txt_puts0
	jsr txt_clear_eol
	; selected groups: n/m at column 26
	jsr menu_cat_counts
	ldx #25
	jsr menu_row_at_col
	A16
	lda m_cnt
	ldx #2
	jsr txt_dec
	A8
	lda #'/'
	jsr txt_putc
	A16
	lda m_tmp
	ldx #2
	jsr txt_dec
	A8
	rts
@group:
	; box
	lda m_type
	cmp #ITEM_GSPC
	beq @g_spc
	SET_BM rsv_sel_cpu
	bra @g_test
@g_spc:
	SET_BM rsv_sel_spc
@g_test:
	A16
	lda m_idx
	and #$00FF
	tax
	A8
	jsr bitmap_test
	beq @g_off
	lda #T_BOX_ON
	bra @g_box
@g_off:
	lda #T_BOX_OFF
@g_box:
	jsr txt_putc
	lda #' '
	jsr txt_putc
	; name and count: entry of the group table
	A16
	lda m_idx
	and #$00FF
	asl a
	asl a
	asl a
	tax
	A8
	lda m_type
	cmp #ITEM_GSPC
	beq @n_spc
	A16
	lda f:cpu_groups,x
	sta m_tmp
	lda f:cpu_groups+4,x
	sta m_cnt
	A8
	bra @n_print
@n_spc:
	A16
	lda f:spc_groups,x
	sta m_tmp
	lda f:spc_groups+4,x
	sta m_cnt
	A8
@n_print:
	ldx m_tmp
	jsr txt_putsf
	jsr txt_clear_eol
	ldx #27
	jsr menu_row_at_col
	lda #ST_DIM
	jsr txt_style
	A16
	lda m_cnt
	ldx #4
	jsr txt_dec
	A8
	rts

; Positions the text in column X of the row m_row
menu_row_at_col:
	A16
	lda m_row
	and #$00FF
	clc
	adc #LIST_TOP
	tay
	A8
	lda #0
	jmp txt_at

; For the category m_idx: m_cnt = selected groups, m_tmp = groups
menu_cat_counts:
	A16
	stz m_cnt
	A8
	lda m_idx
	bne @cpu
	A16
	lda #SPC_GROUP_COUNT
	sta m_tmp
	A8
	SET_BM rsv_sel_spc
	bra @count
@cpu:
	A16
	lda #CPU_GROUP_COUNT
	sta m_tmp
	A8
	SET_BM rsv_sel_cpu
@count:
	ldx #0
@loop:
	cpx m_tmp
	bcs @done
	jsr bitmap_test
	beq @next
	A16
	inc m_cnt
	A8
@next:
	inx
	bra @loop
@done:
	rts

.segment "RODATA"
filter_bit: .byte FILT_EMULATION, FILT_UNDOC, FILT_DECIMAL
.segment "CODE"

menu_draw_start:
	lda #0
	ldx #1
	ldy #START_ROW
	jsr txt_at
	jsr menu_total
	A16
	cmp #0
	A8
	beq @none
	A16
	lda m_cursor
	cmp m_nvis
	A8
	bne @normal
	lda #ST_ACCENT
	bra @go
@normal:
	lda #ST_NORMAL
@go:
	jsr txt_style
	lda #' '
	jsr txt_putc
	ldx #txt_start
	jsr txt_puts0
	lda #' '
	jsr txt_putc
	lda #'('
	jsr txt_putc
	jsr menu_total
	jsr txt_dec_left
	ldx #txt_tests_word
	jsr txt_puts0
	lda #')'
	jsr txt_putc
	jmp txt_clear_eol
@none:
	lda #ST_DIM
	jsr txt_style
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	lda #' '
	jsr txt_putc
	ldx #txt_no_tests
	jsr txt_puts0
	jmp txt_clear_eol

; Footer (BG3): totals and hints, or the auto-start countdown
menu_footer:
	lda #ST_NORMAL
	jsr txt_style
	ldx #1
	ldy #25
	lda #1
	jsr txt_at
	ldx #txt_ft_spc
	jsr txt_puts0
	A16
	lda f:rsv_spc_total
	ldx #4
	jsr txt_dec
	A8
	ldx #txt_ft_cpu
	jsr txt_puts0
	A16
	lda f:rsv_cpu_total
	ldx #4
	jsr txt_dec
	A8
	jsr txt_clear_eol
	lda #ST_DIM
	jsr txt_style
	ldx #1
	ldy #26
	lda #1
	jsr txt_at
	ldx #txt_hint1
	jsr txt_puts0
	jsr txt_clear_eol
	ldx #1
	ldy #27
	lda #1
	jsr txt_at
	ldx #txt_hint2
	jsr txt_puts0
	jsr txt_clear_eol
	lda m_auto_on
	beq @done
	lda #$FF
	sta m_auto_sec
	jsr menu_footer_auto
@done:
	lda #1
	sta bg3_dirty
	rts

; "Auto-start in N s (any button cancels)" on the last row (BG3)
menu_footer_auto:
	A16
	lda m_auto
	sta $4204
	A8
	lda #60
	sta $4206
	.repeat 8
	nop
	.endrepeat
	A16
	lda $4214
	inc a
	sta m_tmp
	A8
	lda m_tmp
	cmp m_auto_sec
	beq @done
	sta m_auto_sec
	lda #ST_WARN
	jsr txt_style
	ldx #1
	ldy #27
	lda #1
	jsr txt_at
	ldx #txt_auto1
	jsr txt_puts0
	A16
	lda m_tmp
	ldx #2
	jsr txt_dec
	A8
	ldx #txt_auto2
	jsr txt_puts0
	jsr txt_clear_eol
	lda #1
	sta bg3_dirty
@done:
	rts

; Sets the cursor sprite (OAM entry 0) at the selected item
menu_cursor:
	A16
	lda m_cursor
	cmp m_nvis
	bne @list
	lda #START_ROW
	bra @row
@list:
	sec
	sbc m_scroll
	clc
	adc #LIST_TOP
@row:
	asl a
	asl a
	asl a
	dec a
	A8
	sta f:OAM_SHADOW+1    ; y
	lda m_anim
	lsr a
	lsr a
	lsr a
	lsr a
	and #$01
	sta f:OAM_SHADOW+2    ; tile 0 or 1 (arrow, arrow shifted)
	lda #0
	sta f:OAM_SHADOW+0    ; x
	lda #$30
	sta f:OAM_SHADOW+3    ; priority 3
	rts

; --- Actions ------------------------------------------------------------------------------------------------

; A or Y on the current item
menu_activate:
	A16
	lda m_cursor
	cmp m_nvis
	A8
	bne @item
	; Start item
	jsr menu_total
	A16
	cmp #0
	A8
	beq @ret
	pla
	pla
	jmp menu_start
@item:
	A16
	lda m_cursor
	sta m_i
	A8
	jsr menu_get_item
	lda m_type
	cmp #ITEM_FILTER
	beq @filter
	cmp #ITEM_ALL
	beq @all
	cmp #ITEM_NONE
	beq @none
	cmp #ITEM_CAT
	beq @cat
	; a group
	lda m_type
	cmp #ITEM_GSPC
	beq @g_spc
	SET_BM rsv_sel_cpu
	bra @g_toggle
@g_spc:
	SET_BM rsv_sel_spc
@g_toggle:
	A16
	lda m_idx
	and #$00FF
	tax
	A8
	jmp bitmap_toggle
@filter:
	A16
	lda m_idx
	and #$00FF
	tax
	A8
	lda f:rsv_filters
	eor filter_bit,x
	sta f:rsv_filters
@ret:
	rts
@all:
	lda #1
	jmp menu_select_all
@none:
	lda #0
	jmp menu_select_all
@cat:
	; A: expand/collapse. Y: toggle all the groups of the category
	A16
	lda m_pad
	and #PAD_A
	A8
	beq @cat_toggle_all
	A16
	lda m_idx
	and #$00FF
	tax
	A8
	lda m_exp,x
	eor #1
	sta m_exp,x
	jsr build_vis
	rts
@cat_toggle_all:
	lda m_idx
	jmp menu_toggle_cat_a

; X: toggle all the groups of the category of the current item
menu_toggle_category:
	A16
	lda m_cursor
	cmp m_nvis
	A8
	bcs @ret
	A16
	lda m_cursor
	sta m_i
	A8
	jsr menu_get_item
	lda m_type
	cmp #ITEM_CAT
	beq @cat
	cmp #ITEM_GSPC
	beq @spc
	cmp #ITEM_GCPU
	beq @cpu
@ret:
	rts
@cat:
	lda m_idx
	jmp menu_toggle_cat_a
@spc:
	lda #0
	jmp menu_toggle_cat_a
@cpu:
	lda #1
	jmp menu_toggle_cat_a

; A = category (0 = SPC, 1 = CPU): selects all its groups, or none if all were selected
menu_toggle_cat_a:
	sta m_idx
	jsr menu_cat_counts
	A16
	lda m_cnt
	cmp m_tmp
	A8
	beq @none
	lda #1
	bra @apply
@none:
	lda #0
@apply:
	sta m_type             ; 1 = select, 0 = clear
	lda m_idx
	bne @cpu
	SET_BM rsv_sel_spc
	bra @loop_start
@cpu:
	SET_BM rsv_sel_cpu
@loop_start:
	ldx #0
@loop:
	cpx m_tmp
	bcs @done
	lda m_type
	beq @clear
	jsr bitmap_set
	bra @next
@clear:
	jsr bitmap_clear
@next:
	inx
	bra @loop
@done:
	rts

; A = 1 selects every group of both categories, 0 clears them
menu_select_all:
	sta m_type
	ldx #0
@loop:
	lda m_type
	beq @clear
	lda #$FF
	bra @store
@clear:
	lda #0
@store:
	sta f:rsv_sel_spc,x
	sta f:rsv_sel_cpu,x
	inx
	cpx #MAX_GROUPS/8
	bne @loop
	rts
