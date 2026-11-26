; SNES test ROM for the 65C816 and SPC-700 CPUs: menu, runner and report.
;
; Overview (see PLAN.md, README.md and CLAUDE.md):
;   hw.asm          video setup, NMI, joypad
;   text.asm        text drawing
;   state.asm       state in the reserved WRAM ($7FA000-$7FDFFF), which survives resets
;   runner_cpu.asm  runs the generated 65C816 tests, records failures
;   runner_spc.asm  runs the generated SPC-700 tests through the IPL ROM and the I/O ports (spc_proto.inc)
;   run.asm         starts a run, run screen, totals
;   menu.asm        selection menu
;   report.asm      final report
.p816
.i16
.a8
.smart -

.include "defs.inc"
.include "macros.inc"

.import cpu_table, cpu_records, cpu_groups, spc_records, spc_groups, spc_files
.import CPU_TEST_COUNT, CPU_GROUP_COUNT, SPC_TEST_COUNT, SPC_GROUP_COUNT, SPC_FILE_COUNT
.import gfx_font4, gfx_font4_end, gfx_font2, gfx_font2_end, gfx_obj, gfx_obj_end, gfx_palette, gfx_hdma
.export init_test: far, fail_chk: far, save_results: far, cpu_done: far
.exportzp result_a, result_x, result_y, result_p, result_s, result_d, result_dbr, retaddr, chk_addr, chk_bank

.segment "HEADER"
	.byte "65C816 + SPC700 TESTS"
.segment "ROMINFO" ; $FFD5
	.byte $30  ; LoROM
	.byte 0    ; no battery/chips
	.byte $0A  ; 1MB
	.byte 0, 0, 0, 0
	.word $0000, $FFFF ;checksum+complement

.segment "VECTORS"
	; native: COP BRK ABORT NMI RESET IRQ.   The BRK/COP handlers are in RAM ($1000-$100F): see runner_cpu.asm
	.word 0, 0, native_cop_handler, native_brk_handler, 0, nmi, 0, 0
	.word 0, 0, emulation_cop_handler, 0, 0, nmi, main, emulation_brk_handler

; Zero page. $10-$24 is what the tests need (they never touch it); $33-$35 and $FA-$FF are used by the tests, so
; the runner state that must live while tests run is in $25-$32 and in the reserved WRAM.
.segment "ZEROPAGE"
.res $10
test_num: .word 0
result_a: .word 0
result_x: .word 0
result_y: .word 0
result_p: .word 0
result_s: .word 0
result_d: .word 0
result_dbr: .byte 0
retaddr: .word 0       ; return address from bankN_save_results
vblank_counter: .byte 0  ; update the screen when it reaches 0
chk_addr: .word 0      ; address of a failed memory check (set by the failure stub)
chk_bank: .byte 0
f_bank: .byte 0        ; failure being recorded (add_failure)
f_test: .word 0
f_kind: .word 0
f_actual: .word 0
f_expected: .word 0
f_addr: .word 0
f_group: .word 0
f_tmp: .word 0
; --- the rest is not used while the tests run
.res $40-$34
nmi_frames: .byte 0
nmi_ui: .byte 0
bg3_dirty: .byte 0
pad_cur: .word 0
pad_prev: .word 0
pad_new: .word 0
pad_ev: .word 0
rep_last: .word 0
rep_timer: .byte 0
tpos: .word 0
tbase: .word 0
tlayer: .byte 0
tattr: .byte 0
tmode: .byte 0
tstyle: .byte 0
tptr: .res 3
tcount: .word 0
tchar: .word 0
tlead: .word 0
tmp16: .word 0
tmpa: .word 0
tmpb: .word 0
numbuf: .res 6
wrap_x0: .byte 0
wrap_x1: .byte 0
wcol: .byte 0
wrow: .byte 0
wspace: .byte 0
wlen: .byte 0
wy: .word 0
bm_ptr: .res 3
bm_mask: .byte 0
zw: .word 0
jbank: .byte 0
frame_acc: .byte 0     ; frames counted by the polling loops, added to the elapsed time by run_update
excl: .byte 0
ct: .word 0
coff: .word 0
ccount: .word 0
; run screen
bar_done: .word 0
bar_total: .word 0
bar_sd: .word 0
bar_st: .word 0
barpx: .word 0
cur_group: .word 0
cur_ins: .word 0
cur_name: .word 0
cur_test: .word 0
; SPC runner
spc_file: .byte 0      ; file loaded in the SPC ($FF = none)
spc_seq: .byte 0       ; sequence number of the last command sent
spc_gi: .word 0        ; group being considered
spc_gfirst: .word 0
spc_gend: .word 0
spc_gfile: .byte 0
spc_start: .word 0     ; first test of the run in progress
spc_base: .word 0      ; tests done before spc_start
spc_last: .word 0      ; last progress read from the SPC
spc_hung: .word 0
spc_wd: .byte 0
spc_try: .byte 0       ; attempts left (loading a file, rescuing a hung SPC)
spc_badfiles: .byte 0  ; files in a row that couldn't be loaded
spc_skipf: .byte 0     ; file whose groups are being skipped
rx_seq: .byte 0
rx_state: .byte 0
rx_test: .word 0
rx_buf: .res 6
done_flag: .byte 0
timeout: .word 0
spc_src: .res 3
spc_size: .word 0
; menu and report
.include "ui_vars.inc"

