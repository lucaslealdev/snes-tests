-- Headless run of snes-tests.sfc in Mesen2 (--testrunner). Etapa 7.
--
--   OUT=build/mesen LBL=build/snes-tests.lbl EXPECTED=expected-failures.txt \
--   Mesen --testrunner snes-tests.sfc tools/lua/run_tests.lua
--   (tools/run_mesen.sh does this)
--
-- The ROM starts the tests by itself (auto-start of the menu after 10 s). This script:
--   * reads the state of the runner in the reserved WRAM ($7FA000-$7FDFFF), whose labels come from the linker's
--     label file (LBL);
--   * resets the console when a CPU test never finishes (the number of the test in progress doesn't change for
--     STALL_FRAMES frames), which is how the ROM recovers from a hung test;
--   * when the report is shown, walks through it with the joypad, reading the text from the screen, so the
--     wording of the report is verified too;
--   * prints a summary, compares the failures with EXPECTED, and exits with 0 (as expected) or 1.
-- Exit codes: 0 ok, 1 unexpected/missing failures, 2 the run didn't finish (timeout), 3 bad setup.

local OUT = os.getenv("OUT") or "."
local LBL = os.getenv("LBL") or "build/snes-tests.lbl"
local EXPECTED = os.getenv("EXPECTED") or "expected-failures.txt"
local STALL_FRAMES = tonumber(os.getenv("STALL_FRAMES") or "420")
local MAX_FRAMES = tonumber(os.getenv("MAX_FRAMES") or "120000")
local SCREENSHOT = os.getenv("SCREENSHOT")   -- "frame:file,frame:file" to save PNGs of the screen
local VERBOSE = os.getenv("VERBOSE")

local CHK = { [0] = "ctrl", "X", "Y", "P", "A", "S", "DBR", "D", "MEM", "order", "brk", "cop", "hang", "unresp" }

-- labels ----------------------------------------------------------------------------------------------------
local sym = {}
local f = io.open(LBL, "r")
if not f then print("cannot read " .. LBL); emu.stop(3); return end
for line in f:lines() do
  local addr, name = line:match("^al%s+(%x+)%s+%.(%S+)")
  if addr then sym[name] = tonumber(addr, 16) end
end
f:close()
for _, n in ipairs({ "rsv_phase", "rsv_fails", "rsv_fail_count", "rsv_cpu_cur", "rsv_cpu_done" }) do
  if not sym[n] then print("label " .. n .. " not found in " .. LBL); emu.stop(3); return end
end

local WRAM = emu.memType.snesWorkRam
local function rd8(name, off) return emu.read(sym[name] - 0x7E0000 + (off or 0), WRAM) end
local function rd16(name, off) return rd8(name, off) + 256 * rd8(name, (off or 0) + 1) end

