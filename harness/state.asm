; State kept in the reserved WRAM range $7FA000-$7FDFFF (segment RSVSTATE, see tools/gen_cfg.py).
; No test touches this range (tools/audit_wram.py), so it survives the tests and the resets that recover from a
; test that never finishes. The ROM has no SRAM, so nothing here survives a power cycle.
;
; Layout:
;   header   magic, version, phase, "auto-start used" flag, checksum of the configuration
;   config   filters and the selected groups (covered by the checksum)
;   runner   progress, counters, SPC state (updated while tests run, validated by range checks)
;   tables   failures per group, bitmap of the CPU tests that will run, list of failures

.segment "RSVSTATE"
rsv_start:
rsv_magic:          .res 4      ; "SNTS"
rsv_version:        .res 1
rsv_phase:          .res 1      ; PHASE_*
rsv_autostart_used: .res 1      ; set once the menu was entered after power-on
rsv_pad0:           .res 1
rsv_checksum:       .res 2
rsv_pad1:           .res 2
rsv_cfg_start:
rsv_filters:        .res 1      ; FILT_*: 1 = run tests with that tag
rsv_pad2:           .res 1
rsv_sel_spc:        .res MAX_GROUPS/8   ; bit set = group selected
rsv_sel_cpu:        .res MAX_GROUPS/8
rsv_cfg_end:
; --- runner state: zeroed at the start of every run
rsv_run_start:
rsv_spc_state:      .res 1      ; 0 = not started, 1 = running, 2 = finished, 3 = SPC unresponsive
rsv_spc_group:      .res 1      ; group being run (for the recovery after a reset)
rsv_spc_cur:        .res 2      ; SPC test in progress
rsv_cpu_cur:        .res 2      ; CPU test in progress
rsv_spc_total:      .res 2      ; tests that will run (selected and not filtered out)
rsv_cpu_total:      .res 2
rsv_spc_done:       .res 2      ; tests started so far
rsv_cpu_done:       .res 2
rsv_fail_count:     .res 2      ; entries stored in rsv_fails
rsv_fail_spc:       .res 2      ; failed tests (also those that didn't fit in rsv_fails)
rsv_fail_cpu:       .res 2
rsv_notrun:         .res 2      ; SPC tests not run because the SPC stopped responding
rsv_seconds:        .res 2      ; elapsed time
rsv_frames:         .res 1
rsv_group_fail_spc: .res MAX_GROUPS*2
rsv_group_fail_cpu: .res MAX_GROUPS*2
rsv_cpu_map:        .res MAX_TESTS/8   ; bit set = CPU test will run
rsv_fails:          .res FAIL_MAX*FAIL_SIZE
rsv_run_end:
rsv_end:

; Exported so they appear in the label file (build/snes-tests.lbl), which tools/lua/run_tests.lua reads
.export rsv_start, rsv_magic, rsv_version, rsv_phase, rsv_autostart_used, rsv_filters, rsv_sel_spc, rsv_sel_cpu
.export rsv_spc_state, rsv_spc_group, rsv_spc_cur, rsv_cpu_cur, rsv_spc_total, rsv_cpu_total, rsv_spc_done
.export rsv_cpu_done, rsv_fail_count, rsv_fail_spc, rsv_fail_cpu, rsv_notrun, rsv_seconds, rsv_frames
.export rsv_group_fail_spc, rsv_group_fail_cpu, rsv_cpu_map, rsv_fails, rsv_end

; Failure entry (FAIL_SIZE bytes):
;   +0 test number (2)     +2 kind (FAIL_SPC | CHK_*)   +3 group
;   +4 actual (2)  +6 expected (2)   +8 address (2)  +10 bank   +11 unused
FE_TEST = 0
FE_KIND = 2
FE_GROUP = 3
FE_ACTUAL = 4
FE_EXPECTED = 6
FE_ADDR = 8
FE_BANK = 10

.segment "RODATA"
magic_text: .byte "SNTS"
bit_mask: .byte $01, $02, $04, $08, $10, $20, $40, $80

.segment "CODE"

; Checks the saved state. Returns carry set if it is valid (so this is a reset, not a power on).
state_validate:
	AXY16
	ldx #0
@magic:
	A8
	lda f:rsv_magic,x
	cmp magic_text,x
	bne @bad
	inx
	cpx #4
	bne @magic
	lda f:rsv_version
	cmp #1
	bne @bad
	lda f:rsv_phase
	cmp #PHASE_REPORT+1
	bcs @bad
	jsr state_calc_checksum
	A16
	txa
	cmp f:rsv_checksum
	A8
	bne @bad
	; sanity checks of the dynamic part
	AXY16
	lda f:rsv_fail_count
	cmp #FAIL_MAX+1
	bcs @bad
	lda f:rsv_cpu_total
	cmp #MAX_TESTS+1
	bcs @bad
	A8
	sec
	rts
@bad:
	A8
	clc
	rts

; Returns the checksum of the configuration in X
state_calc_checksum:
	AXY16
	lda #$5AA5
	ldx #0
@loop:
	clc
	adc f:rsv_cfg_start,x
	inx
	inx
	cpx #rsv_cfg_end-rsv_cfg_start
	bcc @loop
	tax
	A8
	rts

state_update_checksum:
	jsr state_calc_checksum
	A16
	txa
	sta f:rsv_checksum
	A8
	rts

; Clears the saved state, selects every group, turns every filter on, and shows the menu next.
state_init_defaults:
	; fill the whole range with 0, using DMA to WRAM
	A8
	ldx #.loword(rsv_start)
	stx $2181
	lda #^rsv_start
	and #$01
	sta $2183
	lda #$08         ; fixed source, A->B
	sta $4300
	lda #$80         ; B bus register $2180
	sta $4301
	ldx #.loword(zero_byte)
	stx $4302
	lda #^zero_byte
	sta $4304
	ldx #rsv_end-rsv_start
	stx $4305
	lda #$01
	sta $420B
	ldx #0
@magic:
	lda magic_text,x
	sta f:rsv_magic,x
	inx
	cpx #4
	bne @magic
	lda #1
	sta f:rsv_version
	lda #PHASE_MENU
	sta f:rsv_phase
	lda #FILT_EMULATION|FILT_UNDOC|FILT_DECIMAL
	sta f:rsv_filters
	; select all groups
	ldx #0
@sel:
	lda #$FF
	sta f:rsv_sel_spc,x
	sta f:rsv_sel_cpu,x
	inx
	cpx #MAX_GROUPS/8
	bne @sel
	jmp state_update_checksum

; Clears the runner state (counters, failures) before a run
state_clear_run:
	A8
	ldx #.loword(rsv_run_start)
	stx $2181
	lda #^rsv_run_start
	and #$01
	sta $2183
	lda #$08
	sta $4300
	lda #$80
	sta $4301
	ldx #.loword(zero_byte)
	stx $4302
	lda #^zero_byte
	sta $4304
	ldx #rsv_run_end-rsv_run_start
	stx $4305
	lda #$01
	sta $420B
	rts

; Sets A = the phase, and updates the checksum (the phase isn't covered by it, but be safe)
state_set_phase:
	sta f:rsv_phase
	rts

; Adds one failure. Input (zero page): f_test, f_kind (with FAIL_SPC for the SPC), f_actual, f_expected,
; f_addr, f_bank. Looks up the group of the test.
; Uses only long addressing for the saved state, so it can be called with any DBR (but D=0).
add_failure:
	AXY16
	lda f_test
	sta f_group           ; (temporary, as a 16-bit value)
	lda f_kind
	and #FAIL_SPC
	bne @spc_group
	; CPU: record of the test is 16 bytes, group at +15
	lda f_kind
	and #$007F
	cmp #CHK_UNRESP
	beq @no_group
	lda f_test
	cmp #CPU_TEST_COUNT
	bcs @no_group
	asl a
	asl a
	asl a
	asl a
	tax
	A8
	lda f:cpu_records+15,x
	bra @have_group
@spc_group:
	.a16
	lda f_kind
	and #$007F
	cmp #CHK_UNRESP
	beq @no_group
	lda f_test
	cmp #SPC_TEST_COUNT
	bcs @no_group
	asl a
	asl a
	asl a
	tax
	A8
	lda f:spc_records+7,x
	bra @have_group
@no_group:
	A8
	lda #0
@have_group:
	A8
	sta f_group
	stz f_group+1
	; count the failure (CHK_UNRESP is not a failed test: it only says that tests were not run)
	AXY16
	lda f_kind
	and #$007F
	cmp #CHK_UNRESP
	beq @store
	lda f_group
	asl a
	tax
	lda f_kind
	and #FAIL_SPC
	bne @count_spc
	lda f:rsv_group_fail_cpu,x
	inc a
	sta f:rsv_group_fail_cpu,x
	lda f:rsv_fail_cpu
	inc a
	sta f:rsv_fail_cpu
	bra @store
@count_spc:
	lda f:rsv_group_fail_spc,x
	inc a
	sta f:rsv_group_fail_spc,x
	lda f:rsv_fail_spc
	inc a
	sta f:rsv_fail_spc
@store:
	lda f:rsv_fail_count
	cmp #FAIL_MAX
	bcs @done
	; offset = count * 12
	asl a
	asl a
	sta f_tmp
	lda f:rsv_fail_count
	asl a
	asl a
	asl a
	clc
	adc f_tmp
	tax
	lda f_test
	sta f:rsv_fails+FE_TEST,x
	lda f_actual
	sta f:rsv_fails+FE_ACTUAL,x
	lda f_expected
	sta f:rsv_fails+FE_EXPECTED,x
	lda f_addr
	sta f:rsv_fails+FE_ADDR,x
	A8
	lda f_kind
	sta f:rsv_fails+FE_KIND,x
	lda f_group
	sta f:rsv_fails+FE_GROUP,x
	lda f_bank
	sta f:rsv_fails+FE_BANK,x
	AXY16
	lda f:rsv_fail_count
	inc a
	sta f:rsv_fail_count
@done:
	A8
	XY16
	rts

; --- Bitmaps. Set bm_ptr (24-bit address) with SET_BM first; X = bit number (preserved).
.macro SET_BM label
	ldy #.loword(label)
	sty bm_ptr
	lda #^label
	sta bm_ptr+2
.endmacro

bitmap_locate:        ; -> bm_mask = mask of the bit, Y = index of the byte
	A16
	txa
	and #$0007
	tay
	A8
	lda bit_mask,y
	sta bm_mask
	A16
	txa
	lsr a
	lsr a
	lsr a
	tay
	A8
	rts

bitmap_test:          ; Z clear if the bit is set
	jsr bitmap_locate
	lda [bm_ptr],y
	and bm_mask
	rts

bitmap_set:
	jsr bitmap_locate
	lda [bm_ptr],y
	ora bm_mask
	sta [bm_ptr],y
	rts

bitmap_clear:
	jsr bitmap_locate
	lda bm_mask
	eor #$FF
	and [bm_ptr],y
	sta [bm_ptr],y
	rts

bitmap_toggle:
	jsr bitmap_locate
	lda [bm_ptr],y
	eor bm_mask
	sta [bm_ptr],y
	rts

.segment "RODATA"
zero_byte: .byte 0
.segment "CODE"
