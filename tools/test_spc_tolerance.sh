#!/usr/bin/env bash
# Faults in the SPC protocol, like the ones clone consoles cause, simulated in Mesen2 (INJECT in run_tests.lua):
#   ack   one acknowledgment from the main CPU is lost: the SPC waits forever. The runner must detect the hang,
#         send EXIT, upload the program again and run every other test (one "hang", nothing left unrun).
#   load  all the attempts to load the 3rd SPC file fail: only its groups are skipped, everything else runs.
# Needs Mesen2 (see tools/run_mesen.sh). Exit status 0 = OK.
set -u
cd "$(dirname "$0")/.."
make -s || exit 1
fails=0
check() {  # name, condition result
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
field() {  # log, name -> value of name=value in the RESULT lines
  grep -o "$2=[0-9]*" "$1" | head -1 | cut -d= -f2
}
spc_field() {  # log, name -> value in the spc part of the RESULT line
  grep "^RESULT cpu:" "$1" | sed 's/.*| spc://' | grep -o "$2=[0-9]*" | cut -d= -f2
}
OUTD=build/mesen
mkdir -p $OUTD

INJECT=ack:20 TIMEOUT=300 tools/run_mesen.sh > $OUTD/tolerance-ack.log 2>&1
L=$OUTD/tolerance-ack.log
check "ack: fault injected" "$(grep -q '^INJECT: acknowledgment' $L; echo $?)"
check "ack: all SPC tests ran" "$([ "$(spc_field $L done)" = "$(spc_field $L total)" ]; echo $?)"
check "ack: nothing left unrun" "$([ "$(spc_field $L notrun)" = 0 ]; echo $?)"
check "ack: exactly one failure, a hang" "$([ "$(field $L stored)" = 1 ] && grep -q '^FAIL SPC #.* hang' $L; echo $?)"
check "ack: all CPU tests ran" "$(grep -q '^RESULT cpu: total=\([0-9]*\) done=\1 failed=0' $L; echo $?)"

INJECT=load:3 TIMEOUT=400 tools/run_mesen.sh > $OUTD/tolerance-load.log 2>&1
L=$OUTD/tolerance-load.log
total=$(spc_field $L total); done_=$(spc_field $L done); notrun=$(spc_field $L notrun)
check "load: 3 attempts dropped" "$([ "$(grep -c '^INJECT: upload handshake' $L)" = 3 ]; echo $?)"
check "load: some SPC tests skipped" "$([ "${notrun:-0}" -gt 0 ]; echo $?)"
check "load: only one file skipped, the rest ran" \
  "$([ "${notrun:-0}" -lt 500 ] && [ $((done_ + notrun)) = "$total" ]; echo $?)"
check "load: one 'unresponsive' entry, no failed test" \
  "$([ "$(field $L stored)" = 1 ] && grep -q '^FAIL SPC unresponsive' $L && [ "$(spc_field $L failed)" = 0 ]; echo $?)"
check "load: summary doesn't say all tests passed" "$(grep -q '^SUMMARY .*[0-9] of [0-9,]* tests passed' $L; echo $?)"
check "load: all CPU tests ran" "$(grep -q '^RESULT cpu: total=\([0-9]*\) done=\1 failed=0' $L; echo $?)"

if [ $fails = 0 ]; then echo "PASS: SPC fault tolerance"; exit 0; else echo "FAIL: SPC fault tolerance ($fails)"; exit 1; fi