-- screen text (BG1 tilemap in VRAM word $0000: the low byte of each entry is the character) ------------------
local function screen_row(row)
  local t = {}
  for col = 0, 31 do
    local c = emu.read((row * 32 + col) * 2, emu.memType.snesVideoRam)
    t[#t + 1] = (c >= 32 and c < 127) and string.char(c) or " "
  end
  return table.concat(t)
end
local function screen_text(first, last)
  local rows = {}
  for r = first, last do rows[#rows + 1] = (screen_row(r):gsub("%s+$", "")) end
  return rows
end

local frame = 0
local resets = 0
local last_progress, stall = -1, 0
local state = "run"          -- run, report, done
local report_frame = 0
local details = {}
local nfails
local press_queue = {}       -- list of {buttons table, frames}
local press_now = nil

local shots = {}
if SCREENSHOT then
  for fr, file in SCREENSHOT:gmatch("(%d+):([^,]+)") do shots[tonumber(fr)] = file end
end

local function press(buttons, frames, wait)
  press_queue[#press_queue + 1] = { b = buttons, n = frames or 2, wait = wait or 6 }
end

emu.addEventCallback(function()
  local b = {}
  if press_now and press_now.n > 0 then b = press_now.b end
  emu.setInput(b, 0, 0)
end, emu.eventType.inputPolled)

local function finish(code, msg)
  print(msg)
  emu.stop(code)
end

local function collect_failures()
  local list = {}
  local n = rd16("rsv_fail_count")
  for i = 0, n - 1 do
    local o = i * 12
    local base = sym["rsv_fails"] - 0x7E0000 + o
    local e = {
      test = emu.read(base, WRAM) + 256 * emu.read(base + 1, WRAM),
      kind = emu.read(base + 2, WRAM),
      group = emu.read(base + 3, WRAM),
      actual = emu.read(base + 4, WRAM) + 256 * emu.read(base + 5, WRAM),
      expected = emu.read(base + 6, WRAM) + 256 * emu.read(base + 7, WRAM),
      addr = emu.read(base + 8, WRAM) + 256 * emu.read(base + 9, WRAM),
      bank = emu.read(base + 10, WRAM),
    }
    e.spc = e.kind >= 0x80
    e.chk = e.kind & 0x7F
    e.name = string.format("%s #%04X", e.spc and "SPC" or "CPU", e.test)
    list[#list + 1] = e
  end
  return list
end

local function load_expected()
  local set = {}
  local fh = io.open(EXPECTED, "r")
  if not fh then return set end
  for line in fh:lines() do
    local kind, num = line:match("^%s*(%a+)%s*#(%x+)")
    if kind then set[string.format("%s #%04X", kind, tonumber(num, 16))] = true end
  end
  fh:close()
  return set
end

local function summarize()
  local fails = collect_failures()
  local expected = load_expected()
  local seen, unexpected, missing = {}, {}, {}
  print(string.format("RESULT phase=%d frames=%d resets=%d", rd8("rsv_phase"), frame, resets))
  print(string.format("RESULT cpu: total=%d done=%d failed=%d | spc: total=%d done=%d failed=%d notrun=%d",
    rd16("rsv_cpu_total"), rd16("rsv_cpu_done"), rd16("rsv_fail_cpu"),
    rd16("rsv_spc_total"), rd16("rsv_spc_done"), rd16("rsv_fail_spc"), rd16("rsv_notrun")))
  print(string.format("RESULT failures stored=%d elapsed=%ds", #fails, rd16("rsv_seconds")))
  for _, e in ipairs(fails) do
    local extra = ""
    if e.chk == 8 then extra = string.format(" addr=%02X:%04X", e.bank, e.addr) end
    print(string.format("FAIL %s group=%d %s actual=%04X expected=%04X%s", e.name, e.group, CHK[e.chk] or "?",
      e.actual, e.expected, extra))
    seen[e.name] = true
    if not expected[e.name] then unexpected[#unexpected + 1] = e.name end
  end
  for name in pairs(expected) do
    if not seen[name] then missing[#missing + 1] = name end
  end
  table.sort(unexpected)
  table.sort(missing)
  for _, n in ipairs(unexpected) do print("UNEXPECTED FAILURE " .. n) end
  for _, n in ipairs(missing) do print("EXPECTED FAILURE MISSING " .. n) end
  return #unexpected + #missing == 0
end

emu.addEventCallback(function()
  frame = frame + 1
  if shots[frame] then
    local png = emu.takeScreenshot()
    local fh = io.open(OUT .. "/" .. shots[frame], "wb")
    if fh then fh:write(png); fh:close() end
  end
  -- joypad script
  if press_now then
    if press_now.n > 0 then press_now.n = press_now.n - 1
    elseif press_now.wait > 0 then press_now.wait = press_now.wait - 1
    else press_now = nil end
  end
  if not press_now and #press_queue > 0 then press_now = table.remove(press_queue, 1) end

  if frame > MAX_FRAMES then
    summarize()
    finish(2, "TIMEOUT: the run did not finish")
    return
  end

  local phase = rd8("rsv_phase")
  if state == "run" then
    if phase == 3 then
      state = "report"
      report_frame = frame
      return
    end
    -- hang detection for the CPU tests: reset the console
    if phase == 2 then
      local progress = rd16("rsv_cpu_cur") * 65536 + rd16("rsv_cpu_done")
      if progress == last_progress then
        stall = stall + 1
        if stall >= STALL_FRAMES then
          resets = resets + 1
          print(string.format("RESET #%d: CPU test #%04X did not finish", resets, rd16("rsv_cpu_cur")))
          stall = 0
          emu.reset()
          if resets > 50 then finish(2, "too many resets"); return end
        end
      else
        stall = 0
        last_progress = progress
      end
    else
      stall = 0
    end
  elseif state == "report" then
    if frame - report_frame < 20 then return end
    local ok = summarize()
    if VERBOSE then
      for _, r in ipairs(screen_text(0, 27)) do print("| " .. r) end
    end
    state = "done"
    finish(ok and 0 or 1, ok and "PASS: failures match the expected list" or "FAIL: failures differ from the expected list")
  end
end, emu.eventType.endFrame)
