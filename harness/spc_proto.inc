; Protocol between the main CPU (harness/runner_spc.asm) and the SPC-700 test programs (spctest/spc_common.inc).
; If you change it, change both sides together.
;
; Port names: I0..I3 are the ports written by the main CPU ($2140-$2143) and read by the SPC ($F4-$F7);
;             O0..O3 are written by the SPC and read by the main CPU.
;
; 1. Upload. The test program of one file (spc-tests<N>.spc, loaded at $0300) is uploaded through the IPL ROM
;    with the standard protocol. After the final "execute" command the IPL jumps to $0300 (main in spc_common.inc).
;    The main CPU waits for $BBAA in O0/O1 (IPL ready) before the upload, with a timeout.
;
; 2. Boot. The SPC sets O0 = $00, O1 = $5C, O2/O3 = 0 and waits for commands. The main CPU waits for O0/O1 = $5C00
;    (timeout: the SPC is unresponsive), clears I3, and takes the value it last wrote to I0 (in the execute
;    command) as the current command sequence number.
;
; 3. Commands (main CPU -> SPC). The main CPU writes I1, I2 first and I0 last. I0 is a sequence number: the SPC
;    runs a command when I0 differs from the last value it saw. I1/I2 hold the parameters:
;       I1 = low byte of the test number, I2 = (command << 4) | (test number >> 8)       [tests < 4096]
;       command $1 = RUN: run the tests from the given one to the end of its group, then send MSG_DONE.
;                         The test must be in the uploaded file; the SPC finds its code in a table.
;       command $2 = EXIT: enable the IPL ROM and jump to it (the SPC is ready for another upload).
;
; 4. Progress (SPC -> main CPU). While running, the SPC writes the number of the test in progress to O2/O3 (at the
;    start of every test). If it doesn't change for SPC_HANG_FRAMES frames and the SPC sends nothing, the main CPU
;    decides that the test never finished (hang): it records it, tries to bring the SPC back to the IPL (the SPC
;    can only do that by itself), uploads the file again and continues with the next test; if the IPL doesn't
;    answer, the SPC is declared unresponsive and the SPC tests that didn't run are only counted.
;
; 5. Byte stream (SPC -> main CPU), for failures and the end of a group. To send a byte the SPC writes it to O1,
;    then writes a sequence number (1..255, wrapping to 1) to O0, then waits until I3 equals that number. The main
;    CPU polls O0; when it changes it reads O1, processes the byte and writes the number to I3 (acknowledge).
;       MSG_FAIL (1), followed by 5 bytes: kind of check (CHK_*), expected value, actual value, address (low, high).
;                     The test number is in O2/O3 (the SPC doesn't change it during the report).
;                     The SPC goes on with the next test after the last byte is acknowledged.
;       MSG_DONE (2): the group finished. The SPC waits for the next command.
