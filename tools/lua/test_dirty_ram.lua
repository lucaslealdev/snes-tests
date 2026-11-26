-- Power-on test with garbage in WRAM, like a real console (and snes9x). Mesen zeroes the RAM by default, which
-- hides reads of uninitialized variables. Fills all 128 KB of WRAM with pseudo-random bytes before the first
-- instruction, waits for the menu and checks that the BG1 (content) and BG3 (header/footer) tilemaps have text.
-- Environment: SEED (optional, default 1).
local WRAM = emu.memType.snesWorkRam
local VRAM = emu.memType.snesVideoRam

local seed = tonumber(os.getenv("SEED") or "1")
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return (seed >> 16) & 0xFF
end
for a = 0, 0x1FFFF do emu.write(a, rnd(), WRAM) end

-- counts the tilemap entries that are not blank (tile $00 or $20) in a 32x32 map at the VRAM byte address
local function text_tiles(base)
  local n = 0
  for i = 0, 0x3FF do
    local t = emu.read(base + i * 2, VRAM)
    if t ~= 0 and t ~= 0x20 then n = n + 1 end
  end
  return n
end

local frame = 0
emu.addEventCallback(function()
  frame = frame + 1
  if frame == 120 then
    local bg1 = text_tiles(0x0000)   -- word $0000
    local bg3 = text_tiles(0x0800)   -- word $0400
    print(string.format("BG1 text tiles: %d, BG3 text tiles: %d", bg1, bg3))
    if bg1 >= 100 and bg3 >= 20 then
      print("PASS: menu has text with garbage in WRAM at power-on")
      emu.stop(0)
    else
      print("FAIL: menu has no text with garbage in WRAM at power-on")
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
