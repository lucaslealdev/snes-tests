-- Dynamic WRAM audit (Etapa 3): logs every address of the WRAM that is written while a ROM runs, one
-- "OFFSET COUNT" line per address (the offset is the CPU address, $7E0000-$7FFFFF, or $0000-$1FFF).
-- Run it on the legacy cputest-full ROM (tag legacy-v1, same test code) with:
--   OUT=wram.txt Mesen --testrunner cputest-full.sfc tools/lua/wram_writes.lua
-- and compare with the reserved range ($7FA000-$7FDFFF): no address in it may appear.
-- The legacy ROM shows "Success" at VRAM word $32 when it finishes. Recorded result (Etapa 3): 656 distinct
-- addresses, none of them in $7E2000-$7E4FFF or $7FA000-$7FDFFF.
-- logs every WRAM write (offset in 0..0x1FFFF) -> page-granular histogram
local hist = {}
local nbytes = {}
local function cb(addr, value)
  -- try treating addr as offset in snesWorkRam
  local a = addr
  hist[a] = (hist[a] or 0) + 1
end
emu.addMemoryCallback(cb, emu.callbackType.write, 0, 0x1FFFF, emu.cpuType.snes, emu.memType.snesWorkRam)
local frame = 0
local function vtext(wordaddr, n)
  local s = {}
  for i=0,n-1 do
    local c = emu.read((wordaddr+i)*2, emu.memType.snesVideoRam)
    s[#s+1] = string.char(c>=32 and c<127 and c or 32)
  end
  return table.concat(s)
end
emu.addEventCallback(function()
  frame = frame + 1
  if vtext(0x32,7)=="Success" or frame > 3000 then
    local keys = {}
    for k in pairs(hist) do keys[#keys+1]=k end
    table.sort(keys)
    local f = io.open(os.getenv("OUT") or "wram.txt","w")
    for _,k in ipairs(keys) do f:write(string.format("%06X %d\n", k, hist[k])) end
    f:close()
    print("done frames="..frame.." addrs="..#keys)
    emu.stop(0)
  end
end, emu.eventType.endFrame)