.segment "CODE"

main:
	sei
	clc
	xce
	rep #$18
	sep #$20
	.a8
	.i16
	cld
	ldx #$1FFF
	txs
	lda #0
	pha
	plb
	A16
	lda #0
	tcd
	A8
	; Clear all of WRAM except the reserved state (rsv_start-rsv_end), which must survive a reset. A real console
	; (and snes9x) powers on with garbage in WRAM, and the harness assumes its variables start at 0. Mesen zeroes
	; WRAM by default, which hid this: see tools/lua/test_dirty_ram.lua. Inline, because it also clears the stack.
	ldx #0
	stx $2181
	stz $2183        ; WRAM address = $7E0000
	lda #$08
	sta $4300        ; DMA0: fixed source, A->B
	lda #$80
	sta $4301        ; B bus: $2180 (WMDATA)
	ldx #.loword(zero_byte)
	stx $4302
	lda #^zero_byte
	sta $4304
	ldx #0
	stx $4305        ; 64KB: $7E0000-$7EFFFF
	lda #$01
	sta $420B
	ldx #.loword(rsv_start)
	stx $4305        ; $7F0000 up to rsv_start (the WRAM address continues from $7F0000)
	sta $420B
	ldx #.loword(rsv_end)
	stx $2181
	sta $2183        ; WRAM address = rsv_end (bank $7F)
	ldx #.loword(-rsv_end)
	stx $4305        ; rsv_end up to $7FFFFF
	sta $420B
	jsr hw_init
	jsr state_validate
	bcc @power_on
	lda f:rsv_phase
	cmp #PHASE_SPC
	beq @spc
	cmp #PHASE_CPU
	beq @cpu
	jmp menu_enter_keep
@power_on:
	jsr state_init_defaults
	jmp menu_enter
@spc:
	; The console was reset during the SPC tests. The SPC state is lost: count the tests that didn't run
	jsr run_screen_init
	jsr spc_unresponsive
	lda #PHASE_CPU
	sta f:rsv_phase
	jmp cpu_start
@cpu:
	; reset during the CPU tests: the test in progress never finished. Continue with the next one
	jsr run_screen_init
	jmp cpu_resume

; Called when the CPU tests are done: shows the report, then the menu
run_finished:
	A8
	XY16
	lda #PHASE_REPORT
	sta f:rsv_phase
	jsr report_enter
	jmp menu_enter_keep

.include "hw.asm"
.include "text.asm"
.include "state.asm"
.include "runner_cpu.asm"
.include "runner_spc.asm"
.include "run.asm"
.include "menu.asm"
.include "report.asm"

.segment "STRINGS"
strings_marker: .byte 0

.segment "TEST_DATA"  ; At address FFA0. Used by some tests
test_addr:    ; $FFA0
	.word $1212
test_target:  ; $FFA2
	.word $8000
test_target24:  ; $FFA4
	.word $8000
	.byte $7E
