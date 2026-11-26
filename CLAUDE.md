# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

One SNES test ROM, `snes-tests.sfc`, for the 65C816 (`cputest/`) and the SPC-700 (`spctest/`). Python scripts
generate thousands of assembly test cases; a hand-written harness (`harness/`) provides the menu, runs the tests
one after the other without help, and shows a report that describes each failure in plain English. The old
separate ROMs (`cputest-full`, `cputest-basic`, `spctest`) are in the git tag/release `legacy-v1`.

## Commands

Requires ca65/ld65, Python 3 and [spcasm](https://github.com/kleinesfilmroellchen/spcasm) (it is in `~/.cargo/bin`,
which may not be on the PATH).

```sh
make              # snes-tests.sfc (1MB LoROM); all generated files go to build/ (gitignored)
make check        # no emulator: WRAM audit, register-size check, Python tests of the generators/tables
make debug        # build-debug/snes-tests.sfc: tests sabotaged on purpose (generators with --plant)
make package      # snes-tests.zip
make clean
make test         # all of the above plus the Mesen2 tests below (needs MESEN=path/to/Mesen)
```

Tests of the ROM in Mesen2 2.x headless (`--testrunner` + Lua; `tools/run_mesen.sh` wraps it, `MESEN` = binary):
`tools/run_mesen.sh` (all tests must pass, or fail only as listed in `expected-failures.txt`),
`tools/test_menu.sh`, `tools/test_debug_build.sh` (the report of the debug build must list exactly the planted
failures, with the text in `tools/debug-expected-text.txt`), `tools/lua/test_reset.lua`.
In the Lua API `emu.log()` doesn't print in the test runner: use `print()`.

Mesen zeroes WRAM at power-on by default (`Snes.RamPowerOnState`), but a real console and snes9x don't. Relying
on a variable starting at 0 once made the menu show no text on hardware while every Mesen test passed. `main`
now clears all WRAM except the reserved state at boot; keep it that way, and keep testing with garbage RAM:
`DIRTY_RAM=<seed> tools/run_mesen.sh` (full run) and `tools/lua/test_dirty_ram.lua` (menu text), both in
`make test`.

