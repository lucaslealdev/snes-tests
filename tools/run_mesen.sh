#!/usr/bin/env bash
# Runs a ROM headless in Mesen2 with tools/lua/run_tests.lua (or another script).
# Usage: tools/run_mesen.sh [rom [lua]]      (default: snes-tests.sfc)
# Environment: MESEN (path of the Mesen binary), TIMEOUT (seconds, default 600), OUT, LBL, EXPECTED, ...
#   (see tools/lua/run_tests.lua). The exit code is the one of the Lua script.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="$(realpath "${1:-$ROOT/snes-tests.sfc}")"
LUA="$(realpath "${2:-$ROOT/tools/lua/run_tests.lua}")"
MESEN="${MESEN:-$HOME/.local/share/mesen-2.2.1/mesen/Mesen}"
export OUT="$(realpath -m "${OUT:-$ROOT/build/mesen}")"
export LBL="${LBL:-$ROOT/build/snes-tests.lbl}"
export EXPECTED="${EXPECTED:-$ROOT/expected-failures.txt}"
mkdir -p "$OUT"
# The Mesen working directory must be the one with its settings (portable mode)
cd "$(dirname "$MESEN")"
timeout "$(( ${TIMEOUT:-600} + 30 ))" "$MESEN" --testrunner --timeout="${TIMEOUT:-600}" "$ROM" "$LUA" 2>&1 | grep -v "Uninitialized memory read"
exit "${PIPESTATUS[0]}"
