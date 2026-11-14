# Test af bande-baren (Bar.lua): ikoner, XP-ring, tooltip, live-ticker, flytning og indstillinger.
# Kør: pip install lupa && python3 tests/test_bar.py WastedCoast [forever]
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
# Tooltippen og flytning skal kunne ses i testen
lua.execute('''
TT = {}
GameTooltip.AddLine = function(_, s) TT[#TT+1] = s end
GameTooltip.AddDoubleLine = function(_, a, b) TT[#TT+1] = a .. " | " .. tostring(b) end
MOVES = 0
''')
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function hb(friend, char, class, level, zone, xp)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "H", friend, char, class, level, 100, zone, xp or 0, "", "1" }, ";"), "GUILD", char)
end
local function ttHas(s) for _, l in ipairs(TT) do if tostring(l):find(s, 1, true) then return true end end end
local function lastPrint() return PRINTS[#PRINTS] or "" end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
STARTED_LONG_AGO = true
CLOCK = CLOCK + 1000

local bar, Bar = ns.barFrame, ns.Bar
check(bar ~= nil and Bar ~= nil, "baren bygges ved login")
Bar.Tick()   -- første tik efter login: vennelisten er nu kendt
check(bar.shown == true and db.settings.bar == nil, "baren er slået til som standard")
check(#bar.icons == #ns.core.ROSTER and #bar.icons == 8, "et ikon pr. ven (8)")

-- -----------------------------------------------------------------------------
-- Ikoner: online/offline, level og XP-ring
-- -----------------------------------------------------------------------------
hb("Nick", "Nickchar", "MAGE", 34, "Duskwood", 50)
db.friends.Jeppe = { chars = { Jepchar = { class = "ROGUE", level = 20, xp = 10, zone = "Westfall", seen = NOW - 7200 } } }
db.chars.Jepchar = "Jeppe"
Bar.Refresh()
local function icon(friend) for _, b in ipairs(bar.icons) do if b.friend == friend then return b end end end
local nick, jep, me = icon("Nick"), icon("Jeppe"), icon("Mathias")
check(nick and jep and me, "ikonerne hører til de rigtige venner")
check(nick.online == true and nick.dot.shown == true, "en ven med et frisk livstegn lyser og har en grøn prik")
check(jep.online == false and jep.dot.shown == false, "en ven, der ikke er set i 2 timer, er slukket")
check(nick.level.text_ == "34" and jep.level.text_ == "20", "level står på ikonet")
check(me.online == true, "du selv er altid online")

local p, max = Bar.RingValue(34, 50)
check(math.abs(p - 0.5) < 0.001 and not max, "XP-ringen er halvt fyldt ved 50% XP")
p, max = Bar.RingValue(ns.core.MAX_LEVEL, nil)
check(p == 1 and max == true, "fuld guld ring på max level")
check(Bar.RingValue(0, nil) == 0, "tom ring, når level ikke kendes")
check(nick.ring.fill[1].shown and nick.ring.fill[2].shown and not nick.ring.fill[3].shown and not nick.ring.fill[4].shown,
      "50% XP fylder de to første kanter af ringen")
check(jep.ring.fill[1].shown and not jep.ring.fill[2].shown, "10% XP fylder kun et stykke af den første kant")

-- -----------------------------------------------------------------------------
-- Tooltip: zone og hvad vennen laver
-- -----------------------------------------------------------------------------
TT = {}
nick.scripts.OnEnter(nick)
check(ttHas("Duskwood") and ttHas("Nickchar") and ttHas("Online"), "tooltippen viser karakter, zone og online")
check(ttHas("Intet farligt"), "uden nyt: vennen er bare ude i verden")
-- Nick går i en dungeon og dør
hb("Nick", "Nickchar", "MAGE", 34, "The Deadmines", 50)
Fire("CHAT_MSG_ADDON", "WCOAST", "D;bar-1;Nickchar;MAGE;Defias Pillager;Nærkamp;34;The Deadmines;" .. (NOW - 60) .. ";Nick;20", "GUILD", "Nickchar")
RunTimers()
Bar.Refresh()
nick = icon("Nick")
TT = {}
nick.scripts.OnEnter(nick)
check(ttHas("I en dungeon") and ttHas("Døde til Defias Pillager"), "tooltippen: i en dungeon og døde for nylig")
check(ttHas("Døde i dag | |cffff60601|r"), "dagens dødsfald tælles")
TT = {}
jep.scripts.OnEnter(jep)
check(ttHas("Offline") and ttHas("Sidst set") and ttHas("Westfall"), "offline: sidst set og hvor")

-- Klik åbner vennens karakterer
ns.frame:Hide()
nick.scripts.OnClick(nick, "LeftButton")
check(ns.frame.shown and ns.target == "Nick" and ns.tab == 3, "klik på ikonet åbner vennens karakterer")

-- -----------------------------------------------------------------------------
-- Live-ticker
-- -----------------------------------------------------------------------------
db.levelAt.Nick = { l = 34, t = NOW - 30 }
db.levelAt.Frode = { l = 12, t = NOW - 40, g = true }      -- gæt: vises ikke
db.levelAt["Søren"] = { l = 10, t = NOW - 90000 }             -- over et døgn gammel
table.insert(db.loot, { id = "bar-l1", char = "Nickchar", class = "MAGE", item = "item:1:0", name = "Big Sword", quality = 4, time = NOW - 120 })
db.ach.Jeppe = { first_death = NOW - 200 }
db.rareLog = { { friend = "Mikkel", mob = "Rak'shiri", lvl = 64, cls = "rareelite", zone = "Nagrand", t = NOW - 300 } }
db.duels = {
    Mathias = { { id = "du1", char = "Mathiasx", opp = "Nickchar", of = "Nick", won = true, t = NOW - 400 } },
    Nick = { { id = "du1", char = "Nickchar", opp = "Mathiasx", of = "Mathias", won = false, t = NOW - 400 } },
}
table.insert(db.events, { id = "bar-2", name = "Jepchar", friend = "Jeppe", class = "ROGUE", killer = "Chicken", klvl = 1, level = 20, time = NOW - 500 })
local items = Bar.Items()
local keys, texts = {}, {}
for i, it in ipairs(items) do keys[i] = it.key texts[i] = it.text end
local all = table.concat(texts, "\n")
check(items[1].key == "lNick34" and texts[1]:find("dingede 34"), "nyeste først: Nick dingede 34")
check(all:find("Defias Pillager") and all:find("fik ") and all:find("Big Sword"), "dødsfald og loot er med")
check(all:find("Første blod") and all:find("Rak'shiri") and all:find("vandt en duel mod"), "trofæer, rare mobs og dueller er med")
check(all:find("level 1 Chicken. Pinligt."), "dødsfald til en mob langt under ens level er pinligt")
local nd = 0
for _, t in ipairs(texts) do if t:find("duel") then nd = nd + 1 end end
check(nd == 1, "samme duel vises kun én gang")
check(not all:find("dingede 12") and not all:find("dingede 10"), "gættede og gamle levels er ikke med")
for i = 2, #items do check(items[i - 1].t >= items[i].t, "sorteret efter tid") end

-- Ny begivenhed: tickeren starter forfra med det samme
Bar.UpdateTicker(true)
rawset(bar.tick, "GetStringWidth", function() return 2000 end)
bar.clipW = 300
bar.scripts.OnUpdate(bar, 1)
check(bar.offset > 0, "tickeren ruller")
local before = bar.tick.text_
db.levelAt.Rasmus = { l = 41, t = NOW }
db.friends.Rasmus = { chars = { Raschar = { class = "WARRIOR", level = 41, seen = NOW } } }
Bar.UpdateTicker(false)
check(bar.offset == 0 and bar.tick.text_ ~= before and bar.tick.text_:find("dingede 41"), "nyt øverst: starter forfra")
-- Uden nyt venter en ny tekst, til runden er færdig
bar.scripts.OnUpdate(bar, 2)
local mid = bar.offset
bar.pending = "ny tekst"
bar.scripts.OnUpdate(bar, 1)
check(bar.tick.text_ ~= "ny tekst" and bar.offset > mid, "teksten skifter ikke midt i en runde")
bar.scripts.OnUpdate(bar, 100)
check(bar.tick.text_ == "ny tekst" and bar.offset == 0, "ny tekst, når runden er færdig")

-- Ingen nyheder
local saved = { db.events, db.loot, db.levelAt, db.ach, db.rareLog, db.duels }
db.events, db.loot, db.levelAt, db.ach, db.rareLog, db.duels = {}, {}, {}, {}, {}, {}
local t, newest = Bar.TickerText(Bar.Items())
check(t:find("Stille på kysten") and newest == "", "stille dag: en pladsholder")
db.events, db.loot, db.levelAt, db.ach, db.rareLog, db.duels = unpack(saved)

-- -----------------------------------------------------------------------------
-- Flyt, lås, gem position
-- -----------------------------------------------------------------------------
rawset(bar, "StartMoving", function() MOVES = MOVES + 1 end)
rawset(bar, "GetPoint", function() return "TOPLEFT", UIParent, "TOPLEFT", 120.4, -80.6 end)
bar.scripts.OnDragStart(bar)
bar.scripts.OnDragStop(bar)
check(MOVES == 1, "baren kan trækkes")
local pos = db.settings.barPos
check(pos and pos[1] == "TOPLEFT" and pos[3] == 120 and pos[4] == -81, "positionen gemmes")
local slash = SlashCmdList["WASTEDCOAST"]
slash("bar lås")
check(db.settings.barLocked == true and lastPrint():find("låst"), "/wc4ever bar lås låser")
bar.scripts.OnDragStart(bar)
nick.scripts.OnDragStart(nick)
check(MOVES == 1, "en låst bar kan ikke flyttes, heller ikke fra et ikon")
slash("bar lås")
check(not db.settings.barLocked, "og låses op igen")
nick.scripts.OnDragStart(nick)
nick.scripts.OnDragStop(nick)
check(MOVES == 2, "træk i et ikon flytter baren")

slash("bar ticker")
check(db.settings.barTicker == false and bar.clip.shown == false, "tickeren kan slås fra")
slash("bar ticker")
check(db.settings.barTicker == true and bar.clip.shown == true, "og til igen")
slash("bar")
check(db.settings.bar == false and bar.shown == false, "/wc4ever bar skjuler baren")
slash("bar")
check(db.settings.bar == true and bar.shown == true, "og viser den igen")
slash("bar nulstil")
check(db.settings.barPos == nil and bar.shown, "bar nulstil flytter den tilbage")

-- Indstillinger: tre nye afkrydsninger (bar, lås, ticker)
local opts = ns.options
local found = {}
for _, cb in ipairs(opts.checks) do found[cb.label.text_] = cb end
check(found["Bande-bar"] and found["Lås"] and found["Ticker"], "indstillingerne har bar, lås og ticker")
rawset(found["Bande-bar"], "GetChecked", function() return false end)
found["Bande-bar"].scripts.OnClick(found["Bande-bar"])
check(db.settings.bar == false and not bar.shown, "afkrydsningen skjuler baren")
rawset(found["Bande-bar"], "GetChecked", function() return true end)
found["Bande-bar"].scripts.OnClick(found["Bande-bar"])
check(bar.shown, "og viser den igen")

-- Opdatering: nye data markerer baren, og tikket opdaterer højst én gang i sekundet
hb("Andreas", "Andchar", "PRIEST", 8, "Elwynn Forest", 70)
Bar.Tick()
check(icon("Andreas").online and icon("Andreas").level.text_ == "8", "et nyt livstegn kommer på baren ved næste tik")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
