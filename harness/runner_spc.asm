; Runner for the SPC-700 tests. See spc_proto.inc for the protocol.
; Groups are run one at a time. If the SPC stops making progress (a hang) the runner records it, tries to get the
; IPL back to upload the file again, and goes on with the next test; if it can't, the SPC is "unresponsive".

.segment "CODE"

; Runs all the selected SPC groups. Needs the total (rsv_spc_total) to be computed.
spc_phase:
	A8
	XY16
	A16
	lda f:rsv_spc_total
	A8
	bne @go
	lda #2
	sta f:rsv_spc_state
	rts
@go:
	lda #1
	sta f:rsv_spc_state
	lda #$FF
	sta spc_file
	stz spc_seq
	ldx #0
	stx spc_gi
@group:
	ldx spc_gi
	cpx #SPC_GROUP_COUNT
	bcs @finish
	jsr spc_eligible
	bcc @next
	lda spc_gfile
	cmp spc_file
	beq @loaded
	jsr spc_load_file
	bcs @unresponsive
@loaded:
	ldx spc_gfirst
	stx spc_start
	jsr spc_run_group
	bcs @unresponsive
@next:
	ldx spc_gi
	inx
	stx spc_gi
	bra @group
@finish:
	jsr spc_send_exit
	lda #2
	sta f:rsv_spc_state
	rts
@unresponsive:
	jmp spc_unresponsive

; Reached when the SPC can't be reached anymore: records it, and the SPC tests that didn't run are only counted
spc_unresponsive:
	A8
	lda #3
	sta f:rsv_spc_state
	A16
	lda f:rsv_spc_total
	sec
	sbc f:rsv_spc_done
	sta f_expected
	sta f:rsv_notrun
	stz f_test
	stz f_actual
	stz f_addr
	lda #FAIL_SPC|CHK_UNRESP
	sta f_kind
	A8
	stz f_bank
	jmp add_failure

; X = group number (spc_gi). Carry set if the group will run (selected and not filtered out); sets spc_gfirst,
; spc_gend (first test after the group) and spc_gfile.
spc_eligible:
	SET_BM rsv_sel_spc
	jsr bitmap_test
	beq @no
	A16
	lda spc_gi
	asl a
	asl a
	asl a
	tax
	A8
	lda f:spc_groups+6,x
	and #TAG_UNDOCUMENTED
	beq @yes
	lda f:rsv_filters
	and #FILT_UNDOC
	beq @no
@yes:
	A16
	lda f:spc_groups+2,x
	sta spc_gfirst
	clc
	adc f:spc_groups+4,x
	sta spc_gend
	A8
	lda f:spc_groups+7,x
	sta spc_gfile
	sec
	rts
@no:
	clc
	rts

; Loads the file spc_gfile (sends EXIT to the previous one first). Carry set if the SPC doesn't respond
spc_load_file:
	lda spc_file
	cmp #$FF
	beq @upload
	jsr spc_send_exit
@upload:
	lda spc_gfile
	jsr spc_upload
	bcs @fail
	lda spc_gfile
	sta spc_file
	clc
	rts
@fail:
	lda #$FF
	sta spc_file
	sec
	rts

spc_send_exit:
	lda #SPC_CMD_EXIT
	sta $2142
	inc spc_seq
	lda spc_seq
	sta $2140
	rts

; Runs the tests from spc_start to the end of the group spc_gi, recovering from hangs.
; Carry set if the SPC is unresponsive.
spc_run_group:
	A16
	lda f:rsv_spc_done
	sta spc_base
	A8
@again:
	; command: RUN spc_start
	lda spc_start
	sta $2141
	lda spc_start+1
	and #$0F
	ora #SPC_CMD_RUN
	sta $2142
	stz done_flag
	stz rx_state
	inc spc_seq
	lda spc_seq
	sta $2140
	jsr spc_poll
	bne @hang
	; all the tests of the group were started
	A16
	lda spc_gend
	sec
	sbc spc_start
	clc
	adc spc_base
	sta f:rsv_spc_done
	A8
	clc
	rts
@hang:
	; The test in progress is the last one seen, or the first one if none started yet
	A16
	lda spc_last
	cmp spc_start
	bcs @have
	lda spc_start
@have:
	sta f_test
	sta spc_hung
	; count it as started
	sec
	sbc spc_start
	inc a
	clc
	adc spc_base
	sta f:rsv_spc_done
	lda spc_hung
	sta f:rsv_spc_cur
	stz f_actual
	stz f_expected
	stz f_addr
	lda #FAIL_SPC|CHK_HANG
	sta f_kind
	A8
	stz f_bank
	jsr add_failure
	; get the SPC back
	lda #$FF
	sta spc_file
	jsr spc_wait_ipl
	bcs @dead
	jsr spc_load_file
	bcs @dead
	A16
	lda spc_hung
	inc a
	sta spc_start
	cmp spc_gend
	A8
	bcs @group_over
	A16
	lda f:rsv_spc_done
	sta spc_base
	A8
	jmp @again
