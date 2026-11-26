#!/usr/bin/env python3
"""WRAM audit (Etapa 3): proves that no CPU test touches the WRAM area reserved for the runner state.

The runner keeps its state across tests (and across the resets used to recover from a hung test) in the WRAM
range RESERVED below. This script imports the CPU test generator and computes, for every test, a set of 24-bit
addresses that the test can access (read or write). The result is mapped to WRAM offsets, taking the bank 0
mirrors ($0000-$1FFF of banks $00-$3F/$80-$BF) into account, and compared with the reserved range.

What is covered for each test:
  - mem_*/emem_*/memw_*/ememw_* locations.
  - `sta`/`stz` instructions in the extra asm code of the test (before_regs, after_checks...).
  - the stack: S (default $01EF, or the s= parameter) +/- 16 bytes, in bank 0, also for E=1 wrapping.
  - D, DBR and index registers: the operand of the instruction under test is evaluated for every addressing
    mode (direct, absolute, long, indexed, indirect, stack relative, ...) using the register inputs of the test
    and the pointers that the test puts in memory. 16-bit and 8-bit index wrapping, page and bank wrapping,
    and the carry into the next bank are all considered.
  - MVN/MVP: the source and destination blocks are simulated.
The script fails if it cannot evaluate an operand (so a new test with a new addressing form cannot slip through).

The same property was also verified dynamically with Mesen2 (tools/lua/wram_writes.lua) on the legacy
cputest-full ROM, which has exactly the same test code: see PLAN.md.

Usage: audit_wram.py [-v]
"""
import importlib.util
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

# Reserved range, as a WRAM offset (bank $7E = $00000-$0FFFF, bank $7F = $10000-$1FFFF). Must match
# tools/gen_cfg.py (RSVWRAM, $7FA000-$7FDFFF).
RESERVED = (0x1A000, 0x1DFFF)
# The UI shadow buffers of the harness ($7E2000-$7E4FFF) are only used by the menu and must not be touched either.
UI_AREA = (0x02000, 0x04FFF)

FLAG_X = 0x10
FLAG_E = 0x100

# TEST_DATA segment of the harness, at $00FFA0 in ROM (test_addr, test_target, test_target24)
ROM_DATA = {0xFFA0: 0x12, 0xFFA1: 0x12, 0xFFA2: 0x00, 0xFFA3: 0x80, 0xFFA4: 0x00, 0xFFA5: 0x80, 0xFFA6: 0x7E}


