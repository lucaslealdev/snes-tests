"""Consistency tests for the generators and the metadata tables (Etapa 2).

Run with:  python3 -m unittest discover -s tools -p 'test_*.py'   (or `make check`)
"""
import importlib.util
import os
import re
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def load(name, relpath):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, relpath))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.generate()
    return mod


def defs():
    """Constants of harness/defs.inc"""
    out = {}
    for line in open(os.path.join(ROOT, 'harness', 'defs.inc')):
        m = re.match(r'^(\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)', line)
        if m:
            v = m.group(2)
            out[m.group(1)] = int(v[1:], 16) if v.startswith('$') else int(v)
    return out


CPU = load('cpu_gen', 'cputest/make_cpu_tests.py')
SPC = load('spc_gen', 'spctest/make_tests.py')
DEFS = defs()


class GroupTests(unittest.TestCase):
    def check_groups(self, mod):
        pos = 0
        for i, g in enumerate(mod.GROUPS):
            self.assertEqual(g['index'], i)
            self.assertEqual(g['first'], pos, g['name'])
            self.assertGreater(g['count'], 0, g['name'])
            self.assertEqual(len([t for t in mod.TESTS if t['group'] == i]), g['count'], g['name'])
            self.assertLessEqual(len(g['name']), 24, g['name'])
            pos += g['count']
        self.assertEqual(pos, len(mod.TESTS))
        self.assertEqual([t['num'] for t in mod.TESTS], list(range(len(mod.TESTS))))

    def test_cpu_groups(self):
        self.check_groups(CPU)
        self.assertLessEqual(len(CPU.GROUPS), DEFS['MAX_GROUPS'])
        self.assertLessEqual(len(CPU.TESTS), DEFS['MAX_TESTS'])

    def test_spc_groups(self):
        self.check_groups(SPC)
        self.assertLessEqual(len(SPC.GROUPS), DEFS['MAX_GROUPS'])
        self.assertLessEqual(len(SPC.TESTS), DEFS['MAX_TESTS'])

    def test_decimal_groups_are_last_in_cpu(self):
        flags = [g['decimal'] for g in CPU.GROUPS]
        self.assertEqual(flags, sorted(flags))

    def test_undocumented_groups_are_last_in_spc(self):
        flags = [g['undocumented'] for g in SPC.GROUPS]
        self.assertEqual(flags, sorted(flags))
        self.assertEqual([g['name'] for g in SPC.GROUPS if g['undocumented']], ['DAA', 'DAS', 'DIV'])


class TagTests(unittest.TestCase):
    def test_tag_values_match_defs(self):
        self.assertEqual(CPU.TAG_EMULATION, DEFS['TAG_EMULATION'])
        self.assertEqual(CPU.TAG_UNDOCUMENTED, DEFS['TAG_UNDOCUMENTED'])
        self.assertEqual(CPU.TAG_DECIMAL, DEFS['TAG_DECIMAL'])
        self.assertEqual(CPU.HAS_S, DEFS['HAS_S'])
        self.assertEqual(CPU.HAS_D, DEFS['HAS_D'])
        self.assertEqual(CPU.HAS_DBR, DEFS['HAS_DBR'])
        self.assertEqual(SPC.TAG_UNDOCUMENTED, DEFS['TAG_UNDOCUMENTED'])

    def test_cpu_tags(self):
        for t in CPU.TESTS:
            self.assertEqual(bool(t['tags'] & CPU.TAG_EMULATION), bool(t['p'] & CPU.FLAG_E), t['num'])
            self.assertEqual(bool(t['tags'] & CPU.TAG_DECIMAL), CPU.GROUPS[t['group']]['decimal'], t['num'])
        undocumented = [t for t in CPU.TESTS if t['tags'] & CPU.TAG_UNDOCUMENTED]
        self.assertGreaterEqual(len(undocumented), 2)  # (dp,x) with E=1 and PLB with S=$1FF
        self.assertTrue(any(t['ins'].startswith('plb') for t in undocumented))

    def test_spc_tags(self):
        for t in SPC.TESTS:
            self.assertEqual(bool(t['tags']), SPC.GROUPS[t['group']]['undocumented'], t['num'])


class CheckTests(unittest.TestCase):
    def test_kinds_match_defs(self):
        for name in ('CTRL', 'X', 'Y', 'P', 'A', 'S', 'DBR', 'D', 'MEM'):
            self.assertEqual(getattr(CPU, 'CHK_' + name), DEFS['CHK_' + name], name)
        for name in ('CTRL', 'X', 'Y', 'P', 'A', 'MEM'):
            self.assertEqual(getattr(SPC, 'CHK_' + name), DEFS['CHK_' + name], name)
        self.assertEqual(SPC.CHK_SP, DEFS['CHK_S'])

    def test_every_test_has_checks(self):
        for mod in (CPU, SPC):
            for t in mod.TESTS:
                kinds = [c[0] for c in t['checks']]
                self.assertIn(mod.CHK_X, kinds, t['num'])
                self.assertIn(mod.CHK_Y, kinds, t['num'])
                self.assertIn(mod.CHK_P, kinds, t['num'])
                self.assertIn(mod.CHK_A, kinds, t['num'])

    def test_check_values_fit(self):
        for t in CPU.TESTS:
            for kind, expected, addr in t['checks']:
                if kind == CPU.CHK_MEM:
                    self.assertTrue(0 <= expected <= 0xFF and addr is not None and 0 <= addr <= 0xFFFFFF)
                else:
                    self.assertTrue(0 <= expected <= 0xFFFF, (t['num'], kind, expected))
        with open(os.path.join(os.path.dirname(__file__), '..', 'spctest', 'spc_common.inc')) as f:
            spc_vars = set(re.findall(r'^(\w+):', f.read(), re.M))
        for t in SPC.TESTS:
            for kind, expected, addr in t['checks']:
                if isinstance(expected, str):
                    # expected value known at run time: only memory checks, against a variable of spc_common.inc
                    self.assertEqual(kind, SPC.CHK_MEM, t['num'])
                    self.assertIn(expected, spc_vars, t['num'])
                    continue
                self.assertTrue(0 <= expected <= 0xFF)
                if kind == SPC.CHK_MEM:
                    self.assertTrue(0 <= addr <= 0xFFFF)

    def test_failure_stub_count_matches_checks(self):
        # Every check emits exactly one `jml fail_chk` in the CPU code
        code = '\n'.join(CPU.asm_code)
        stubs = code.count('jml fail_chk')
        checks = sum(len(t['checks']) for t in CPU.TESTS)
        ctrl = code.count('@to_fail:')
        self.assertEqual(stubs, checks + ctrl)


class SpcFileTests(unittest.TestCase):
    def test_files_hold_whole_groups(self):
        files = SPC.pack_files()
        pos = 0
        for f in files:
            self.assertEqual(f['first'], pos)
            self.assertEqual(f['count'], sum(g['count'] for g in f['groups']))
            pos += f['count']
        self.assertEqual(pos, len(SPC.TESTS))
        for g in SPC.GROUPS:
            self.assertIn('file', g)

    def test_test_numbers_fit_in_12_bits(self):
        # The SPC protocol sends the test number in 12 bits
        self.assertLess(len(SPC.TESTS), 4096)


if __name__ == '__main__':
    unittest.main()