@group_over:
	clc
	rts
@dead:
	sec
	rts

; Waits for the IPL ROM to be ready ($BBAA). Carry set on timeout
spc_wait_ipl:
	ldx #SPC_WAIT_FRAMES
	stx timeout
@loop:
	ldx $2140
	cpx #$BBAA
	beq @ok
	lda $4210
	bpl @loop
	inc frame_acc
	ldx timeout
	dex
	stx timeout
	bne @loop
	sec
	rts
@ok:
	clc
	rts

; Polls the SPC until the group is done (Z set) or it hangs (Z clear)
spc_poll:
	stz spc_wd
	ldx $2142
	stx spc_last
@loop:
	lda $2140
	cmp rx_seq
	beq @nobyte
	sta rx_seq
	lda $2141
	jsr spc_rx_byte
	lda rx_seq
	sta $2143            ; acknowledge
	stz spc_wd
	lda done_flag
	bne @done
	bra @loop
@nobyte:
	lda $4210
	bpl @loop
	; one frame passed
	inc frame_acc
	ldx $2142
	cpx spc_last
	beq @same
	stx spc_last
	stz spc_wd
	bra @update
@same:
	inc spc_wd
	lda spc_wd
	cmp #SPC_HANG_FRAMES
	bcs @hang
@update:
	jsr spc_progress
	bra @loop
@done:
	lda #0
	rts
@hang:
	lda #1
	rts

; Updates the number of tests done and the screen from the last progress seen
spc_progress:
	A16
	lda spc_last
	cmp spc_start
	bcc @skip
	cmp spc_gend
	bcs @skip
	sta f:rsv_spc_cur
	sec
	sbc spc_start
	inc a
	clc
	adc spc_base
	sta f:rsv_spc_done
@skip:
	A8
	jmp run_update

; A byte of the stream from the SPC
spc_rx_byte:
	pha
	lda rx_state
	bne @arg
	pla
	cmp #SPC_MSG_DONE
	bne @notdone
	lda #1
	sta done_flag
	rts
@notdone:
	cmp #SPC_MSG_FAIL
	bne @ret
	lda #1
	sta rx_state
	ldx $2142             ; the number of the test that failed
	stx rx_test
@ret:
	rts
@arg:
	A16
	lda rx_state
	and #$00FF
	tax
	A8
	pla
	sta rx_buf-1,x
	lda rx_state
	cmp #5
	beq @complete
	inc rx_state
	rts
@complete:
	stz rx_state
	A16
	lda rx_test
	sta f_test
	lda rx_buf+1
	and #$00FF
	sta f_expected
	lda rx_buf+2
	and #$00FF
	sta f_actual
	lda rx_buf+3
	sta f_addr
	lda rx_buf
	and #$00FF
	ora #FAIL_SPC
	sta f_kind
	A8
	stz f_bank
	jmp add_failure

; Uploads the test program of file A through the IPL ROM, and waits for it to start.
; Carry set if the SPC doesn't respond (the IPL is not ready or the program doesn't start).
spc_upload:
	A16
	and #$00FF
	sta tmp16
	asl a
	asl a
	asl a
	sec
	sbc tmp16            ; 7 bytes per file
	tax
	A8
	lda f:spc_files,x
	sta spc_src+2
	A16
	lda f:spc_files+1,x
	sta spc_src
	lda f:spc_files+3,x
	sta spc_size
	A8
	jsr spc_wait_ipl
	bcc @go
	rts
@go:
	ldx #$0300
	stx $2142
	lda #$CC
	sta $2141
	sta $2140
@w2:
	cmp $2140
	bne @w2
	ldy #0
@loop:
	lda [spc_src],y
	sta $2141
	tya
	sta $2140
	bit $4210            ; count the frames, for the elapsed time
	bpl @w3
	inc frame_acc
@w3:
	cmp $2140
	bne @w3
	iny
	cpy spc_size
	bne @loop
	ldx #$0300
	stx $2142
	stz $2141
	inc a
	inc a
	sta spc_seq
	sta $2140
@w4:
	cmp $2140
	bne @w4
	; wait for the program to say it's running
	ldx #SPC_WAIT_FRAMES
	stx timeout
@w5:
	ldx $2140
	cpx #SPC_BOOT_SIGNATURE
	beq @booted
	lda $4210
	bpl @w5
	inc frame_acc
	ldx timeout
	dex
	stx timeout
	bne @w5
	sec
	rts
@booted:
	stz $2143
	stz rx_seq
	stz rx_state
	clc
	rts
