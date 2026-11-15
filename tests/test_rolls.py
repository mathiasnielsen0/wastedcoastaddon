# Test af need/greed/disenchant/pass i rolls (v0.21): optælling, synk med nye og gamle versioner,
# Rolls-siden, tickeren og sladderen.
# Kør: pip install lupa && python3 tests/test_rolls.py WastedCoast [forever]
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
# Spillets roll-tekster (engelsk klient)
lua.execute('''
LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s"
LOOT_ROLL_DISENCHANT_SELF = "You have selected Disenchant for: %s"
LOOT_ROLL_PASSED_SELF = "You passed on: %s"
LOOT_ROLL_PASSED_SELF_AUTO = "You automatically passed on: %s because you cannot loot that item."
LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s"
TT = {}
GameTooltip.AddLine = function(_, s) TT[#TT+1] = tostring(s) end
GameTooltip.AddDoubleLine = function(_, a, b) TT[#TT+1] = tostring(a) .. " | " .. tostring(b) end
''')
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function findSent(prefix) pump() for i = #SENT, 1, -1 do if SENT[i].msg:sub(1, #prefix) == prefix then return SENT[i].msg end end end
local function msg(m, sender) Fire("CHAT_MSG_ADDON", "WCOAST", m, "GUILD", sender or "Nickchar") end
local function link(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local function loot(s) Fire("CHAT_MSG_LOOT", s) CLOCK = CLOCK + 5 end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
STARTED_LONG_AGO = true
CLOCK = CLOCK + 1000
wipe(db.rolls)
wipe(db.loot)

-- -----------------------------------------------------------------------------
-- Egne valg: need, greed og pass tælles hver for sig
-- -----------------------------------------------------------------------------
loot("You have selected Need for: " .. link(28830, "Dragonspine Trophy"))
loot("You have selected Greed for: " .. link(28831, "Bracers"))
loot("You have selected Greed for: " .. link(28832, "Boots"))
loot("You have selected Disenchant for: " .. link(28833, "Cloak"))
loot("You passed on: " .. link(28834, "Wand"))
loot("You automatically passed on: " .. link(28835, "Mail") .. " because you cannot loot that item.")
local r = db.rolls.Mathias
check(r.rolls == 4, "need/greed/de tæller som rolls, pass gør ikke: " .. tostring(r.rolls))
check(r.nr == 1 and r.gr == 2 and r.dr == 1, "rolls pr. type: " .. tostring(r.nr) .. "/" .. tostring(r.gr) .. "/" .. tostring(r.dr))
check(r.pr == 2, "pass tælles (også automatisk pass): " .. tostring(r.pr))

-- Samme pass to gange lige efter hinanden er ét pass
Fire("CHAT_MSG_LOOT", "You passed on: " .. link(28836, "Gloves"))
Fire("CHAT_MSG_LOOT", "You passed on: " .. link(28836, "Gloves"))
check(r.pr == 3, "dobbelt pass-besked tæller én gang")

-- Sejr: "You won" uden type bruger det valg, man lige har truffet
loot("You won: " .. link(28831, "Bracers"))
check(r.wins == 1 and r.gw == 1 and (r.nw or 0) == 0, "greed-sejr tælles som greed")
loot("You won: " .. link(28830, "Dragonspine Trophy"))
check(r.wins == 2 and r.nw == 1, "need-sejr tælles som need")
check(db.loot[#db.loot].how == "need", "loot-listen kender stadig typen")
-- Sejr uden kendt valg (fx efter /reload): tæller i alt, men ikke under en type
loot("You won: " .. link(29000, "Mystery"))
check(r.wins == 3 and r.nw == 1 and r.gw == 1, "ukendt type giver ingen typet sejr")
-- Need-roll-tallet tæller stadig med i snittet
loot("Need Roll - 77 for " .. link(28830, "Dragonspine Trophy") .. " by Mathiasx")
loot("Greed Roll - 12 for " .. link(28831, "Bracers") .. " by Mathiasx")
check(r.cnt == 2 and r.sum == 89, "roll-tal fra need og greed: " .. tostring(r.sum))

-- -----------------------------------------------------------------------------
-- Synk: nye felter sendes sidst i R-beskeden
-- -----------------------------------------------------------------------------
SENT = {}
RunTimers()
local rm = findSent("R;Mathias;")
check(rm ~= nil, "R sendes")
local f = { strsplit(";", rm) }
check(#f == 15, "R har 15 felter: " .. rm)
check(f[3] == "4" and f[4] == "3", "gamle felter uændret først: " .. rm)
check(f[9] == "1" and f[10] == "1" and f[11] == "2" and f[12] == "1" and f[13] == "1" and f[14] == "0" and f[15] == "3",
    "need/greed/de/pass sidst: " .. rm)

-- En ven på ny version
msg("R;Nick;20;5;800;20;2;98;15;4;5;1;0;0;7")
local n = db.rolls.Nick
check(n.rolls == 20 and n.nr == 15 and n.nw == 4 and n.gr == 5 and n.gw == 1 and n.pr == 7, "nye felter modtages")
check(ns.HasRollTypes(n) and math.abs(ns.NeedShare(n) - 0.75) < 0.001, "need-andel 75%")
-- Samme ven sender senere en besked fra en ældre version: typerne beholdes
msg("R;Nick;21;5;850;21;2;98")
check(n.rolls == 21 and n.nr == 15 and n.pr == 7, "besked uden nye felter sletter ikke need/greed")
-- En ven på en gammel version: kun samlede tal, ingen typer
msg("R;Frode;10;3;500;10;2;99", "Frodex")
check(db.rolls.Frode.rolls == 10 and not ns.HasRollTypes(db.rolls.Frode), "gammel version: ingen need/greed")
check(ns.NeedShare(db.rolls.Frode) == nil, "ingen need-andel uden data")
-- Skæve værdier
msg("R;Andreas;11;3;500;10;2;99;x;-4;;2;0;0;1", "Andreasx")
check(db.rolls.Andreas.nr == nil and db.rolls.Andreas.nw == nil and db.rolls.Andreas.gw == 2, "ugyldige tal ignoreres")

-- -----------------------------------------------------------------------------
-- Rolls-siden viser need / greed og pass, og need-goblinen er orange
-- -----------------------------------------------------------------------------
ns.frame:Show()
for i = 1, #ns.pages do pcall(ns.ShowTab, i) end
check(ns.rollRows ~= nil, "Rolls-siden kan bygges")
ns.core.EXTRA_PAGES[8].refresh()
local byName = {}
for _, row in ipairs(ns.rollRows) do local d = rawget(row, "data") if type(d) == "table" then byName[d.name] = row end end
check(byName.Nick.f[7]:GetText() == "15 / 5" and byName.Nick.f[8]:GetText() == "7", "Nicks need/greed og pass: " .. tostring(byName.Nick.f[7]:GetText()))
check(byName.Mathias.f[7]:GetText() == "1 / 2" and byName.Mathias.f[8]:GetText() == "3", "egne need/greed og pass")
check(tostring(byName.Frode.f[7]:GetText()):find("-", 1, true), "gammel version viser -")
TT = {}
byName.Nick.scripts.OnEnter(byName.Nick)
local tt = table.concat(TT, "\n")
check(tt:find("Need (vundet) | 15 (4)", 1, true) and tt:find("Pass | 7", 1, true) and tt:find("Need-andel | 75%", 1, true), "tooltip med typer: " .. tt)
TT = {}
byName.Frode.scripts.OnEnter(byName.Frode)
check(table.concat(TT, "\n"):find("0.21", 1, true), "tooltip forklarer, at need/greed tælles fra 0.21")

-- -----------------------------------------------------------------------------
-- Tickeren skriver, hvordan loot blev vundet
-- -----------------------------------------------------------------------------
local found = false
for _, it in ipairs(ns.Bar.Items(NOW)) do
    if it.text:find("Dragonspine Trophy", 1, true) then found = it.text end
end
check(found and found:find("(Need)", 1, true), "ticker viser Need: " .. tostring(found))

-- -----------------------------------------------------------------------------
-- Sladder: need-goblin og pass-helgen
-- -----------------------------------------------------------------------------
do
    local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
    db.rolls.Jeppe = { rolls = 10, wins = 1, sum = 0, cnt = 0, nr = 2, nw = 0, gr = 8, gw = 1, dr = 0, dw = 0, pr = 3 }
    db.rolls["Søren"] = { rolls = 5, wins = 0, sum = 0, cnt = 0, nr = 1, nw = 0, gr = 4, gw = 0, dr = 0, dw = 0, pr = 0 }
    local st0 = copy(ns.GossipStats())
    check(st0.Jeppe.nr == 2 and st0.Jeppe.gr == 8 and st0.Jeppe.pr == 3, "øjebliksbillede med need/greed/pass")
    check(st0.Frode.nr == nil, "ingen typer i øjebliksbilledet for gamle versioner")
    local since = NOW
    NOW = NOW + 3600
    db.rolls.Jeppe.nr, db.rolls.Jeppe.rolls = 9, 17                    -- 7 need, 0 greed
    db.rolls["Søren"].pr = 14                                              -- 14 pass
    db.rolls.Frode.rolls = 30                                           -- gammel version: ingen typer
    local txt = table.concat(ns.GossipLines(since, {}, st0, 99), "\n")
    check(txt:find("trykkede Need 7 gange og Greed ikke én eneste gang"), "need-goblin i sladderen: " .. txt)
    check(txt:find("passede 14 gange"), "pass-helgen i sladderen")
    -- Need med lidt greed
    local st1 = copy(ns.GossipStats())
    NOW = NOW + 3600
    db.rolls.Jeppe.nr, db.rolls.Jeppe.gr = 15, 10                       -- 6 need, 2 greed
    txt = table.concat(ns.GossipLines(NOW - 3600, {}, st1, 99), "\n")
    check(txt:find("needede 6 gange og greedede kun 2"), "need med lidt greed: " .. txt)
    -- Balanceret = ingen sladder
    local st2 = copy(ns.GossipStats())
    NOW = NOW + 3600
    db.rolls.Jeppe.nr, db.rolls.Jeppe.gr = 20, 15
    txt = table.concat(ns.GossipLines(NOW - 3600, {}, st2, 99), "\n")
    check(not txt:find("needede") and not txt:find("trykkede Need"), "5 need og 5 greed er ikke grådigt")
end

-- Demo-data har også need/greed
wipe(db.rolls)
SlashCmdList["WASTEDCOAST"]("demo")
local anyTyped = false
for _, rr in pairs(db.rolls) do if ns.HasRollTypes(rr) then anyTyped = true end end
check(anyTyped, "demo-data har need/greed")

return PASSES
'''
passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
