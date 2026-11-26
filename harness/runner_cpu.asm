; Runner for the 65C816 tests.
;
; The generated test code (cputest/make_cpu_tests.py) starts every test with `ldx #num / jsl init_test`, and
; falls through to the next test. init_test skips the tests that were not selected (or filtered out) by jumping
; to the next enabled test with cpu_goto. A failed check jumps to fail_chk, which records the failure
; in the reserved WRAM and continues with the next enabled test. A test that never finishes can only be recovered
; with a reset: at boot, the phase and rsv_cpu_cur tell that a CPU test was running (cpu_resume).
;
; Zero page used by the tests (must not change, the generated code depends on it): result_*, retaddr, chk_addr,
; chk_bank. Fixed addresses used by the tests: BRK/COP handlers at $1000-$100F, TEST_DATA at $00FFA0.

vblank_every_n_tests = 10

.segment "RODATA"
; Where fail_chk finds the actual value for each kind of check (CHK_CTRL has no actual value)
kind_src: .word zw, result_x, result_y, result_p, result_a, result_s, result_dbr, result_d
handler_table:
	.byte $5C
	.faraddr unexp_brk_native
	.byte $5C
	.faraddr unexp_cop_native
	.byte $5C
	.faraddr unexp_brk_emu
	.byte $5C
	.faraddr unexp_cop_emu

.segment "CODE"

; Called by every test: X = number of the test that starts
init_test:
	dex
	cpx test_num
	beq @ok
	jmp cpu_order_error
@ok:
	inx
	stx f_tmp
	jsr cpu_next_enabled     ; X = first enabled test >= X
	cpx f_tmp
	beq @run
	; This test is not enabled: drop the return address and go to the next enabled test
	pla
	pla
	pla
	jmp cpu_goto
@run:
	stx test_num
	A16
	txa
	sta f:rsv_cpu_cur
	lda f:rsv_cpu_done
	inc a
	sta f:rsv_cpu_done
	A8
	dec vblank_counter
	bne @ret
	lda #vblank_every_n_tests
	sta vblank_counter
	jsr run_update           ; waits for vblank and updates the screen
@ret:
	rtl

; X = test number. Returns X = first enabled test >= X, or CPU_TEST_COUNT if there is none
cpu_next_enabled:
	SET_BM rsv_cpu_map
@loop:
	cpx #CPU_TEST_COUNT
	bcs @end
	jsr bitmap_test
	bne @found
	inx
	bra @loop
@end:
	ldx #CPU_TEST_COUNT
@found:
	rts

; Jumps to test X (or to the end of the tests if X = CPU_TEST_COUNT), with the state that tests expect
; (S=$1EF, E=0, M=1, X=16 bits, D=0, DBR=0)
cpu_goto:
	cpx #CPU_TEST_COUNT
	bcc @go
	jmp cpu_done
@go:
	stx f_tmp
	dex
	stx test_num
	A16
	lda f_tmp
	asl a
	clc
	adc f_tmp
	tax
	lda f:cpu_table,x
	dec a              ; rtl returns to the address + 1
	sta f_tmp
	A8
	lda f:cpu_table+2,x
	sta jbank
	ldx #$01EF
	txs
	cld
	lda jbank
	pha
	ldx f_tmp
	phx
	lda #$00
	pha
	plb
	rtl                ; "returns" to the test

; Continues with the test after the current one (after a failure)
cpu_next_after_fail:
	jsr install_handlers
	ldx test_num
	inx
	jsr cpu_next_enabled
	jmp cpu_goto

; Restores the BRK/COP handlers (the tests that expect BRK/COP replace them temporarily)
install_handlers:
	A8
	ldx #0
@loop:
	lda handler_table,x
	sta native_brk_handler,x
	inx
	cpx #16
	bne @loop
	rts

