-- Reset on the report screen must show the menu again with the previous selection and without auto-start
-- (Etapa 3.3), i.e. the reserved WRAM must survive the reset. Environment: LBL
local sym = {}
for line in io.lines(os.getenv("LBL")) do
  local a, n = line:match("^al%s+(%x+)%s+%.(%S+)")
  if a then sym[n] = tonumber(a, 16) end
end
local WRAM = emu.memType.snesWorkRam
local function rd8(n, o) return emu.read(sym[n] - 0x7E0000 + (o or 0), WRAM) end
local frame, reset_at = 0, nil
local fails = 0
local function check(name, got, want)
  if got == want then print(string.format("ok   %s = %s", name, tostring(got)))
  else print(string.format("FAIL %s: got %s, expected %s", name, tostring(got), tostring(want))); fails = fails + 1 end
end
emu.addEventCallback(function()
  frame = frame + 1
  if not reset_at and rd8("rsv_phase") == 3 and frame > 100 then
    check("autostart flag before the reset", rd8("rsv_autostart_used"), 1)
    reset_at = frame
    emu.reset()
  elseif reset_at and frame == reset_at + 900 then   -- longer than the 10 s of the auto-start
    check("phase 900 frames after the reset (menu, no auto-start)", rd8("rsv_phase"), 0)
    check("filters kept", rd8("rsv_filters"), 7)
    check("selection kept", rd8("rsv_sel_cpu"), 255)
    print(fails == 0 and "PASS: reset" or "FAIL: reset")
    emu.stop(fails == 0 and 0 or 1)
  end
  if frame > 5000 then print("TIMEOUT"); emu.stop(2) end
end, emu.eventType.endFrame)
