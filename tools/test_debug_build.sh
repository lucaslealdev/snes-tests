#!/usr/bin/env bash
# Builds the debug ROM (tests sabotaged on purpose), runs it headless in Mesen2 and checks that the report lists
# exactly the planted failures, with the expected text (tools/debug-expected-text.txt).
# Needs Mesen2 (see tools/run_mesen.sh). Exit status 0 = OK.
set -eu
cd "$(dirname "$0")/.."
make debug
D=build-debug
# What was planted (written by the generators): "CPU #0028 wrong_a" -> "CPU #0028"
{ awk '{print $1" "$2}' $D/cpu-planted.txt $D/spc-planted.txt; echo "SPC unresponsive"; } > $D/expected.txt
mkdir -p $D/mesen
set +e
WALK=1 EXPECTED=$PWD/$D/expected.txt LBL=$PWD/$D/snes-tests.lbl OUT=$PWD/$D/mesen \
    tools/run_mesen.sh $D/snes-tests.sfc > $D/mesen/run.log 2>&1
rc=$?
set -e
grep -E "^(RESULT|FAIL|UNEXPECTED|EXPECTED|PASS|RESET)" $D/mesen/run.log || true
status=0
if [ $rc -ne 0 ]; then echo "Mesen run exited with $rc"; status=1; fi
planted=$(( $(wc -l < $D/expected.txt) ))
listed=$(grep -c "^FAIL [CS]" $D/mesen/run.log || true)
if [ "$planted" -ne "$listed" ]; then echo "planted $planted failures, but the ROM lists $listed"; status=1; fi
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue;; esac
    if ! grep -qF -- "$line" $D/mesen/run.log; then echo "MISSING TEXT: $line"; status=1; fi
done < tools/debug-expected-text.txt
if [ $status -eq 0 ]; then echo "debug build: OK ($planted planted failures, all reported with the expected text)"; fi
exit $status