def load_cpu():
    spec = importlib.util.spec_from_file_location('cpu_gen', os.path.join(ROOT, 'cputest', 'make_cpu_tests.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.generate()
    return mod


def wram_offset(addr):
    """24-bit CPU address -> WRAM offset, or None if the address is not WRAM"""
    bank, off = addr >> 16, addr & 0xFFFF
    if bank in (0x7E, 0x7F):
        return ((bank - 0x7E) << 16) | off
    if (bank < 0x40 or 0x80 <= bank < 0xC0) and off < 0x2000:
        return off
    return None


class Unresolved(Exception):
    pass


def eval_test(t):
    """Returns (set of 24-bit addresses accessed, list of warnings)"""
    acc = set()
    warn = []
    p = t['p']
    x, y, a = t['x'], t['y'], t['a']
    idx8 = bool(p & (FLAG_X | FLAG_E))
    if idx8:
        x &= 0xFF
        y &= 0xFF
    d = t['d'] or 0
    dbr = t['dbr'] or 0
    s = t['s'] if t['s'] is not None else 0x1EF
    mem = dict(ROM_DATA)   # what the test can read (pointers). Includes the TEST_DATA bytes in ROM
    for loc, val in t['mem_input']:
        mem[loc] = val

    def touch(bank, off, n=1):
        for i in range(n):
            acc.add(((bank + ((off + i) >> 16)) & 0xFF) << 16 | ((off + i) & 0xFFFF))

    def touch_bank0(off, n=1):
        # direct page / stack accesses wrap inside bank 0
        for i in range(n):
            acc.add((off + i) & 0xFFFF)

    def read16_bank0(addr):
        """16-bit pointer at a bank 0 address. With E=1 the high byte may come from the start of the page."""
        his = {(addr + 1) & 0xFFFF}
        if p & FLAG_E:
            his.add((addr & 0xFF00) | ((addr + 1) & 0xFF))
        ptrs = {mem[addr] | mem[h] << 8 for h in his if addr in mem and h in mem}
        if not ptrs:
            raise Unresolved(f'pointer at ${addr:04x} not set by the test')
        return ptrs

    def read24_bank0(addr):
        if addr not in mem or (addr + 1) not in mem or (addr + 2) not in mem:
            raise Unresolved(f'long pointer at ${addr:04x} not set by the test')
        return mem[addr] | mem[addr + 1] << 8 | mem[addr + 2] << 16

    # 1. Memory that the test sets or checks
    acc.update(loc for loc, _ in t['mem_input'])
    acc.update(t['mem_output'])

    # 2. sta/stz/ldx... with a numeric address in the extra code
    for text in t['code'].values():
        if not text:
            continue
        for m in re.finditer(r'\bst[azxy]\s+\$([0-9a-fA-F]+)', text):
            digits = m.group(1)
            acc.add(int(digits, 16) if len(digits) <= 6 else int(digits[-6:], 16))

    # 3. The stack. Pushes can go below S, pulls above it
    for off in range(s - 16, s + 17):
        acc.add(off & 0xFFFF)
    # E=1 forces the stack to page 1 (wraps in page 1), included in the window above for the usual values.
    if p & FLAG_E:
        for off in range(0x100, 0x200):
            acc.add(off)

    # 4. The instruction
    ins = (t['code']['ins'] or '').strip().lower()
    mnem, _, op = ins.partition(' ')
    op = op.strip().replace(' ', '')
    if mnem in ('mvn', 'mvp'):
        m = re.fullmatch(r'#\$([0-9a-f]{2}),#\$([0-9a-f]{2})', op)
        if not m:
            raise Unresolved(f'bad mvn/mvp operand {op}')
        src_bank, dst_bank = int(m.group(1), 16), int(m.group(2), 16)
        count = (a & 0xFFFF) + 1
        mask = 0xFF if idx8 else 0xFFFF
        sx, dy = x, y
        step = 1 if mnem == 'mvn' else -1
        for _ in range(count):
            acc.add(src_bank << 16 | sx)
            acc.add(dst_bank << 16 | dy)
            sx = (sx + step) & mask
            dy = (dy + step) & mask
        return acc, warn

    if not op or op.startswith('#') or op.startswith('@') or op in ('a',) or mnem in ('pea', 'per', 'brk', 'cop', 'wdm', 'jml', 'jmp', 'jsr',
                                                                  'jsl', 'rts', 'rtl', 'rti', 'bra', 'brl'):
        if mnem in ('jml', 'jmp', 'jsr', 'jsl'):
            # Only used as a trampoline to code written by the test. Reads from the target address are covered by
            # the mem_* keys, but add the target itself.
            m = re.fullmatch(r'\[?\$([0-9a-f]+)\]?', op)
            if m:
                v = int(m.group(1), 16)
                acc.add(v if len(m.group(1)) > 4 else v)
        return acc, warn

    def index(reg):
        return {'x': x, 'y': y}[reg]

    m = None
    if (m := re.fullmatch(r'\$([0-9a-f]{2}),s', op)):
        touch_bank0(s + int(m.group(1), 16))
        if p & FLAG_E:
            touch_bank0((s & 0xFF00) | ((s + int(m.group(1), 16)) & 0xFF))
    elif (m := re.fullmatch(r'\(\$([0-9a-f]{2}),s\),y', op)):
        for ptr in read16_bank0((s + int(m.group(1), 16)) & 0xFFFF):
            touch(dbr, ptr + y)
    elif (m := re.fullmatch(r'\(\$([0-9a-f]{2}),x\)', op)):
        dp = int(m.group(1), 16)
        lo_addrs = {(d + dp + x) & 0xFFFF}
        if p & FLAG_E:
            lo_addrs.add((d & 0xFF00) | ((dp + x + (d & 0xFF)) & 0xFF))
        resolved = False
        for lo_addr in lo_addrs:
            touch_bank0(lo_addr, 2)
            for hi_addr in {(lo_addr + 1) & 0xFFFF, (lo_addr & 0xFF00) | ((lo_addr + 1) & 0xFF)}:
                if lo_addr in mem and hi_addr in mem:
                    touch(dbr, mem[lo_addr] | mem[hi_addr] << 8, 2)
                    resolved = True
        if not resolved:
            raise Unresolved(f'pointer for `{ins}` not set by the test')
    elif (m := re.fullmatch(r'\(\$([0-9a-f]{2})\),y', op)):
        dp = int(m.group(1), 16)
        base = (d + dp) & 0xFFFF
        bases = {base}
        if p & FLAG_E:
            bases.add((d & 0xFF00) | ((dp + (d & 0xFF)) & 0xFF))
        for b in bases:
            for ptr in read16_bank0(b):
                touch(dbr, ptr + y)
            touch_bank0(b, 2)
    elif (m := re.fullmatch(r'\(\$([0-9a-f]{2})\)', op)):
        dp = int(m.group(1), 16)
        base = (d + dp) & 0xFFFF
        bases = {base}
        if p & FLAG_E:
            bases.add((d & 0xFF00) | ((dp + (d & 0xFF)) & 0xFF))
        for b in bases:
            for ptr in read16_bank0(b):
                touch(dbr, ptr)
            touch_bank0(b, 2)
    elif (m := re.fullmatch(r'\[\$([0-9a-f]{2})\](,y)?', op)):
        dp = int(m.group(1), 16)
        base = (d + dp) & 0xFFFF
        ptr = read24_bank0(base)
        touch(0, ptr + (y if m.group(2) else 0))
        touch_bank0(base, 3)
    elif (m := re.fullmatch(r'\$([0-9a-f]{2})(,[xy])?', op)):
        dp = int(m.group(1), 16)
        i = index(m.group(2)[1]) if m.group(2) else 0
        touch_bank0(d + dp + i, 2)
        if p & FLAG_E:
            touch_bank0((d & 0xFF00) | ((dp + i + (d & 0xFF)) & 0xFF), 2)
    elif (m := re.fullmatch(r'\$([0-9a-f]{4})(,[xy])?', op)):
        i = index(m.group(2)[1]) if m.group(2) else 0
        touch(dbr, int(m.group(1), 16) + i, 2)
    elif (m := re.fullmatch(r'\$([0-9a-f]{6})(,x)?', op)):
        i = x if m.group(2) else 0
        v = int(m.group(1), 16) + i
        touch(v >> 16, v & 0xFFFF, 2)
    else:
        raise Unresolved(f'cannot evaluate operand of `{ins}`')
    return acc, warn


def main():
    verbose = '-v' in sys.argv
    cpu = load_cpu()
    touched = {}  # wram offset -> first test that touched it
    errors = []
    for t in cpu.TESTS:
        try:
            acc, _ = eval_test(t)
        except Unresolved as e:
            errors.append(f'CPU #{t["num"]:04x} ({t["code"]["ins"]}): {e}')
            continue
        for addr in acc:
            off = wram_offset(addr)
            if off is None:
                continue
            touched.setdefault(off, t['num'])
    for (lo, hi), name in ((RESERVED, 'reserved runner state'), (UI_AREA, 'UI shadow buffers')):
        bad = sorted(o for o in touched if lo <= o <= hi)
        for o in bad[:10]:
            errors.append(f'CPU #{touched[o]:04x} touches WRAM offset ${o:05x} ({name})')
    # Print the touched WRAM clusters
    offs = sorted(touched)
    clusters = []
    start = prev = offs[0]
    for o in offs[1:]:
        if o - prev > 0x100:
            clusters.append((start, prev))
            start = o
        prev = o
    clusters.append((start, prev))
    print(f'Analyzed {len(cpu.TESTS)} CPU tests; they can access {len(offs)} distinct WRAM bytes in {len(clusters)} areas:')
    for lo, hi in clusters:
        name = lambda o: f'${0x7E + (o >> 16):02X}:{o & 0xFFFF:04X}'
        print(f'  {name(lo)} - {name(hi)}')
    print(f'Reserved runner state: ${0x7E + (RESERVED[0] >> 16):02X}:{RESERVED[0] & 0xFFFF:04X}'
          f' - ${0x7E + (RESERVED[1] >> 16):02X}:{RESERVED[1] & 0xFFFF:04X}')
    if errors:
        print('AUDIT FAILED:')
        for e in errors:
            print('  ' + e)
        sys.exit(1)
    print('AUDIT OK: no test touches the reserved WRAM range or the UI shadow buffers.')


if __name__ == '__main__':
    main()
