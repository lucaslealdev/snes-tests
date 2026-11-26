; PLACEHOLDER (Etapa 1): just enough to link everything. Replaced by the real harness in the next steps.
.p816
.i16
.a8
.export init_test: far, fail_chk: far, save_results: far, cpu_done: far
.export unexp_brk_native: far, unexp_cop_native: far, unexp_brk_emu: far, unexp_cop_emu: far
.exportzp result_a, result_x, result_y, result_p, result_s, result_d, result_dbr, retaddr, chk_addr, chk_bank
.import cpu_table, cpu_records, cpu_groups, spc_records, spc_groups, spc_files
.import gfx_font4, gfx_palette, gfx_hdma

.segment "HEADER"
	.byte "65C816 + SPC700 TESTS"
.segment "ROMINFO" ; $FFD5
	.byte $30  ; LoROM
	.byte 0    ; no battery/chips
	.byte $0A  ; 1MB
	.byte 0, 0, 0, 0
	.word $0000, $FFFF ;checksum+complement

.segment "VECTORS"
	.word 0, 0, 0, 0, 0, 0, 0, 0
	.word 0, 0, 0, 0, 0, 0, main, 0

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
retaddr: .word 0
chk_addr: .word 0
chk_bank: .byte 0

.segment "CODE"
main:
	jmp main
init_test:
fail_chk:
save_results:
cpu_done:
unexp_brk_native:
unexp_cop_native:
unexp_brk_emu:
unexp_cop_emu:
	rtl

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
