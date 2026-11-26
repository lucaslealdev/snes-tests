-- Scripted test of the menu (Etapa 5), headless in Mesen2. Presses buttons, checks the selection state and the
-- totals in the reserved WRAM, runs a small selection and checks the result.
-- Environment: LBL, and the expected totals computed by tools/test_menu.sh:
--   N_CPU, N_SPC (all tests), CPU_NO_E, CPU_NO_E_UNDOC, CPU_NO_FILTERS, SPC_NO_UNDOC
local LBL = os.getenv("LBL")
local sym = {}
for line in io.lines(LBL) do
  local a, n = line:match("^al%s+(%x+)%s+%.(%S+)")
  if a then sym[n] = tonumber(a, 16) end
end
local WRAM = emu.memType.snesWorkRam
local function rd8(n, o) return emu.read(sym[n] - 0x7E0000 + (o or 0), WRAM) end
local function rd16(n) return rd8(n) + 256 * rd8(n, 1) end
local function num(n) return tonumber(os.getenv(n)) end
local N_CPU, N_SPC = num("N_CPU"), num("N_SPC")

local fails = 0
local function check(name, got, want)
  if got == want then print(string.format("ok   %s = %s", name, tostring(got)))
  else print(string.format("FAIL %s: got %s, expected %s", name, tostring(got), tostring(want))); fails = fails + 1 end
end

-- script: list of {button, check function or nil}
local steps = {}
local function press(b, fn) steps[#steps + 1] = { b = b, fn = fn } end
local totals = function() return rd16("rsv_cpu_total"), rd16("rsv_spc_total") end

press("a", function()   -- cursor on "Emulation mode": off
  check("filters", rd8("rsv_filters"), 6)
  local c, s = totals(); check("cpu total without E=1", c, num("CPU_NO_E")); check("spc total", s, N_SPC)
end)
press("down"); press("a", function()   -- "Undocumented behavior": off
  check("filters", rd8("rsv_filters"), 4)
  local c, s = totals(); check("cpu total without E=1 and undocumented", c, num("CPU_NO_E_UNDOC")); check("spc total", s, num("SPC_NO_UNDOC"))
end)
press("down"); press("a", function()   -- "Decimal mode": off
  check("filters", rd8("rsv_filters"), 0)
  local c, s = totals(); check("cpu total without filters", c, num("CPU_NO_FILTERS")); check("spc total", s, num("SPC_NO_UNDOC"))
end)
press("down"); press("down"); press("a", function()   -- "Select no tests"
  local c, s = totals(); check("cpu total, none selected", c, 0); check("spc total, none selected", s, 0)
  check("selection byte", rd8("rsv_sel_spc"), 0)
end)
press("start", function()   -- Start with nothing selected does nothing
  check("phase after START with nothing selected", rd8("rsv_phase"), 0)
end)
press("down"); press("y", function()   -- Y on the SPC category: all its groups
  local c, s = totals(); check("cpu total, SPC category selected", c, 0); check("spc total", s, num("SPC_NO_UNDOC"))
end)
press("start")   -- run the SPC tests only

local frame, si, hold, wait = 0, 1, 0, 0
local running = false
local pressed
emu.addEventCallback(function()
  local b = {}
  if pressed and hold > 0 then b[pressed] = true end
  emu.setInput(b, 0, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frame = frame + 1
  if frame < 30 then return end
  if hold > 0 then hold = hold - 1; return end
  if wait > 0 then wait = wait - 1; return end
  local st = steps[si - 1]
  if st and st.fn and not st.done then st.done = true; st.fn() end
  if si <= #steps then
    pressed = steps[si].b
    hold = 3; wait = 8
    si = si + 1
    return
  end
  -- all the presses were made: wait for the run to finish
  if rd8("rsv_phase") == 3 and frame > 100 then
    wait = 30
    local c, s = totals()
    check("cpu total of the run", c, 0)
    check("spc tests done", rd16("rsv_spc_done"), num("SPC_NO_UNDOC"))
    check("failures", rd16("rsv_fail_count"), 0)
    check("magic", rd8("rsv_magic"), string.byte("S"))
    print(fails == 0 and "PASS: menu" or ("FAIL: " .. fails .. " check(s) failed"))
    emu.stop(fails == 0 and 0 or 1)
  end
  if frame > 6000 then print("TIMEOUT"); emu.stop(2) end
end, emu.eventType.endFrame)
