# Test af avisen (Avis.lua): øjebliksbilledet ved dagens start, historierne og deres betingelser,
# forsiden og vægtene, højst 3 historier pr. ven, kapløbet, Skammens hat, horoskop, annoncer,
# demo og gamle data, vinduet ved login (ikke ved /reload eller zone-skift), sladderen, der viger,
# kommandoer, Discord-teksten, siden og en ny dag.
# Kør: pip install lupa && python3 tests/test_avis.py WastedCoast [forever]
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
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function printed(s) for _, p in ipairs(PRINTS) do if p:find(s, 1, true) then return true end end end
local A = ns.Avis
check(A ~= nil and ns.AvisSlash ~= nil and ns.ShowAvis ~= nil, "Avis.lua er indlæst")
local C = ns.core
local slash = SlashCmdList["WASTEDCOAST"]

-- Midt på dagen, så "i dag" har plads både før og efter
local mid = A.Midnight(NOW)
NOW = mid + 14 * 3600
local since = A.Midnight(NOW)

-- Din egen karakter er lav, så den ikke blander sig i kapløbet
UnitLevel = function(u) if u == "target" then return TARGET_LEVEL end return 5 end
Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
check(db.avis.day == date("%Y-%m-%d", NOW) and db.avis.n == 1, "øjebliksbilledet tages lidt efter login")
-- Øjebliksbilledet tages igen med bandens data (som om det var dagens første login)
db.avis.day, db.avis.n = nil, 0
-- Bandens stilling før i dag
C.UpdateChar("Mathias", "Mathchar", { class = "WARLOCK", level = 29, gold = 0, zone = "Duskwood" }, NOW - 86400)
C.UpdateChar("Frode", "Frochar", { class = "DRUID", level = 30, gold = 0, zone = "Westfall" }, NOW - 86400)
C.UpdateChar("Nick", "Nickchar", { class = "HUNTER", level = 20, gold = 0, zone = "Redridge" }, NOW - 86400)
C.UpdateChar("Jeppe", "Jepchar", { class = "MAGE", level = 19, gold = 0, zone = "Loch Modan" }, NOW - 86400)
C.UpdateChar("Søren", "Sorchar", { class = "ROGUE", level = 19, gold = 0, zone = "Westfall" }, NOW - 86400)
-- En gammel død (i går) og en død i et demo-dødsfald må ikke tælle
table.insert(db.events, { id = "old-1", name = "Nickchar", friend = "Nick", class = "HUNTER", killer = "Hogger", klvl = 11, level = 20, zone = "Elwynn Forest", time = since - 3600 })
A.EnsureDay()
local a = db.avis
check(a.day == date("%Y-%m-%d", NOW), "øjebliksbilledet er fra i dag")
check(math.floor(a.base.lv.Frode) == 30 and math.floor(a.base.lv.Mathias) == 29, "levels ved dagens start er gemt")
check(a.n == 1, "avis nummer 1")
check(a.hist[a.day] and a.hist[a.day].lv.Frode, "historikken har dagens start")

