# Test af avisen (Avis.lua): øjebliksbilledet ved dagens start, de fire rubrikker (dødsfald, loot,
# levels, bedrifter) med klokkeslæt og nyeste først, forsiden og vægtene, tallene, der passer med
# rubrikkerne, level-løbet på én linje, demo og gamle data, vinduet ved login (ikke ved /reload eller
# zone-skift) og dets højde, tomme rubrikker, sladderen, der viger, kommandoer, Discord-teksten,
# siden og en ny dag.
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
C.UpdateChar("Mathias", "Mathchar", { class = "WARLOCK", level = 29, gold = 0, zone = "Duskwood" }, NOW - 86400)
C.UpdateChar("Frode", "Frochar", { class = "DRUID", level = 30, gold = 0, zone = "Westfall" }, NOW - 86400)
C.UpdateChar("Nick", "Nickchar", { class = "HUNTER", level = 20, gold = 0, zone = "Redridge" }, NOW - 86400)
C.UpdateChar("Jeppe", "Jepchar", { class = "MAGE", level = 19, gold = 0, zone = "Loch Modan" }, NOW - 86400)
C.UpdateChar("Søren", "Sorchar", { class = "ROGUE", level = 19, gold = 0, zone = "Westfall" }, NOW - 86400)
-- En gammel død (i går) må ikke tælle
table.insert(db.events, { id = "old-1", name = "Nickchar", friend = "Nick", class = "HUNTER", killer = "Hogger", klvl = 11, level = 20, zone = "Elwynn Forest", time = since - 3600 })
-- Instanser ved dagens start (sladderens målinger)
local realStats = ns.GossipStats
local PM = C.MAX_LEVEL >= 70 and 375 or 300
local runs = { Nick = { runs = { Gnomeregan = { c = 0, w = 0, b = 0 } }, rep = { Stormwind = 6 }, prof = { Mining = PM - 10 } } }
ns.GossipStats = function() return runs end
A.EnsureDay()
local a = db.avis
check(a.day == date("%Y-%m-%d", NOW), "øjebliksbilledet er fra i dag")
check(math.floor(a.base.lv.Frode) == 30 and math.floor(a.base.lv.Mathias) == 29, "levels ved dagens start er gemt")
check(a.n == 1, "avis nummer 1")
check(a.hist[a.day] and a.hist[a.day].lv.Frode, "historikken har dagens start")
check(a.base.st.Nick.runs.Gnomeregan.c == 0, "instanserne ved dagens start er gemt")

