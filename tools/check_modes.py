#!/usr/bin/env python3
"""Finds places where the register size that ca65 assumes (.a8/.a16/.i8/.i16, set by the A8/A16/XY8/XY16/AXY16
macros, rep/sep and the directives) differs between a branch and its target label.

ca65 only tracks the sizes in the order of the source text, so after an unconditional jump the target label is
assembled with the size of whatever came before it, which can be wrong: an immediate then gets the wrong number of
bytes and the code is garbage at run time. This script follows the same linear order as the assembler and, for
every branch or jump to a local label (@name), compares the size at the source with the size at the label. A mismatch is
reported unless the code at the label starts with an instruction that sets the sizes itself.

Usage: check_modes.py [harness/main.asm]       (exit status 1 if there are mismatches)
"""
import os
import re
import sys

BRANCHES = {'beq', 'bne', 'bcc', 'bcs', 'bra', 'bmi', 'bpl', 'bvc', 'bvs', 'jmp', 'jsr', 'brl', 'jeq', 'jne', 'jcs', 'jcc',
            'jml', 'jsl'}
SETTERS = {'a8', 'a16', 'xy8', 'xy16', 'axy16', 'rep', 'sep', '.a8', '.a16', '.i8', '.i16'}


def read_lines(path, out, seen_dir=None):
    base = os.path.dirname(path)
    in_macro = False
    for n, line in enumerate(open(path), 1):
        code = line.split(';')[0].rstrip()
        m = re.match(r'\s*\.(macro|endmacro)\b', code)
        if m:
            in_macro = m.group(1) == 'macro'
            continue
        if in_macro:
            continue
        m = re.match(r'\s*\.include\s+"([^"]+)"', code)
        if m and m.group(1).endswith('.asm'):
            read_lines(os.path.join(base, m.group(1)), out)
            continue
        out.append((os.path.basename(path), n, code))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'harness', 'main.asm')
    lines = []
    read_lines(path, lines)
    a, i = 8, 16
    scope = ''
    label_state = {}     # (scope, name) -> (a, i, first instruction after it)
    refs = []            # (file, line, mnemonic, key, a, i)
    pending = []         # labels waiting for their first instruction
    for fname, n, code in lines:
        if not code.strip():
            continue
        m = re.match(r'^\s*(@?[A-Za-z_]\w*):(.*)$', code)
        rest = code
        while m:
            name = m.group(1)
            if not name.startswith('@'):
                scope = name
            key = (scope if name.startswith('@') else '', name)
            label_state[key] = [a, i, None, fname, n]
            pending.append(key)
            rest = m.group(2)
            m = re.match(r'^\s*(@?[A-Za-z_]\w*):(.*)$', rest)
        rest = rest.strip()
        if not rest or rest.startswith('.segment') or rest.startswith('.res') or rest.startswith('.byte') \
                or rest.startswith('.word') or rest.startswith('.faraddr'):
            continue
        tokens = rest.split(None, 1)
        mnem = tokens[0].lower()
        if mnem.startswith('.') and mnem not in ('.a8', '.a16', '.i8', '.i16'):
            continue
        for key in pending:
            label_state[key][2] = mnem
        pending = []
        arg = tokens[1].strip() if len(tokens) > 1 else ''
        if mnem in BRANCHES and mnem not in ('jsr', 'jsl', 'jml') and re.fullmatch(r'@[A-Za-z_]\w*', arg):
            key = (scope if arg.startswith('@') else '', arg)
            refs.append((fname, n, mnem, key, a, i))
        # update the sizes
        if mnem == 'a8' or mnem == '.a8':
            a = 8
        elif mnem == 'a16' or mnem == '.a16':
            a = 16
        elif mnem == 'xy8' or mnem == '.i8':
            i = 8
        elif mnem == 'xy16' or mnem == '.i16':
            i = 16
        elif mnem == 'axy16':
            a = i = 16
        elif mnem in ('rep', 'sep'):
            mm = re.match(r'#\$([0-9A-Fa-f]+)', arg)
            if mm:
                v = int(mm.group(1), 16)
                size = 16 if mnem == 'rep' else 8
                if v & 0x20:
                    a = size
                if v & 0x10:
                    i = size
    bad = 0
    for fname, n, mnem, key, sa, si in refs:
        st = label_state.get(key)
        if not st:
            continue
        la, li, first = st[0], st[1], st[2]
        if first in SETTERS:
            continue
        if (la, li) != (sa, si):
            bad += 1
            print(f'{fname}:{n}: {mnem} {key[1]} at A{sa}/I{si}, but the label ({st[3]}:{st[4]}) is assembled as A{la}/I{li}')
    if bad:
        print(f'{bad} mismatch(es)')
        sys.exit(1)
    print('check_modes: no register size mismatches')


main()
