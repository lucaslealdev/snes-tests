#!/usr/bin/env bash
# Scripted test of the menu in Mesen2 (headless). Needs Mesen2, see tools/run_mesen.sh.
set -eu
cd "$(dirname "$0")/.."
make -s
eval "$(python3 - <<'PY'
import sys
sys.path.insert(0, 'tools')
import importlib.util
def load(n, p):
    spec = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m); m.generate(); return m
cpu = load('cpu', 'cputest/make_cpu_tests.py'); spc = load('spc', 'spctest/make_tests.py')
T = cpu.TESTS
print('export N_CPU=%d N_SPC=%d' % (len(T), len(spc.TESTS)))
print('export CPU_NO_E=%d' % sum(1 for t in T if not t['tags'] & 1))
print('export CPU_NO_E_UNDOC=%d' % sum(1 for t in T if not t['tags'] & 3))
print('export CPU_NO_FILTERS=%d' % sum(1 for t in T if not t['tags'] & 7))
print('export SPC_NO_UNDOC=%d' % sum(1 for t in spc.TESTS if not t['tags']))
PY
)"
LBL=$PWD/build/snes-tests.lbl OUT=$PWD/build/mesen tools/run_mesen.sh snes-tests.sfc tools/lua/test_menu.lua