-- Ingenting sket endnu: reserveforside, alle rubrikker tomme
local P = A.Collect()
check(P.count == 0 and P.lead.h == "Stille dag i Wasted Coast", "stille dag: reserveforsiden")
check(P.hat.f == "Nick" and P.hat.text and P.hat.text:find("Nick", 1, true), "Nick bærer hatten fra i går: " .. tostring(P.hat.text))
check(#P.ads == 1 and P.ads[1]:find("lilla hat", 1, true), "kun hat-annoncen")
check(#P.horo == 5, "horoskop til alle med karakterer: " .. #P.horo)
for _, h in ipairs(P.horo) do
    if h.f == "Mathias" then check(h.sign == "Dæmonen", "warlock er Dæmonen") end
    if h.f == "Frode" then check(h.sign == "Bjørnen", "druid er Bjørnen") end
end

-- I dag: Frode dør tre gange (én til en level 12 mob, ét fald), Jeppe drukner, Nick får epic og 3 levels,
-- Mathias overhaler Frode, Jeppe får stomi, prutter over Frode, Need-politiet tager Søren
local function death(id, friend, char, killer, klvl, level, zone, t, extra)
    local ev = { id = id, name = char, friend = friend, class = "DRUID", killer = killer, klvl = klvl, level = level, zone = zone, time = t }
    for k, v in pairs(extra or {}) do ev[k] = v end
    table.insert(db.events, ev)
    return ev
end
death("d1", "Frode", "Frochar", "Defias Trapper", 12, 30, "Westfall", since + 3600)
death("d2", "Frode", "Frochar", C.ENV_NAMES.Falling, 0, 30, "Westfall", since + 7200)
death("d3", "Frode", "Frochar", "Defias Trapper", 14, 30, "Westfall", since + 9000)
death("d4", "Jeppe", "Jepchar", C.ENV_NAMES.Drowning, 0, 19, "Loch Modan", since + 9500)
death("demo-1", "Søren", "Sorchar", "Hogger", 1, 19, "Elwynn Forest", since + 9600, { demo = true })
table.insert(db.loot, { id = "l1", friend = "Nick", char = "Nickchar", item = "item:6448", name = "Tail Spike", quality = 4, zone = "Shadowfang Keep", time = since + 5000, how = "need" })
table.insert(db.loot, { id = "demo-l", friend = "Søren", char = "Sorchar", item = "item:1", name = "Fake", quality = 5, zone = "X", time = since + 5000, demo = true })
C.UpdateChar("Nick", "Nickchar", { class = "HUNTER", level = 23, gold = 0, zone = "Redridge" }, NOW)
C.UpdateChar("Mathias", "Mathchar", { class = "WARLOCK", level = 31, gold = 0, zone = "Duskwood" }, NOW)
db.stomi = db.stomi or {}
db.stomi.log = db.stomi.log or {}
table.insert(db.stomi.log, { id = "s1", from = "Mathias", to = "Jeppe", r = "y", t = since + 4000 })
table.insert(db.stomi.log, { id = "s0", from = "Mathias", to = "Jeppe", r = "y", t = since - 2 * 86400 })
db.haan = db.haan or {}
db.haan.log = db.haan.log or {}
for i, who in ipairs({ "Mathias", "Nick", "Jeppe" }) do
    table.insert(db.haan.log, { id = "h" .. i, from = who, to = "Frode", death = "d1", t = since + 3700 })
end
table.insert(db.needShame, { friend = "Søren", item = "item:5", name = "Commander's Crest", quality = 3, why = "gone", time = since + 6000 })

P = A.Collect()
local function find(h) for _, s in ipairs(P.stories) do if s.h == h then return s end end end
local function inSec(sec, h) for _, s in ipairs(P.sec[sec]) do if s.h == h then return true end end end
check(P.stats.deaths == 4, "dagens dødsfald uden demo og gamle: " .. P.stats.deaths)
check(P.lead.h == "Skandale i Westfall", "den pinligste død er forsiden: " .. tostring(P.lead.h))
check(P.lead.t:find("level 30", 1, true) and P.lead.t:find("level 12", 1, true), "forsiden har levels: " .. P.lead.t)
check(find("Tyngdekraften slår til"), "faldet er en historie")
check(find("Drama i dybet"), "druknet er en historie")
check(find("Frode døde 3 gange"), "tre dødsfald samme dag")
check(find("Første epic til Nick") or find("Nick i lilla"), "epic loot")
check(find("Nick pløjede sig gennem 3 levels"), "tre levels i dag")
check(find("Ny fører i kapløbet"), "Mathias har overhalet Frode")
check(find("Jeppe sagde ja igen"), "anden stomi på en uge")
check(find("Kollektiv prut over Frode"), "tre venner pruttede af samme dødsfald")
check(find("Need-politiet anholder Søren"), "Need-politiet")
check(not find("Legendarisk!"), "demo-loot tæller ikke")
-- Højst 3 historier om Frode, så længe der er andet
local frode = 0
local shown = { P.lead }
for _, k in ipairs(A.SECTIONS) do for _, s in ipairs(P.sec[k]) do shown[#shown + 1] = s end end
local firstRest
for i, s in ipairs(shown) do if s.f == "Frode" then frode = frode + 1 end end
check(frode >= 3, "Frode er med")
local per = {}
local over = false
for _, s in ipairs(P.stories) do if s.f then per[s.f] = (per[s.f] or 0) + 1 end end
check(per.Frode > 3, "Frode har flere end 3 historier i alt")
-- De første 3 af Frodes historier står foran andres lavere historier
local function rank(h) for i, s in ipairs(shown) do if s.h == h then return i end end return 99 end
check(rank("Jeppe sagde ja igen") < 99, "andre venner kommer også med")
-- Kapløbet
check(P.race[1].f == "Mathias" and P.race[1].gain == 2, "Mathias fører med +2 i dag")
check(P.race[2].f == "Frode" and P.race[2].gain == 0, "Frode er nummer 2")
-- Hatten: Jeppe døde sidst
check(P.hat.f == "Jeppe", "Jeppe bærer hatten: " .. tostring(P.hat.f))
check(P.hat.text and P.hat.text:find("Frode", 1, true), "hatten kom fra Frode: " .. tostring(P.hat.text))
-- Horoskop og annoncer følger dagens historier
for _, h in ipairs(P.horo) do
    if h.f == "Jeppe" then check(A.HORO.hat[1] == h.t or A.HORO.hat[2] == h.t or A.HORO.hat[3] == h.t, "Jeppe har hatten i horoskopet") end
    if h.f == "Frode" then check(h.t:find("Westfall", 1, true), "Frode skal undgå Westfall: " .. h.t) end
end
local stomiAd, sundAd = false, false
for _, ad in ipairs(P.ads) do
    if ad:find("stomipose", 1, true) and ad:find("Jeppe", 1, true) then stomiAd = true end
    if ad:find("sund fornuft", 1, true) and ad:find("Frode", 1, true) then sundAd = true end
end
check(stomiAd and sundAd, "annoncerne bygger på dagens data")
check(P.weather:find("Westfall", 1, true) and P.weather:find("Defias Trapper", 1, true), "vejret: " .. P.weather)
-- Det samme hele dagen: teksterne vælges ud fra datoen, ikke tilfældigt
local P2 = A.Collect()
check(P2.lead.t == P.lead.t and P2.horo[1].t == P.horo[1].t, "samme tekster ved samme dato")

-- Discord-teksten er ren tekst
local plain = A.PlainText(P)
check(plain:find("Wasted Coast Tidende", 1, true) and plain:find("Skandale i Westfall", 1, true), "Discord-teksten har forsiden")
check(not plain:find("|c", 1, true) and not plain:find("|H", 1, true), "ingen farvekoder i Discord-teksten")

-- Ødelagte data crasher ikke
table.insert(db.events, { id = "bad1" })
table.insert(db.events, { id = "bad2", friend = "Nick", time = since + 100, level = "x" })
table.insert(db.loot, { id = "bad3", friend = "Nick", time = since + 100 })
table.insert(db.stomi.log, { id = "bad4", t = since + 1 })
table.insert(db.haan.log, { id = "bad5", from = "Nick", to = "Frode", t = since + 1 })
local ok, err = pcall(A.Collect)
check(ok, "ødelagte data: " .. tostring(err))

-- Vinduet: ikke ved zone-skift eller /reload, kun ved et rigtigt login
TIMERS = {}
Fire("PLAYER_ENTERING_WORLD", false, false)
check(#TIMERS == 0, "intet ved zone-skift")
Fire("PLAYER_ENTERING_WORLD", false, true)
check(#TIMERS == 0, "intet ved /reload")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(#TIMERS == 1, "login sætter avisen i gang")
RunTimers()
check(A.ui.frame and A.ui.frame.shown, "avisen åbner ved login")
check(A.ui.head.text_ == P.lead.h, "forsidens overskrift står i vinduet")
check(A.ui.mast.text_ == "Wasted Coast Tidende", "avisens navn")
check(not (_G.WastedCoastGossip and _G.WastedCoastGossip.shown), "sladderen popper ikke op, når avisen er slået til")
Fire("PLAYER_ENTERING_WORLD", true, false)
check(#TIMERS == 0, "kun én avis pr. login")

-- Kommandoer
A.ui.frame.shown = false
slash("avis")
check(A.ui.frame.shown, "/wc4ever avis viser avisen")
slash("avis fra")
check(db.settings.avis == false and printed("Avisen ved login: fra"), "avis fra")
slash("avis til")
check(db.settings.avis == nil and printed("Avisen ved login: til"), "avis til")
slash("avis discord")
check(A.lastPlain and A.ui.copy and A.ui.copy.shown, "avis discord viser kopi-boksen")
A.ShowCopy()
check(A.ui.copyEdit.text_ == A.lastPlain, "kopi-boksen har teksten")

-- Siden Sjov > Avisen
ns.frame:Show()
local okPage, errPage = pcall(ns.ShowTab, 20)
check(okPage, "siden kan vises: " .. tostring(errPage))
check(ns.GROUPS[5].pages[1] == 20, "Avisen er første side under Sjov")

-- Ingen gruppe: ingen avis
db.me = nil
PRINTS = {}
A.ui.frame.shown = false
slash("avis")
check(not A.ui.frame.shown and printed("ikke med i en gruppe"), "uden gruppe kommer der ingen avis")
db.me = "Mathias"

-- Kl. 01-05 og arbejdstid noteres, mens man er online
local myZone = A.Friends().Mathias.zone
check(type(myZone) == "string" and myZone ~= "", "din zone kendes")
C.UpdateChar("Nick", "Nickchar", { class = "HUNTER", level = 23, gold = 0, zone = myZone }, NOW)
local realOnline = C.IsOnline
C.IsOnline = function(n) return n == "Mathias" or n == "Nick" end
for i = 1, 31 do A.Track() end
check(db.avis.peak.n == 2, "flest online på én gang")
check(db.avis.duo["Mathias|Nick"] and db.avis.duo["Mathias|Nick"].s >= 1800, "Mathias og Nick i samme zone")
P = A.Collect()
check(find("Set sammen i " .. myZone), "makkerparret er en historie")

-- En ny dag: nyt øjebliksbillede, gårsdagens dødsfald tæller ikke, nummeret stiger
NOW = NOW + 86400
A.Track()
check(db.avis.day == date("%Y-%m-%d", NOW) and db.avis.n == 2, "ny dag, nyt nummer")
local nh = 0 for _ in pairs(db.avis.hist) do nh = nh + 1 end
check(nh == 2, "historikken har to dage")
check(db.avis.duo["Mathias|Nick"].s == 60, "makkerpar starter forfra på en ny dag")
P = A.Collect()
check(P.stats.deaths == 0 and P.lead.h == "Stille dag i Wasted Coast", "en ny dag starter stille")
-- Tempo: efter 4 dage med levels kan førstemandens ankomst til max level regnes ud
NOW = NOW + 4 * 86400
C.UpdateChar("Mathias", "Mathchar", { class = "WARLOCK", level = 39, gold = 0, zone = "Duskwood" }, NOW)
A.Track()
P = A.Collect()
check(P.eta and P.eta.f == "Mathias" and P.eta.d > 0, "tempoet giver en dato for max level")
C.IsOnline = realOnline
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
