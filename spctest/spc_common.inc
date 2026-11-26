; Common code for the SPC-700 tests, included at the top of every generated spc-tests<N>.asm.
; The protocol with the main CPU is documented at the top of harness/spc_proto.inc. Change both together.
;
; Port names: O0..O3 are written by the SPC ($f4-$f7) and read by the main CPU at $2140-$2143.
;             I0..I3 are written by the main CPU and read by the SPC at the same addresses.

MSG_FAIL = 1
MSG_DONE = 2
CHK_ORDER = 9
CMD_RUN = $10
CMD_EXIT = $20

; All memory up to $300 is uninitialized
org $0
    ; First 16 bytes are reserved for testing instructions.
org $10
test_num:
    dw 0
result_a: db 0
result_x: db 0
result_y: db 0
result_p: db 0
txseq: db 0     ; sequence number of the last byte sent to the main CPU
last_cmd: db 0  ; I0 value of the last command seen
fk: db 0        ; check kind of the failure being reported
fe: db 0        ; expected value
fa: db 0        ; actual value
fsp: db 0       ; value of SP, for failed SP checks
fptr: dw 0      ; address of the memory location of failed memory checks
fret: dw 0      ; return address saved by fail_chk
ftmp: dw 0

; Load RAM from here
org $300
main:
    mov $f1, #$00  ; disable IPL ROM
    mov a, $f4
    mov last_cmd, a  ; the value left by the IPL protocol doesn't count as a command
    mov txseq, #$00
    mov $f6, #$00
    mov $f7, #$00
    mov $f4, #$00
    mov $f5, #$5C  ; boot signature: O0=$00 O1=$5C. Tells the main CPU that we are running

cmd_wait:
    mov a, $f4
    cmp a, last_cmd
    beq cmd_wait
    mov last_cmd, a
    mov a, $f6
    and a, #$F0
    cmp a, #CMD_EXIT
    beq exit_to_ipl
    cmp a, #CMD_RUN
    bne cmd_wait

    ; CMD_RUN. I1 = test number low byte, I2 = (command << 4) | test number high nibble
    movw ya, $f5
    mov x, a
    mov a, y
    and a, #$0F
    mov y, a
    mov a, x          ; ya = first test to run
    movw test_num, ya
    decw test_num     ; init_test increments it
    movw ftmp, ya
    mov a, #(file_first & $FF)
    mov y, #(file_first >> 8)
    movw fret, ya
    movw ya, ftmp
    subw ya, fret     ; ya = index of test in this file
    movw fret, ya
    addw ya, fret     ; ya = 2 * index
    movw ftmp, ya
    mov a, #(test_table & $FF)
    mov y, #(test_table >> 8)
    addw ya, ftmp     ; ya = address of the table entry
    movw fptr, ya
    mov y, #$00
    mov a, [fptr]+y
    mov x, a
    mov y, #$01
    mov a, [fptr]+y   ; a:x = address of the test
    mov fret+1, a
    mov fret, x
    clrp
    mov x, #$EF       ; the stack is empty at the start of every test
    mov sp, x
    mov a, fret+1
    push a
    mov a, fret
    push a
    ret               ; jumps to the test (ret pops the address without adding 1)

exit_to_ipl:
    mov $f1, #$80  ; enable IPL ROM
    jmp $ffc0      ; jump to IPL ROM


; input: YA = test number
init_test:
    incw test_num
    cmpw ya, test_num
    beq .ok
    ; We are at the wrong test - possibly due to an errant jump. Report it, and resynchronize.
    movw test_num, ya
    movw $f6, ya
    mov a, #MSG_FAIL
    call send_byte
    mov a, #CHK_ORDER
    call send_byte
    mov a, #$00
    call send_byte
    mov a, #$00
    call send_byte
    mov a, #$00
    call send_byte
    mov a, #$00
    call send_byte
    ret
.ok:
    movw $f6, ya   ; let main CPU know what test is running
    ret


; saves registers to memory and returns psw in a. Also clears P flag
save_results:
    push psw
    clrp
    mov result_a, a
    mov result_x, x
    mov result_y, y
    pop a
    mov result_p, a
    ret


; Sends the byte in a to the main CPU, and waits until it was read. Clobbers a.
send_byte:
    mov $f5, a        ; O1 = data
    inc txseq
    bne .nz
    inc txseq         ; sequence numbers are 1..255
.nz:
    mov a, txseq
    mov $f4, a        ; O0 = sequence number. This publishes the byte
.wait:
    mov a, $f7        ; I3 = sequence number of the last byte read by the main CPU
    cmp a, txseq
    bne .wait
    ret


; Called by the inline stub of a failed check: a = kind of check, y = expected value.
; Reports the failure to the main CPU, then returns to the stub, which jumps to the end of the test.
; (The stub's return address is on the stack, but the stack pointer may be anywhere.)
fail_chk:
    mov fk, a
    mov fe, y
    pop a
    mov fret, a
    pop a
    mov fret+1, a
    mov x, #$EF
    mov sp, x
    ; find the actual value
    mov a, result_x
    cmp fk, #1
    beq .have
    mov a, result_y
    cmp fk, #2
    beq .have
    mov a, result_p
    cmp fk, #3
    beq .have
    mov a, result_a
    cmp fk, #4
    beq .have
    mov a, fsp
    cmp fk, #5
    beq .have
    cmp fk, #8
    bne .have
    mov x, #$00
    mov a, [fptr+x]
.have:
    mov fa, a
    mov a, #MSG_FAIL
    call send_byte
    mov a, fk
    call send_byte
    mov a, fe
    call send_byte
    mov a, fa
    call send_byte
    mov a, fptr
    call send_byte
    mov a, fptr+1
    call send_byte
    mov a, fret+1
    push a
    mov a, fret
    push a
    ret


; End of a group of tests. Tell the main CPU and wait for the next command.
group_done:
    mov x, #$EF
    mov sp, x
    mov a, #MSG_DONE
    call send_byte
    jmp cmd_wait