; Called with `jml` by the failure stubs of the tests. X = expected value, Y = kind of check (CHK_*)
; (After save_results: A=8 bits, X/Y=16 bits, E=0, D=0, DBR=0.) For memory checks, chk_addr/chk_bank have the address.
fail_chk:
	stx f_expected
	sty f_kind
	ldx #$01EF
	txs
	cld
	A16
	lda f_kind
	and #$00FF
	sta f_kind
	cmp #CHK_MEM
	beq @mem
	stz zw
	asl a
	tax
	lda kind_src,x
	tax
	lda $00,x
	sta f_actual
	lda f_kind
	cmp #CHK_DBR
	bne @store
	lda f_actual
	and #$00FF
	sta f_actual
	bra @store
@mem:
	A8
	lda [chk_addr]
	sta f_actual
	stz f_actual+1
	ldx chk_addr
	stx f_addr
	lda chk_bank
	sta f_bank
@store:
	A8
	XY16
	ldx test_num
	stx f_test
	jsr add_failure
	jmp cpu_next_after_fail

; The test X-1 was entered when the runner expected the test after test_num: probably an errant jump
cpu_order_error:
	inx
	stx f_test
	ldx #$01EF
	txs
	cld
	A16
	lda test_num
	sta f_actual
	lda f_test
	dec a
	sta f_expected
	lda #CHK_ORDER
	sta f_kind
	stz f_addr
	A8
	stz f_bank
	jsr add_failure
	ldx f_test
	jmp cpu_goto

; Unexpected BRK/COP (the handlers of the tests that expect them are installed only while they run)
unexp_brk_native:
unexp_brk_emu:
	clc
	xce
	rep #$10
	sep #$20
	.a8
	.i16
	ldy #CHK_BRK
	bra unexp_common
unexp_cop_native:
unexp_cop_emu:
	clc
	xce
	rep #$10
	sep #$20
	ldy #CHK_COP
unexp_common:
	sei
	ldx #$01EF
	txs
	cld
	lda #0
	pha
	plb
	A16
	lda #0
	tcd
	tya
	and #$00FF
	sta f_kind
	stz f_actual
	stz f_expected
	stz f_addr
	A8
	stz f_bank
	XY16
	ldx test_num
	stx f_test
	jsr add_failure
	jmp cpu_next_after_fail

.export unexp_brk_native: far, unexp_cop_native: far, unexp_brk_emu: far, unexp_cop_emu: far

; Starts the CPU tests. The map of enabled tests (rsv_cpu_map) must be ready.
cpu_start:
	A8
	XY16
	lda #1
	sta vblank_counter
	ldx #$FFFF
	stx test_num
	jsr install_handlers
	ldx #0
	jsr cpu_next_enabled
	jmp cpu_goto

; Continues after a reset during the CPU tests: the test in progress never finished
cpu_resume:
	A8
	XY16
	lda #1
	sta vblank_counter
	jsr install_handlers
	A16
	lda f:rsv_cpu_done
	A8
	beq @none_started
	A16
	lda f:rsv_cpu_cur
	sta f_test
	sta test_num
	stz f_actual
	stz f_expected
	stz f_addr
	lda #CHK_HANG
	sta f_kind
	A8
	stz f_bank
	jsr add_failure
	ldx test_num
	inx
	jsr cpu_next_enabled
	jmp cpu_goto
@none_started:
	ldx #0
	jsr cpu_next_enabled
	jmp cpu_goto

; Jumped to by the last test, and by cpu_goto when there are no more enabled tests
cpu_done:
	sei
	cld
	A8
	XY16
	ldx #$1FFF
	txs
	lda #0
	pha
	plb
	A16
	lda #0
	tcd
	A8
	jmp run_finished

; Saves the registers and resets the state (D, DBR, etc.) after the instruction under test (called with jsl by the
; bankN_save_results stubs of the tests)
save_results:
	; p register was already saved, and emulation mode was cleared.
	sei
	rep #$38
	.a16
	.i16
	phd
	pha
	lda #$0000
	tcd
	pla
	sta result_a
	stx result_x
	sty result_y
	plx  ; d register
	stx result_d
	tsc  ; original S value minus 3 (due to jsl).
	inc a
	inc a
	inc a
	sta result_s

	sep #$20
	.a8
	phb
	pla
	sta result_dbr
	lda #$00
	pha
	plb
	rtl