There is no option to run a single test: use the menu to select groups, or temporarily trim `add_all_tests()`
(don't commit that).

## Architecture

Generated files are never edited: change the generator. In `build/`: `cpu-tests.asm` (+ `cpu-meta.inc`),
`spc-tests<N>.asm`/`.spc` (+ `spc-meta.inc`, `spc-data.inc`), `assets.inc`, `snes-tests.cfg` (made by
`tools/gen_cfg.py` from the bank counts of the generators), the map and the label file.

- `cputest/make_cpu_tests.py`, `spctest/make_tests.py`: every instruction has a `*_tests()` function that must be
  run with `run_group(name, function)` in `add_all_tests()` (one group = one checkbox of the menu). Tests are
  declared with `test()` or the addressing-mode expanders. In `test()`, lowercase `a`/`x`/`y`/`p` are inputs, the
  `e*` versions are expected outputs, and `mem_<hex>` / `emem_<hex>` set and check memory (`memw_`/`ememw_`
  for words, cputest only). The two `test()` functions differ: in spctest a `mem_X` without a matching `emem_X`
  is also checked to be unchanged; in cputest it isn't.
- Test numbers are assigned sequentially from 0 and shown in hexadecimal (`CPU #0123`), so inserting a test
  renumbers all later ones. Tests that depend on undocumented or partly documented behavior go last (decimal
  mode in cputest; `daa`/`das`/`div` in spctest, which is what the group tags rely on:
  `tools/test_tables.py` checks it).
- **Metadata for the report.** Each test has a record (instruction text, input registers, mode, tags) in tables
  in the ROM (`cpu_records` 16 bytes, `spc_records` 8 bytes), plus a group table and a string table. Tags:
  `emulation` (E=1), `undocumented` (`comment=UNDOCUMENTED_COMMENT`; the SPC groups `DAA`/`DAS`/`DIV`),
  `decimal` (the decimal groups). The filters of the menu use them. The constants are in `harness/defs.inc`
  and must match the generators (`tools/test_tables.py`).
- **Failure stubs.** Every check of a test (X, Y, P, A, S, DBR, D, memory) gets an inline stub that loads the kind
  of check and the expected value and calls `fail_chk` (a stub is skipped with a `beq`: a shared stub would be
  out of branch range). `@to_fail` (cputest) / `.to_fail` (spctest) is a control flow failure (a branch went the
  wrong way). Only the first failing check is recorded. In spctest, `bra .to_fail` in extra code must be `jmp`.
- **Harness** (`harness/main.asm` includes the others): `hw.asm` (PPU, NMI, joypad, DMA), `text.asm`,
  `state.asm`, `runner_cpu.asm`, `runner_spc.asm`, `run.asm` (run screen, totals), `menu.asm`, `report.asm`.
  Video is Mode 1: BG1 4bpp content, BG3 2bpp header/footer, a sprite cursor, a HDMA gradient on the backdrop.
  The UI is drawn into shadow buffers at `$7E2000-$7E4FFF` and DMA'd by the NMI; the NMI is off while tests run
  (a NMI would write below the stack that tests inspect) and the run screen is updated at vblank by polling.
- Not to be broken: ca65 tracks `.a8/.a16/.i8/.i16` only in source order. `tools/check_modes.py` (in `make
  check`) finds branches to a label assembled with another register size; it needs `.a8`/`.a16` after
  routines that return in another mode. `TAX/TAY` from an 8-bit A copy 16 bits (clear the high byte first), and
  there is no long addressing for LDX/LDY or `lda long,y`.

### Reserved WRAM and memory the tests may not touch

The runner state lives in `$7FA000-$7FDFFF` (`RSVSTATE`, ld65 memory `RSVWRAM`, 16KB, ~12.8KB used):
header (magic "SNTS", version, `rsv_phase`, auto-start flag, checksum of the config), config (filters, bitmaps of
selected groups), runner state (progress, counters, SPC state), failures per group, bitmap of the CPU tests that
will run, and the list of failures (up to 1000 entries of 12 bytes). It survives resets: a valid magic at boot
means a reset in the middle (`rsv_phase`): in the CPU phase the test in progress is recorded as a hang and the
run continues with the next one; in the report/menu phase the menu is shown again, without auto-start. An
invalid magic is a power on. `tools/audit_wram.py` proves that no CPU test reaches `$7FA000-$7FDFFF`,
`$7E2000-$7E4FFF` (UI buffers) or `$0500-$0EFF` (menu/report variables, segment `BSS`); run it when adding tests
(`make check`). A new test that uses an operand form the script doesn't know makes it fail on purpose. The tests
do write `$7E0000-$7E00FF`, `$7E5000`, `$7E7000`, `$7E8000`, `$7EF000-$7EF003`, `$7EFFC0-$7F0300`, `$7F0FDC-$7F1244`,
`$7F7000` and `$7FFEEC-$7FFFFF` (so `$7FC000-$7FFFFF` could not be used), and `$1000-$100F`.

### cputest

- The generator splits the code across ROM banks (`TESTS_PER_BANK`); bank 0 holds only the harness. Each bank has
  its own `bankN_save_results` stub, so generated code must call `jsr bank{bank_num}_save_results`.
- Each test starts with `ldx #num / jsl init_test`. `init_test` fails with "out of order" if a number was
  skipped (errant jump), and skips the tests that aren't enabled (`rsv_cpu_map`) with `cpu_goto`, which also
  resets S, DBR, D and E=0 (tests assume `S=$1EF`, DBR=0, D=0 at the start).
- `harness/main.asm` and `build/snes-tests.cfg` fix addresses the tests rely on: BRK/COP handlers at
  `$1000-$100C` (RAM, 4 bytes each: `jml` to `unexp_*`, installed by `install_handlers`; tests that expect a
  BRK/COP install their own and restore it), `TEST_DATA` at `$00FFA0`, and the ZP variables `result_*`,
  `chk_addr`/`chk_bank` at `$10-$24` (never used by the tests). `$33-$35` and `$FA-$FF` of the zero page are used
  by the tests. Unexpected BRK/COP, "out of order" and hangs are failures, not stops.
- Tests are "emulation" if they run with E=1 (the `advanced=` parameter of the legacy generator is ignored).
- cputest deliberately checks undocumented behavior (see `cputest/README.md`): `PLB` with S=`$1FF` in emulation
  mode reads `$200`, and `(dp,X)` with E=1 and nonzero DL wraps within the page only for the pointer's high
  byte. Don't "fix" these expectations. Mark such tests with `comment=UNDOCUMENTED_COMMENT`.

### spctest

- The test code runs on the SPC-700. The 65C816 uploads each `.spc` file through the IPL ROM and talks to it
  through the four I/O ports. The protocol is documented at the top of `harness/spc_proto.inc` and implemented on
  the other side in `spctest/spc_common.inc`: **change both together**. Summary: RUN command (start test + group
  end), progress in O2/O3, failures and "group done" as an acknowledged byte stream, EXIT back to the IPL.
- A file only contains whole groups, split by `MAX_FILE_CHARS` so each fits in a 32KB bank; the Makefile
  checks the size. Each file has a table of test addresses, so a run can start at any test (used to continue
  after a hang). The number of files comes from the generator (`spc-meta.inc`), not from any hand-written list.
- Hangs: the main CPU notices that the test number didn't change for `SPC_HANG_FRAMES`, records it, sends EXIT
  (the SPC obeys it in `cmd_wait` and while waiting for an acknowledgment, not inside a test) and waits for
  `$BBAA`, uploads the file again and continues; if the IPL doesn't answer, the SPC is "unresponsive" and the
  remaining SPC tests are counted as not run. A file that can't be uploaded after `SPC_LOAD_TRIES` is skipped
  (its tests are counted as not run); `SPC_BAD_FILES_MAX` such files in a row make the SPC "unresponsive".
- Port reads are always confirmed by a second read, on both sides, and every wait of the main CPU has a timeout.
  This is for clone consoles: with single reads, a port read while the other side wrote it lost a byte of the
  protocol, both sides waited forever and the SPC was declared unresponsive on two clones, while an original
  console passed. Mesen doesn't reproduce that race: `tools/test_spc_tolerance.sh` simulates the faults
  (`INJECT` in `run_tests.lua`) instead. Sequence numbers skip `$CC`, which would start an upload in the IPL.

## Behavior notes

- Neither part tests cycle timing. cputest skips STP/WAI, interrupts and memory-mapped registers; spctest skips
  SLEEP/STOP, dummy reads, S-SMP registers and the DSP.
- A CPU test that hangs can only be recovered by a reset (press RESET; the Lua driver does it for you).
- The ROM has no SRAM; the state in WRAM does not survive a power cycle.
