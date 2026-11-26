# Builds snes-tests.sfc: the unified 65C816 + SPC-700 test ROM.
# Requires ca65/ld65, spcasm (cargo install spcasm) and Python 3.

BUILD := build
PYTHON ?= python3
CA65 ?= ca65
LD65 ?= ld65
SPCASM ?= spcasm
# `make debug` builds a ROM with sabotaged tests in build-debug/ (PLANT=--plant)
PLANT ?=

# Everything that changes the harness
HARNESS_SRC := $(wildcard harness/*.asm harness/*.inc)

OBJS := $(BUILD)/harness.o $(BUILD)/cpu-tests.o $(BUILD)/cpu-meta.o $(BUILD)/spc-meta.o $(BUILD)/spc-data.o \
        $(BUILD)/assets.o

.PHONY: all package clean check debug test

all: snes-tests.sfc

snes-tests.sfc: $(BUILD)/snes-tests.sfc
	cp $< $@

$(BUILD):
	mkdir -p $(BUILD)

# --- Generators. Each writes several files, so a stamp file represents them.
$(BUILD)/cpu.stamp: cputest/make_cpu_tests.py | $(BUILD)
	$(PYTHON) cputest/make_cpu_tests.py $(PLANT) $(BUILD)
	touch $@

# The number of SPC files is decided by the generator, so the files are assembled by a loop.
$(BUILD)/spc.stamp: spctest/make_tests.py spctest/spc_common.inc | $(BUILD)
	rm -f $(BUILD)/spc-tests*.asm $(BUILD)/spc-tests*.spc
	$(PYTHON) spctest/make_tests.py $(PLANT) $(BUILD)
	cp spctest/spc_common.inc $(BUILD)/
	set -e; for f in $(BUILD)/spc-tests*.asm; do \
	    $(SPCASM) -f plain $$f $${f%.asm}.spc; \
	    size=$$(stat -c %s $${f%.asm}.spc); \
	    if [ $$size -gt 32768 ]; then echo "$$f: assembled code ($$size bytes) doesn't fit in a ROM bank"; exit 1; fi; \
	done
	touch $@

$(BUILD)/assets.stamp: assets/make_assets.py assets/font-base.bin | $(BUILD)
	$(PYTHON) assets/make_assets.py $(BUILD)
	touch $@

$(BUILD)/snes-tests.cfg: tools/gen_cfg.py $(BUILD)/cpu.stamp $(BUILD)/spc.stamp
	$(PYTHON) tools/gen_cfg.py $(BUILD)/cpu-meta.json $(BUILD)/spc-meta.json > $@

# --- Objects
$(BUILD)/harness.o: $(HARNESS_SRC) $(BUILD)/cpu.stamp $(BUILD)/spc.stamp | $(BUILD)
	$(CA65) -I harness -I $(BUILD) harness/main.asm -o $@

$(BUILD)/cpu-tests.o: $(BUILD)/cpu.stamp
	$(CA65) $(BUILD)/cpu-tests.asm -o $@

$(BUILD)/cpu-meta.o: $(BUILD)/cpu.stamp
	$(CA65) $(BUILD)/cpu-meta.inc -o $@

$(BUILD)/spc-meta.o: $(BUILD)/spc.stamp
	$(CA65) $(BUILD)/spc-meta.inc -o $@

$(BUILD)/spc-data.o: $(BUILD)/spc.stamp
	$(CA65) --bin-include-dir $(BUILD) $(BUILD)/spc-data.inc -o $@

$(BUILD)/assets.o: $(BUILD)/assets.stamp
	$(CA65) --bin-include-dir $(BUILD) $(BUILD)/assets.inc -o $@

$(BUILD)/snes-tests.sfc: $(OBJS) $(BUILD)/snes-tests.cfg
	$(LD65) -C $(BUILD)/snes-tests.cfg -o $@ $(OBJS) -m $(BUILD)/snes-tests.map -Ln $(BUILD)/snes-tests.lbl -vm

# Debug ROM with planted failures: build-debug/snes-tests.sfc. tools/test_debug_build.sh runs it and checks the report.
debug:
	$(MAKE) BUILD=build-debug PLANT=--plant build-debug/snes-tests.sfc

# --- Tests of the generators and tables (no emulator needed)
check: $(BUILD)/cpu.stamp $(BUILD)/spc.stamp
	$(PYTHON) tools/audit_wram.py
	$(PYTHON) tools/check_modes.py
	$(PYTHON) -m unittest discover -s tools -p 'test_*.py'

# --- Tests of the ROM in Mesen2 (headless). Set MESEN to the path of the Mesen binary.
test: all check
	tools/run_mesen.sh
	tools/test_menu.sh
	tools/test_debug_build.sh

package: all
	rm -f snes-tests.zip
	zip -j snes-tests.zip snes-tests.sfc README.md LICENSE

clean:
	rm -rf $(BUILD) build-debug
	rm -f snes-tests.sfc snes-tests.zip
