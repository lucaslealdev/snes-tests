# SNES-tests

One ROM, `snes-tests.sfc`, that performs comprehensive tests of the 65C816 and the SPC-700 CPUs of the Super
Nintendo Entertainment System. It has a menu to choose what to run, runs everything by itself, and ends with a
report that describes each failure in plain English.

See the README files in the `cputest` and `spctest` directories for what each CPU test covers.

## Using the ROM

1. **Menu.** At power on the menu shows every group of tests (one per instruction, or family of instructions)
   under two categories, "SPC-700 instructions" and "65C816 instructions". Everything is selected by default.
   - Up/Down: move. L/R: move by a page.
   - A: toggle the item. On a category, A expands or collapses it.
   - Y: toggle the checkbox (on a category: all its groups). X: select or clear all the groups of the category
     of the current item.
   - Start: run the tests (from anywhere in the menu). If nothing is selected, "Start tests" is grayed out and
     says "No tests selected".
   - Three global filters at the top (all on by default): *Emulation mode (E=1)* (the 65C816 tests that run in
     emulation mode), *Undocumented behavior* (65C816 tests of behavior that the manuals don't describe, and the
     SPC-700 `DAA`, `DAS` and `DIV` groups) and *Decimal mode* (65C816 decimal arithmetic).
   - The menu doesn't remember the selection across power cycles: at power on everything is selected.
   - **Auto-start:** the first time the menu is shown after power on, a countdown of 10 seconds starts and the
     tests run with everything selected. Any button cancels it (until the next power on).
2. **Run.** The SPC-700 tests run first, then the 65C816 tests. A screen shows the progress of both, the group
   and test in progress, how many tests passed, failed and were skipped, and the elapsed time. A failure doesn't
   stop the run.
3. **Report.** A summary, for example *"4,812 of 4,820 tests passed. 8 failures in 3 groups: MVN (5), PLB (1),
   SPC DIV (2)."*, then the list of failures. A shows the description of the selected failure: the number of the
   test, its group and instruction, the mode (accumulator and index sizes, native or emulation), the inputs, and
   the **first** check that failed (what was found and what was expected). Choosing "Back to menu" (or Start)
   goes back to the menu with the same selection, and you can run again without a reset.

The report is only shown on the screen. The tests are numbered like in the generated `*-tests.txt` files
(`CPU #0123`, `SPC #0412`, in hexadecimal), which describe every test in detail.

### If the console hangs

- **A 65C816 test that never finishes** (it jumped somewhere it shouldn't) can only be recovered by a reset:
  press RESET. The state is kept in a part of the WRAM that no test touches, so when the ROM boots and finds it,
  it knows that a reset happened during the tests: the test in progress is reported as a hang and the run goes on
  with the next test. (A power cycle starts from scratch.)
- **An SPC-700 test that never finishes** is detected by the main CPU, which tells the SPC to go back to the IPL
  ROM, uploads the test program again and goes on with the next test. A test program that can't be uploaded
  is retried, and if it still fails, only its tests are skipped. If the SPC doesn't answer anymore, the report
  says so ("The SPC-700 stopped responding; N SPC tests were not run") and the 65C816 tests run next.
- **Clone consoles:** the communication with the SPC-700 is written to tolerate their different timing (every
  port read is confirmed by a second read, all waits have generous timeouts, and the SPC can be told to restart
  when the two sides get out of step). A clone may still report a few SPC tests as hangs.
- A reset on the report or menu screen shows the menu again with the previous selection (no auto-start).

## Building

Requires ca65/ld65 ([cc65](https://cc65.github.io/)), [spcasm](https://github.com/kleinesfilmroellchen/spcasm)
and Python 3.

    make            # snes-tests.sfc (1MB LoROM, no SRAM)
    make check      # WRAM audit, generator tests, register size check (no emulator needed)
    make debug      # build-debug/snes-tests.sfc: a ROM with a few tests sabotaged on purpose
    make package    # snes-tests.zip with the ROM
    make clean

Everything that is generated goes to `build/` (which is ignored by git): the test code, the tables used by the
report, the linker configuration, the `.spc` programs of the SPC-700 tests, and the graphics.

### Tests of the ROM itself (need [Mesen2](https://www.mesen.ca/))

`tools/run_mesen.sh` runs a ROM headless (`--testrunner`) with `tools/lua/run_tests.lua`: the ROM starts by
itself (auto-start), the script resets the console if a CPU test hangs, reads the failures from the WRAM, and exits
with 0 if they are the ones listed in `expected-failures.txt` (and 1 if a failure appears that isn't in the list, or
if an expected one disappears). Set `MESEN` to the path of the Mesen binary.

- `tools/run_mesen.sh`: runs `snes-tests.sfc` and compares the failures with `expected-failures.txt`.
- `tools/test_debug_build.sh`: builds the debug ROM, whose planted failures (a wrong expected value, a wrong
  branch, a CPU hang, an unexpected BRK, SPC hangs...) must be reported exactly, with the expected text
  (`tools/debug-expected-text.txt`), which is read from the screen.
- `tools/test_menu.sh`: presses buttons in the menu and checks the selection, the filters and the totals.
- `tools/lua/test_reset.lua`: a reset on the report shows the menu again, with the selection and without auto-start.

## Releases

Download from the [releases page](https://github.com/gilyon/snes-tests/releases). The first version of this project
had three ROMs (`cputest-full.sfc`, `cputest-basic.sfc` and `spctest.sfc`) and is still available there as the
release `legacy-v1` (git tag `legacy-v1`).

## How it works

See `CLAUDE.md` for the architecture, the layout of the WRAM that is reserved for the state, the protocol
with the SPC-700 and the rules that the tests impose. `PLAN.md` has the plan of this rewrite and the decisions
that were made.