-- Ingenting sket endnu: reserveforside, alle rubrikker tomme
local P = A.Collect()
check(P.count == 0 and P.lead.h == "Stille dag i Wasted Coast", "stille dag: reserveforsiden")
for _, k in ipairs(A.SECTIONS) do check(#P.sec[k] == 0, "tom rubrik: " .. k) end
check(P.hat == nil and P.horo == nil and P.ads == nil and P.weather == nil, "ingen hat, horoskop, annoncer eller vejr")

-- I dag: Frode dør tre gange (én til en mob, ét fald), Jeppe drukner, Nick får epic, rare og 3 levels,
-- Mathias får et level, Nick rydder Gnomeregan og bliver Exalted, Søren fælder en rare mob
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
-- En helt almindelig død (en mob på samme level) skal også med: det var fejlen i v0.31
death("d5", "Søren", "Sorchar", "Mottled Raptor", 19, 19, "Wetlands", since + 9700, { class = "ROGUE" })
death("demo-1", "Søren", "Sorchar", "Hogger", 1, 19, "Elwynn Forest", since + 9600, { demo = true })
table.insert(db.loot, { id = "l1", friend = "Nick", char = "Nickchar", item = "item:6448", name = "Tail Spike", quality = 4, zone = "Shadowfang Keep", time = since + 5000, how = "need" })
table.insert(db.loot, { id = "l2", friend = "Nick", char = "Nickchar", item = "item:7", name = "Blue Thing", quality = 3, zone = "Redridge", time = since + 8000 })
table.insert(db.loot, { id = "l3", friend = "Nick", char = "Nickchar", item = "item:8", name = "Grey Junk", quality = 2, zone = "Redridge", time = since + 8000 })
table.insert(db.loot, { id = "demo-l", friend = "Søren", char = "Sorchar", item = "item:1", name = "Fake", quality = 5, zone = "X", time = since + 5000, demo = true })
C.UpdateChar("Nick", "Nickchar", { class = "HUNTER", level = 23, gold = 0, zone = "Redridge" }, NOW)
C.UpdateChar("Mathias", "Mathchar", { class = "WARLOCK", level = 30, gold = 0, zone = "Duskwood" }, NOW)
db.levelAt = db.levelAt or {}
db.levelAt.Mathias = { l = 30, t = since + 6000 }
runs = { Nick = { runs = { Gnomeregan = { c = 1, w = 0, b = 5 } }, rep = { Stormwind = 8 }, prof = { Mining = PM } } }
db.rareLog = db.rareLog or {}
table.insert(db.rareLog, { friend = "Søren", mob = "Mor'Ladim", lvl = 35, zone = "Duskwood", t = since + 4000 })
table.insert(db.rareLog, { friend = "Søren", mob = "Fake", t = since + 4000, demo = true })

P = A.Collect()
local function rows(sec) return P.sec[sec] end
local function has(sec, s) for _, e in ipairs(P.sec[sec]) do if e.t:find(s, 1, true) then return e end end end
-- Dødsfald: alle fem, nyeste først, og tallet passer med rubrikken
check(#rows("dod") == 5, "alle dagens dødsfald uden demo og gamle: " .. #rows("dod"))
check(P.stats.dod == #rows("dod"), "tallet over dødsfald passer med rubrikken")
check(rows("dod")[1].t:find("Søren", 1, true) and rows("dod")[1].at == since + 9700, "nyeste dødsfald først")
check(has("dod", "Søren døde til Mottled Raptor (19) i Wetlands."), "almindelig død står der: " .. rows("dod")[1].t)
check(has("dod", "Frode døde af faldskade i Westfall."), "faldet")
check(has("dod", "Jeppe døde af drukning i Loch Modan."), "druknet")
for i = 2, #rows("dod") do check(rows("dod")[i - 1].at >= rows("dod")[i].at, "dødsfald sorteret efter tid") end
-- Loot: epic før rare, ikke grå og ikke demo
check(#rows("loot") == 2 and P.stats.loot == 2, "loot: epic og rare, ikke grå og demo")
check(rows("loot")[1].t:find("Tail Spike", 1, true) and rows("loot")[2].t:find("Blue Thing", 1, true), "epic står før rare")
check(rows("loot")[1].t:find("Shadowfang Keep", 1, true), "loot har zonen")
-- Levels: Mathias med klokkeslæt, Nick uden (levelAt kendes ikke), samlet 4 levels
check(#rows("lvl") == 2 and P.stats.lvl == 4, "levels: to venner, fire levels i alt")
check(rows("lvl")[1].t == "Mathias nåede level 30." and rows("lvl")[1].at == since + 6000, "Mathias med klokkeslæt først")
check(rows("lvl")[2].t == "Nick gik fra level 20 til 23.", "Nick tog tre levels: " .. rows("lvl")[2].t)
-- Bedrifter
check(has("bed", "Nick ryddede Gnomeregan (5 bosser)."), "instans ryddet med bosser")
check(has("bed", "Nick er nu Exalted med Stormwind."), "Exalted")
check(has("bed", "Nick maxede Mining (" .. PM .. ")."), "maxet profession")
check(has("bed", "Søren nedlagde Mor'Ladim i Duskwood."), "rare mob")
check(not has("bed", "Fake"), "demo rare mob tæller ikke")
check(P.stats.bed == #rows("bed"), "tallet over bedrifter passer")
check(P.count == 5 + 2 + 2 + #rows("bed"), "antal begivenheder")
-- Forsiden: den tungeste (første epic, 74) slår tre levels (73) og Gnomeregan (65)
check(P.lead.h == "Første epic til Nick", "forsiden er Nicks første epic: " .. tostring(P.lead.h))
check(P.lead.t:find("Tail Spike", 1, true), "forsidens tekst")
-- Level-løbet på én linje
check(P.race[1].f == "Frode" and P.race[2].f == "Mathias" and P.race[2].gain == 1, "kapløbet")
local line = A.Plain(A.RaceLine(P, true))
check(line:find("1. Frode 30", 1, true) and line:find("2. Mathias 30 (+1)", 1, true) and line:find("Nick 23 (+3)", 1, true), "level-løbet: " .. line)
-- Det samme hele dagen
local P2 = A.Collect()
check(P2.lead.t == P.lead.t and P2.sec.dod[1].t == P.sec.dod[1].t, "samme tekster ved samme dato")

-- En legendary slår alt, og 3 dødsfald til samme ven kan blive forsiden
table.insert(db.loot, { id = "l4", friend = "Jeppe", char = "Jepchar", item = "item:9", name = "Thunderfury", quality = 5, zone = "Molten Core", time = since + 9900 })
P = A.Collect()
check(P.lead.h == "Legendarisk til Jeppe" and P.sec.loot[1].t:find("Thunderfury", 1, true), "legendary er forsiden og står øverst")
table.remove(db.loot)

-- Discord-teksten er ren tekst
P = A.Collect()
local plain = A.PlainText(P)
check(plain:find("Wasted Coast Tidende", 1, true) and plain:find("Første epic til Nick", 1, true), "Discord-teksten har forsiden")
check(plain:find("__Dødsfald__ (5)", 1, true) and plain:find("Søren døde til Mottled Raptor", 1, true), "Discord-teksten har dødsfaldene")
check(plain:find("__Stillingen i level-løbet__", 1, true), "Discord-teksten har level-løbet")
check(not plain:find("|c", 1, true) and not plain:find("|H", 1, true), "ingen farvekoder i Discord-teksten")
check(not plain:find("Horoskop", 1, true) and not plain:find("Skammens hat", 1, true), "ingen horoskop eller hat")

-- Ødelagte data crasher ikke
table.insert(db.events, { id = "bad1" })
table.insert(db.events, { id = "bad2", friend = "Nick", time = since + 100, level = "x", killer = 5 })
table.insert(db.loot, { id = "bad3", friend = "Nick", time = since + 100 })
table.insert(db.loot, { id = "bad3b", friend = "Nick", time = since + 200, quality = "y" })
table.insert(db.rareLog, { friend = "Nick", t = since + 1 })
local ok, err = pcall(A.Collect)
check(ok, "ødelagte data: " .. tostring(err))
P = A.Collect()
check(P.stats.dod == #P.sec.dod, "dødsfald og tal passer stadig")

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
check(A.ui.statN[1].text_ == tostring(P.stats.dod), "dødsfald-tallet i vinduet")
check(A.ui.box.dod.title.text_ == "Dødsfald" and A.ui.box.dod.count.text_ == tostring(#P.sec.dod), "rubrikkens titel og antal")
check(A.ui.box.dod.rows[1].c.text_ ~= "" and A.ui.box.dod.rows[1].t.text_ == P.sec.dod[1].t, "første linje med klokkeslæt")
check(A.ui.box.dod.rows[4].t.text_:find("og 3 mere", 1, true), "højst 4 linjer: " .. tostring(A.ui.box.dod.rows[4].t.text_))
check(A.ui.race.text_ and A.Plain(A.ui.race.text_):find("1. Frode 30", 1, true), "level-løbet i vinduet")
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

-- En ny dag: nyt øjebliksbillede, gårsdagens dødsfald tæller ikke, nummeret stiger
NOW = NOW + 86400
A.Track()
check(db.avis.day == date("%Y-%m-%d", NOW) and db.avis.n == 2, "ny dag, nyt nummer")
local nh = 0 for _ in pairs(db.avis.hist) do nh = nh + 1 end
check(nh == 2, "historikken har to dage")
P = A.Collect()
check(P.stats.dod == 0 and P.lead.h == "Stille dag i Wasted Coast", "en ny dag starter stille")
-- En stille dag: alle fire rubrikker står der stadig med en grå linje, og avisen holder sin størrelse
slash("avis")
local quietH = A.ui.height
for _, k in ipairs(A.SECTIONS) do check(A.ui.box[k].shown and A.ui.box[k].count.text_ == "0", "tom rubrik vises: " .. k) end
check(A.ui.box.dod.title.text_ == "Dødsfald" and A.ui.box.dod.rows[1].t.text_ == "Ingen dødsfald i dag.", "tom rubrik har en kort linje")
check(A.ui.race.shown ~= false, "level-løbet vises stadig")
check(quietH >= 560, "avisen er ikke lille på en stille dag: " .. tostring(quietH))
-- Kun ét level: alle rubrikker vises, Levels har linjen, og forsiden gentager ikke bare overskriften
C.UpdateChar("Jeppe", "Jepchar", { class = "MAGE", level = 20, gold = 0, zone = "Loch Modan" }, NOW)
slash("avis")
check(A.ui.box.lvl.shown and A.ui.box.dod.shown and A.ui.box.lvl.rows[1].t.text_ == "Jeppe nåede level 20.", "Levels har linjen")
check(A.ui.head.text_ == "Jeppe nåede level 20" and A.ui.body.text_:find("nummer", 1, true) and not A.ui.body.text_:find("nåede level", 1, true), "forsidens tekst: " .. tostring(A.ui.body.text_))
check(A.ui.height == quietH, "samme størrelse med én linje")
ns.GossipStats = realStats
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
