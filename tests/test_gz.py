# Test af gz-knappen (Gz.lua): Gz-knappen på vennens level-popup, beskeden til vennen, vindue,
# cooldown og spam-værn, slå fra, bande-baren, synk, demo og kommandoer.
# Kør: pip install lupa && python3 tests/test_gz.py WastedCoast [forever]
import sys, lupa.lua51 as L
from wowmock import MOCK, load_addon

ADDON = sys.argv[1]
FOREVER = len(sys.argv) > 2 and sys.argv[2] == "forever"
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
if FOREVER:
    lua.execute('''
function GetBuildInfo() return "1.60.0", "1", "", 16001 end
C_Item = {
  GetItemInfo = GetItemInfo, IsEquippableItem = IsEquippableItem, IsEquippedItem = IsEquippedItem,
  GetItemCount = GetItemCount, GetItemIconByID = GetItemIcon,
}
GetItemInfo, IsEquippableItem, IsEquippedItem, GetItemCount, GetItemIcon = nil, nil, nil, nil, nil
''')
lua.execute('''
TT = {}
GameTooltip.AddLine = function(_, s) TT[#TT+1] = s end
GameTooltip.AddDoubleLine = function(_, a, b) TT[#TT+1] = a .. " | " .. tostring(b) end
''')
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function hb(friend, char, class, level, zone)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "H", friend, char, class, level, 100, zone, 0, "", "1" }, ";"), "GUILD", char)
end
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function sentWith(prefix) pump() local out, seen = {}, {} for _, s in ipairs(SENT) do if s.msg:sub(1, #prefix) == prefix and not seen[s.msg] then seen[s.msg] = true out[#out+1] = s.msg end end return out end
local function split(s) local t = {} for p in (s .. ";"):gmatch("(.-);") do t[#t+1] = p end return t end
local function printed(s) for _, p in ipairs(PRINTS) do if p:find(s, 1, true) then return true end end end
local function ttHas(s) for _, l in ipairs(TT) do if tostring(l):find(s, 1, true) then return true end end end
-- En ven dinger: XU (popuppen) og XL (levelet med tid), som vennens addon sender dem
local function ding(friend, char, class, level, at)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XU", friend, char, class, level, 3600 }, ";"), "GUILD", char)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XL", friend, level, at or NOW }, ";"), "GUILD", char)
end
local function gz(from, to, level, nonce, line, at)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XG", from, to, level, nonce, line or 1, at or NOW }, ";"), "GUILD", from .. "char")
end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
CLOCK = CLOCK + 1000
local toasts = {}
local realToast = ns.Toast
ns.Toast = function(o) toasts[#toasts+1] = o return realToast(o) end
local function lastToast(kind) for i = #toasts, 1, -1 do if toasts[i].kind == kind then return toasts[i] end end end
local Gz = ns.Gz
check(Gz ~= nil and ns.GzSend ~= nil and ns.HandleGzMessage ~= nil, "Gz.lua er indlæst")
hb("Nick", "Nickchar", "MAGE", 30, "Westfall")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Westfall")

-- -----------------------------------------------------------------------------
-- Level-popuppen har en Gz-knap
-- -----------------------------------------------------------------------------
ding("Nick", "Nickchar", "MAGE", 31)
local lv = lastToast("levelup")
check(lv and lv.action and lv.action.label == "Gz", "vennens level-popup har en Gz-knap")
check(lv.dur == 10, "popuppen med knap står lidt længere")
check(Gz.LatestDing() == "Nick", "Nick er den, der dingede senest")

SENT = {}
check(lv.action.onClick() == true, "klik på knappen sender et gz")
local msgs = sentWith("XG;")
check(#msgs == 1, "én XG-besked: " .. #msgs)
local t = split(msgs[1])
check(t[2] == "Mathias" and t[3] == "Nick" and t[4] == "31", "beskeden: fra, til og levelet")
check(#msgs[1] <= 255 and not msgs[1]:find("|", 1, true), "beskeden er kort og ren")
check(printed("Du sagde tillykke til Nick"), "du får en bekræftelse")
local sent, recv = Gz.Counts()
check(sent.Mathias == 1 and recv.Nick == 1, "gz tælles")

-- Kun ét gz pr. level, og cooldown
local ok, _, why = Gz.Can("Nick")
check(not ok and why:find("allerede"), "kun ét gz pr. level: " .. tostring(why))
ding("Jeppe", "Jepchar", "ROGUE", 31)
ok, _, why = Gz.Can("Jeppe")
check(not ok and why:find("Rolig"), "cooldown mellem dine gz: " .. tostring(why))
CLOCK = CLOCK + Gz.COOLDOWN + 1
check(Gz.Can("Jeppe") == true, "efter cooldown kan du igen")

-- Ikke dig selv, ikke gamle levels, ikke gæt
ok, _, why = Gz.Can("Mathias")
check(not ok and why:find("dig selv"), "ikke dig selv")
db.levelAt.Rasmus = { l = 20, t = NOW - Gz.WINDOW - 5 }
check(not Gz.Can("Rasmus"), "et level over 15 min gammelt kan ikke bruges")
db.levelAt.Rasmus = { l = 20, t = NOW, g = true }
check(not Gz.Can("Rasmus"), "et gættet level kan ikke bruges")
db.levelAt.Rasmus = { l = 20, t = NOW, d = true }
check(not Gz.Can("Rasmus"), "et demo-level kan ikke bruges")
db.levelAt.Rasmus = nil

-- -----------------------------------------------------------------------------
-- Modtageren
-- -----------------------------------------------------------------------------
toasts = {}
gz("Nick", "Mathias", 25, "111111", 2, NOW)
local got = lastToast("levelup")
check(got and got.head == "GZ" and got.title:find("Nick") and got.text:find("Nick klapper ad dig. Level 25!", 1, true), "du får en GZ-popup: " .. tostring(got and got.text))
check(got.sound == "levelup", "med ding-lyden")
toasts = {}
gz("Nick", "Mathias", 25, "111112", 1, NOW)
check(not lastToast("levelup"), "samme ven, samme level: kun én gang")
gz("Jeppe", "Mathias", 25, "222222", 1, NOW)
check(lastToast("levelup") ~= nil, "en anden ven må gerne")
-- Max level har sine egne linjer
check(Gz.Text(1, "A", "B", ns.core.MAX_LEVEL):find("ENDELIG", 1, true), "max level får en særlig tekst")
-- Ugyldige beskeder
local before = #db.gz.log
gz("Nobody", "Mathias", 25, "333333")
gz("Nick", "Mathias", "abc", "333334")
gz("Nick", "Mathias", 25, "")
gz("Nick", "Nick", 25, "333335")
check(#db.gz.log == before, "ugyldige beskeder ignoreres")
-- Slået fra: kun en linje i chatten
db.settings.gz = false
toasts = {}
PRINTS = {}
gz("Søren", "Mathias", 26, "444444", 1, NOW)
check(not lastToast("levelup") and printed("Søren"), "slået fra: ingen popup, kun chat")
db.settings.gz = nil
-- Gamle gz fra synk giver ingen popup
toasts = {}
gz("Andreas", "Mathias", 12, "555555", 1, NOW - 3 * 86400)
check(not lastToast("levelup") and #db.gz.log == before + 2, "gamle gz gemmes uden popup")

-- -----------------------------------------------------------------------------
-- Bande-baren: Gz i tids-kolonnen og klik på level-nyheden
-- -----------------------------------------------------------------------------
local Bar = ns.Bar
local jl
for _, it in ipairs(Bar.Items(nil, 100)) do if it.ding == "Jeppe" and it.kind == "level" then jl = it end end
check(jl and Bar.CanGz(jl), "Jeppes level kan bruges til gz")
Bar.UpdateTicker()
local row = ns.barFrame.rows[1]
row.line = { text = "x", ago = "1m", item = jl }
TT = {}
row.scripts.OnEnter(row)
check(row.time.text_ == "Gz" and row.chip.shown, "musen over level-nyheden viser Gz")
check(ttHas("sig tillykke til Jeppe"), "tooltippen forklarer klikket")
row.scripts.OnLeave(row)
check(row.time.text_ == "1m", "og tiden kommer tilbage")
SENT = {}
row.scripts.OnClick(row)
msgs = sentWith("XG;")
check(#msgs == 1 and split(msgs[1])[3] == "Jeppe", "klik på level-nyheden sender gz til Jeppe")
check(not Bar.CanGz(jl), "bagefter kan den ikke bruges igen")
local found
for _, it in ipairs(Bar.Items(nil, 100)) do if it.kind == "gz" and it.text:find("sagde tillykke", 1, true) then found = true end end
check(found, "gz står i nyhederne")
check(not Bar.IsHot({ kind = "gz", t = NOW }), "gz folder ikke baren ud")

-- -----------------------------------------------------------------------------
-- Synk, demo, nulstilling og kommandoer
-- -----------------------------------------------------------------------------
SENT = {}
Gz.SendLog()
msgs = sentWith("XG;Mathias;")
check(#msgs == 2, "synk sender dine egne gz: " .. #msgs)
local slash = SlashCmdList["WASTEDCOAST"]
slash("gz fra")
check(db.settings.gz == false, "/wc4ever gz fra")
slash("gz til")
check(db.settings.gz == nil, "/wc4ever gz til")
toasts = {}
slash("gz test")
check(lastToast("levelup") and lastToast("levelup").head == "GZ", "/wc4ever gz test viser popuppen")
PRINTS = {}
CLOCK = CLOCK + Gz.COOLDOWN + 1
slash("gz")
check(printed("Ingen af vennerne") or printed("allerede"), "/wc4ever gz uden en frisk ding")
ding("Nick", "Nickchar", "MAGE", 32)
SENT = {}
slash("gz nick")
check(#sentWith("XG;Mathias;Nick;32") == 1, "/wc4ever gz nick")
Gz.MakeDemo()
local demos = 0
for _, e in ipairs(db.gz.log) do if e.demo then demos = demos + 1 end end
check(demos >= 1, "demo-gz")
SENT = {}
Gz.SendLog()
for _, m in ipairs(sentWith("XG;")) do check(not m:find("demo"), "demo sendes aldrig") end
Gz.ClearDemo()
for _, e in ipairs(db.gz.log) do check(not e.demo, "demo fjernet") end
Gz.Reset()
check(#db.gz.log == 0, "nulstil")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
