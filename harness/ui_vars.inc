; Variables of the menu and report. They are in low WRAM ($0500-$0EFF, segment BSS), which the tests don't touch
; (tools/audit_wram.py), and are only used while no test runs.
.segment "BSS"
m_cursor: .word 0      ; selected item (m_nvis = the "Start tests" item)
m_scroll: .word 0
m_nvis: .word 0        ; number of items in the list
m_exp: .res 2          ; categories expanded (0 = SPC, 1 = CPU)
m_dirty: .byte 0
m_auto_on: .byte 0
m_auto: .word 0        ; frames left to the auto-start
m_auto_sec: .byte 0
m_pad: .word 0
m_i: .word 0
m_row: .byte 0
m_type: .byte 0
m_idx: .byte 0
m_tmp: .word 0
m_cnt: .word 0
m_anim: .byte 0
; report
r_sel: .word 0         ; selected failure
r_scroll: .word 0
r_mode: .byte 0        ; 0 = list, 1 = detail
r_n: .word 0
r_entry: .word 0       ; offset of the failure entry being described
r_msgptr: .word 0
r_len: .word 0
r_tmp: .word 0
e_test: .word 0        ; the failure being described
e_kind: .byte 0
e_group: .byte 0
e_actual: .word 0
e_expected: .word 0
e_addr: .word 0
e_bank: .byte 0
e_spc: .byte 0
e_rec: .word 0         ; offset of the record of the test (cpu_records / spc_records)
e_p: .byte 0
e_tags: .byte 0
mb_pos: .word 0
r_i: .word 0
r_j: .word 0
r_cnt: .word 0
r_groups: .word 0
r_buf: .res 16
r_list_top2: .word 0
r_rows: .word 0
mb_comma: .byte 0
