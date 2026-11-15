# Test af gruppe-milepæle (Milestones.lua): tallene, første kørsel (stille), nye mål med fest-popup,
# den N'te hændelse som udløser, XM ind og ud, dubletter, ødelagte beskeder, slå fra, synk, demo,
# bande-baren, siden og kommandoer.
# Kør: pip install lupa && python3 tests/test_milestones.py WastedCoast [forever]
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
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function sentWith(prefix) pump() local out, seen = {}, {} for _, s in ipairs(SENT) do if s.msg:sub(1, #prefix) == prefix and not seen[s.msg] then seen[s.msg] = true out[#out+1] = s.msg end end return out end
local function split(s) local t = {} for p in (s .. ";"):gmatch("(.-);") do t[#t+1] = p end return t end
local function printed(s) for _, p in ipairs(PRINTS) do if p:find(s, 1, true) then return true end end end
local function xm(from, cat, tier, at, by, silent)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XM", from, cat, tostring(tier), tostring(at), by or "", silent or "" }, ";"), "GUILD", from .. "char")
end
local function tick() for _, tk in ipairs(TICKERS) do if tk.d == 20 then tk.f() end end end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
local toasts = {}
local realToast = ns.Toast
ns.Toast = function(o) toasts[#toasts+1] = o return realToast(o) end
local function goalToasts() local n = 0 for _, o in ipairs(toasts) do if o.head == "GRUPPE-MILEPÆL" then n = n + 1 end end return n end
local function lastGoal() for i = #toasts, 1, -1 do if toasts[i].head == "GRUPPE-MILEPÆL" then return toasts[i] end end end
local M = ns.Milestones
check(M ~= nil and ns.HandleMilestoneMessage ~= nil and ns.MilestonesSlash ~= nil, "Milestones.lua er indlæst")
local C = ns.core

-- Data fra før: 12 gamle dødsfald, karakterer med 130 levels i alt (plus din egen)
for friend, char in pairs({ Nick = "Nickchar", Jeppe = "Jepchar", Frode = "Frochar" }) do
    C.UpdateChar(friend, char, { class = "MAGE", level = 30, gold = 1000000, zone = "Westfall" }, NOW)
end
C.UpdateChar("Søren", "Sorchar", { class = "ROGUE", level = 40, gold = 0, zone = "Westfall" }, NOW)
for i = 1, 12 do
    table.insert(db.events, { id = "old-" .. i, name = "Nickchar", friend = "Nick", class = "MAGE", time = NOW - 10 * 86400 + i })
end
local v = M.Values()
check(v.dead == 12, "dødsfald tælles: " .. v.dead)
check(v.lvl >= 130, "levels lægges sammen: " .. v.lvl)
check(v.gold >= 300 and v.gold < 310, "guld i guld: " .. v.gold)

-- Før login er faldet til ro, sker der intet
SENT = {}
tick()
check(next(db.milestones.hit) == nil, "intet de første sekunder efter login")

-- Første kørsel: det, banden allerede har nået, gemmes stille
CLOCK = CLOCK + 1000
tick()
local hit = db.milestones.hit
check(hit["dead:10"] and hit["dead:10"].s == 1, "dead:10 gemt stille")
check(hit["lvl:100"] and hit["lvl:100"].s == 1, "lvl:100 gemt stille")
check(hit["gold:100"] and hit["gold:100"].s == 1, "gold:100 gemt stille")
check(not hit["dead:25"], "dead:25 er ikke nået")
check(goalToasts() == 0, "ingen byge af popups første gang")
check(hit["dead:10"].t == NOW - 10 * 86400 + 10 and hit["dead:10"].by == "Nick", "den 10. død afgør tid og ven")
local msgs = sentWith("XM;")
check(#msgs >= 3, "de stille mål sendes: " .. #msgs)
for _, m in ipairs(msgs) do
    local t = split(m)
    check(t[2] == "Mathias" and t[7] == "1", "sendt som stille: " .. m)
    check(#m <= 255, "kort besked")
end
check(db.milestones.init == true, "første kørsel er gjort")

-- Nye dødsfald: nummer 25 udløser en fest
SENT = {}
for i = 13, 25 do
    local who = (i == 25) and "Jeppe" or "Nick"
    table.insert(db.events, { id = "new-" .. i, name = who .. "char", friend = who, class = "MAGE", time = NOW - 100 + i })
end
PRINTS = {}
check(M.Check() >= 1, "nyt mål fundet")
check(hit["dead:25"] and not hit["dead:25"].s and hit["dead:25"].by == "Jeppe", "dead:25 nået af Jeppe")
check(hit["dead:25"].t == NOW - 75, "tiden er den 25. døds tid")
check(goalToasts() == 1, "fest-popup")
local o = lastGoal()
check(o.kind == "trophy" and o.title:find("25 dødsfald", 1, true), "popuppen: " .. tostring(o.title))
check(o.text:find("Jeppe stod for nummer 25", 1, true) and o.text:find("Næste mål: 50", 1, true), "hvem og næste mål: " .. o.text)
check(printed("Gruppe-milepæl!"), "en linje i chatten")
msgs = sentWith("XM;Mathias;dead;25;")
check(#msgs == 1 and split(msgs[1])[6] == "Jeppe" and split(msgs[1])[7] == "", "XM sendt med udløser: " .. tostring(msgs[1]))
check(M.Check() == 0 and goalToasts() == 1, "kun én gang")

-- Fra en ven: lvl:250 er nået (frisk) -> fest. Samme besked igen -> ingen ny fest
xm("Nick", "lvl", 250, NOW - 60, "Nick")
check(hit["lvl:250"] and hit["lvl:250"].by == "Nick", "lvl:250 fra Nick gemt")
check(goalToasts() == 2, "fest fra vennens besked")
xm("Frode", "lvl", 250, NOW - 30, "Frode")
check(goalToasts() == 2, "samme mål igen giver ingen ny fest")
check(hit["lvl:250"].t == NOW - 60 and hit["lvl:250"].by == "Nick", "senere tid ændrer intet")
xm("Frode", "lvl", 250, NOW - 90, "Frode")
check(hit["lvl:250"].t == NOW - 90 and hit["lvl:250"].by == "Frode", "tidligste tid vinder")
-- Vores egen tjek finder ikke lvl:250 igen
check(M.Check() == 0, "vi fejrer ikke vennens mål to gange")

-- Stille og gamle mål giver ingen fest
xm("Nick", "gold", 500, NOW - 60, "", "1")
check(hit["gold:500"] and hit["gold:500"].s == 1 and goalToasts() == 2, "stille mål: ingen fest")
xm("Nick", "boss", 10, NOW - 3 * 86400, "Nick")
check(hit["boss:10"] and goalToasts() == 2, "mål ældre end 2 døgn: ingen fest")

-- Ødelagte beskeder gemmer intet
local before = 0 for _ in pairs(hit) do before = before + 1 end
xm("Nick", "xyz", 10, NOW)
xm("Nick", "dead", 33, NOW)
xm("Nick", "dead", "abc", NOW)
xm("Nick", "dead", 50, "nu")
xm("Nick", "dead", 50, 5)
xm("Mathias", "dead", 50, NOW)
xm("Fremmed", "dead", 50, NOW)
Fire("CHAT_MSG_ADDON", "WCOAST", "XM;Nick", "GUILD", "Nickchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XM;Nick;dead", "GUILD", "Nickchar")
local after = 0 for _ in pairs(hit) do after = after + 1 end
check(before == after and goalToasts() == 2, "ødelagte beskeder ignoreres")
-- Ukendt udløser og tid i fremtiden
xm("Nick", "dead", 50, NOW + 5000, "Fremmed")
check(hit["dead:50"] and hit["dead:50"].t == NOW and hit["dead:50"].by == nil, "fremtid klippes, ukendt udløser droppes")

-- Flere mål på én gang (fx efter en synk): kun det højeste fejres
toasts = {}
C.UpdateChar("Nick", "Nickalt", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Nick", "Nickalt2", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Jeppe", "Jepalt", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Jeppe", "Jepalt2", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Frode", "Froalt", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
v = M.Values()
check(v.lvl >= 430, "levels: " .. v.lvl)
M.Check()
check(hit["lvl:500"] == nil or v.lvl >= 500, "kun nåede mål")
local lvlToasts = 0
for _, x in ipairs(toasts) do if x.head == "GRUPPE-MILEPÆL" and x.icon == M.BY_ID.lvl.icon then lvlToasts = lvlToasts + 1 end end
check(lvlToasts <= 1, "højst én fest pr. kategori ad gangen")
C.UpdateChar("Frode", "Froalt2", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Frode", "Froalt3", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Søren", "Soralt", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Søren", "Soralt2", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
C.UpdateChar("Søren", "Soralt3", { class = "MAGE", level = C.MAX_LEVEL, gold = 0, zone = "Westfall" }, NOW)
toasts = {}
M.Check()
v = M.Values()
check(v.lvl >= 750 and hit["lvl:500"] and hit["lvl:750"], "500 og 750 nået: " .. v.lvl)
local titles = {}
for _, x in ipairs(toasts) do if x.head == "GRUPPE-MILEPÆL" then titles[#titles+1] = x.title end end
local s = table.concat(titles, " / ")
check(s:find("750 levels", 1, true) and not s:find("500 levels", 1, true), "kun 750 fejres: " .. s)
check(hit["max:3"] and v.max >= 3, "max level-karakterer tælles (" .. v.max .. ")")

-- Slå popuppen fra: kun chat
local slash = SlashCmdList["WASTEDCOAST"]
slash("milepæle fra")
check(db.settings.milestones == false, "/wc4ever milepæle fra")
toasts, PRINTS = {}, {}
xm("Nick", "hours", 24, NOW - 10, "Nick")
check(goalToasts() == 0 and printed("Gruppe-milepæl!"), "slået fra: kun en linje i chatten")
slash("milepæle til")
check(db.settings.milestones == nil, "/wc4ever milepæle til")
toasts = {}
slash("milepæle test")
check(goalToasts() == 1, "/wc4ever milepæle test")
check(not hit["lvl:1000"], "testen gemmer intet")
PRINTS = {}
slash("milepæle")
check(printed("Gruppe-milepæle") and printed("Dødsfald: 25 af 100"), "/wc4ever milepæle viser fremskridt")

-- Synk: fuld sender alle (op til 40), let kun de friske
SENT = {}
M.SendLog(false)
local full = sentWith("XM;Mathias;")
SENT = {}
M.SendLog(true)
local light = sentWith("XM;Mathias;")
check(#full > #light and #light >= 1, "fuld synk: " .. #full .. ", let: " .. #light)
for _, m in ipairs(light) do check(not m:find(";dead;10;", 1, true), "den lette synk sender ikke gamle mål") end
SENT = {}
ns.SendMyExtras(false)
check(#sentWith("XM;") >= 1, "kobler på synken")

-- Demo: vises, sendes aldrig, skygger ikke for et ægte mål og fjernes igen
db.milestones.hit["dead:50"] = nil
M.MakeDemo()
check(hit["dead:50"] and hit["dead:50"].demo, "demo-mål")
SENT = {}
M.SendLog(false)
for _, m in ipairs(sentWith("XM;")) do check(not m:find(";dead;50;", 1, true), "demo sendes aldrig") end
for i = 26, 50 do table.insert(db.events, { id = "more-" .. i, name = "Nickchar", friend = "Nick", class = "MAGE", time = NOW - 50 + i }) end
toasts = {}
M.Check()
check(hit["dead:50"] and not hit["dead:50"].demo and goalToasts() == 1, "ægte mål erstatter demo")
M.MakeDemo()
M.ClearDemo()
for _, h in pairs(hit) do check(not h.demo, "demo fjernet") end

-- Demo-dødsfald tæller ikke
local n0 = M.Values().dead
table.insert(db.events, { id = "demo-x-1", name = "Nickchar", friend = "Nick", time = NOW })
check(M.Values().dead == n0, "demo-dødsfald tæller ikke")

-- Bande-baren og nyhederne
local items = ns.Bar.Items(NOW, 50, 30 * 86400)
local found, stille = false, false
for _, it in ipairs(items) do
    if it.kind == "goal" then found = true end
    if it.key == "mgold:500" then stille = true end
end
check(found, "milepæle står i nyhederne")
check(not stille, "stille mål står ikke i nyhederne")

-- Siden: Sjov > Milepæle
ns.frame:Show()
ns.ShowTab(19)
if ns.RefreshUI then ns.RefreshUI() end
check(M.ui.rows and #M.ui.rows == #M.CATS, "en række pr. kategori")
check(M.ui.sub:GetText():find("nået", 1, true), "overskriften viser fremskridt")
check(M.ui.recent:GetText():find("Dødsfald: 50", 1, true), "seneste fester")
TT = {}
M.ui.rows[3].scripts.OnEnter(M.ui.rows[3])
local tt = table.concat(TT, "\n")
check(tt:find("Dødsfald", 1, true) and tt:find("ikke nået", 1, true), "tooltip med alle mål")
check(M.Num(25000) == "25.000" and M.Num(999) == "999" and M.Num(1000000) == "1.000.000", "tusindtal")

-- Nulstil
M.Reset()
check(db.milestones == nil, "nulstil")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
