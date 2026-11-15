# Test af nyhedspanelet i hovedvinduet (v0.23): de 100 seneste nyheder i højre side, synligt på alle
# faner, scroll, loot-tooltip og shift-klik. Og rettelsen af "[Loot]" i stedet for itemets navn.
# Kør: pip install lupa && python3 tests/test_news.py WastedCoast [forever]
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
# Nyere klienter: roll-sejren har et [Loot]-link (loot-historikken) foran selve itemet
lua.execute('''
LOOT = "Loot"
LOOT_ROLL_YOU_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: You (Need - %d) Won: %s"
LOOT_ROLL_YOU_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: You (Greed - %d) Won: %s"
TT = {}
LINKED = nil
GameTooltip.AddLine = function(_, s) TT[#TT+1] = tostring(s) end
GameTooltip.AddDoubleLine = function(_, a, b) TT[#TT+1] = tostring(a) .. " | " .. tostring(b) end
GameTooltip.SetHyperlink = function(_, l) LINKED = l end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
INSERTED = {}
function ChatEdit_InsertLink(l) INSERTED[#INSERTED+1] = l return true end
''')
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function ttHas(s) for _, l in ipairs(TT) do if tostring(l):find(s, 1, true) then return true end end end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
STARTED_LONG_AGO = true
CLOCK = CLOCK + 1000
wipe(db.events) wipe(db.loot) wipe(db.lootSeen)
db.levelAt, db.ach, db.rareLog, db.duels = {}, {}, {}, {}

-- -----------------------------------------------------------------------------
-- Panelet bygges med hovedvinduet
-- -----------------------------------------------------------------------------
local Bar, panel = ns.Bar, ns.newsPanel
check(ns.frame ~= nil and panel ~= nil, "hovedvinduet har et nyhedspanel")
check(panel.nRows >= 12 and #panel.rows == panel.nRows, "panelet har plads til mange linjer: " .. tostring(panel.nRows))
check(Bar.PANEL_MAX == 100, "op til 100 nyheder")

-- Tomt: en pladsholder og ingen rullebjælke
ns.frame:Show()
ns.RefreshUI()
check(panel.rows[1].shown and panel.rows[1].fs.text_:find("Stille på kysten"), "stille dag: en pladsholder")
check(not panel.rows[2].shown and not panel.thumb.shown, "ingen ekstra linjer eller rullebjælke")

-- -----------------------------------------------------------------------------
-- 130 dødsfald over flere dage: panelet viser de 100 seneste, også dem ældre end et døgn
-- -----------------------------------------------------------------------------
for i = 1, 130 do
    table.insert(db.events, { id = "n-" .. i, name = "Nickchar", friend = "Nick", class = "MAGE",
        killer = "Mob" .. i, time = NOW - i * 1000 })
end
check(#Bar.Items() == 12, "baren har stadig kun de 12 fra det seneste døgn")
local items = Bar.Items(nil, 100, math.huge)
check(#items == 100, "panelet får de 100 seneste: " .. #items)
check(items[1].text:find("Mob1", 1, true) and items[100].text:find("Mob100", 1, true), "nyeste først, ældste sidst")
check(items[100].t < NOW - 86400, "også nyheder ældre end et døgn")

ns.RefreshUI()
check(panel.rows[1].fs.text_:find("Mob1$"), "øverste linje er den nyeste")
check(panel.rows[1].time.text_ == "16m" and not panel.rows[1].fs.text_:find("(16m)", 1, true), "tiden står i sin egen kolonne")
check(panel.rows[1].icon.shown ~= false, "med et ikon for slags nyhed")
check(panel.count.text_ == "100", "antallet står i hjørnet")
check(panel.thumb.shown and panel.track.shown, "rullebjælken vises, når der er mere end der kan ses")

-- Scroll
local wheel = panel.scripts.OnMouseWheel
wheel(panel, -1)
check(panel.offset == 2 and panel.rows[1].fs.text_:find("Mob3$"), "scroll ned to linjer ad gangen")
wheel(panel, 1)
check(panel.offset == 0, "og op igen")
wheel(panel, 5)
check(panel.offset == 0, "kan ikke scrolle over toppen")
for _ = 1, 100 do wheel(panel, -1) end
check(panel.offset == 100 - panel.nRows, "kan ikke scrolle forbi bunden: " .. panel.offset)
local last = panel.rows[panel.nRows]
check(last.shown and last.fs.text_:find("Mob100$"), "nederst står den 100. nyhed")
wheel(panel, 100)

-- PanelLines direkte
local lines, off, maxOff = Bar.PanelLines(items, 95, 10)
check(off == 90 and maxOff == 90 and #lines == 10, "PanelLines retter for stort offset")
lines, off = Bar.PanelLines(items, -4, 10)
check(off == 0 and lines[1].item == items[1], "og negativt")

-- -----------------------------------------------------------------------------
-- Panelet står der på alle faner og opdateres
-- -----------------------------------------------------------------------------
for _, grp in ipairs(ns.GROUPS) do
    for _, pg in ipairs(grp.pages) do
        ns.ShowTab(pg)
        check(panel.shown and panel.rows[1].shown, "panelet er synligt på side " .. pg)
    end
end
db.levelAt.Jeppe = { l = 22, t = NOW }
ns.ShowTab(4)
check(panel.rows[1].fs.text_:find("dingede 22"), "ny nyhed øverst, også på en anden fane")

-- -----------------------------------------------------------------------------
-- Loot: tooltip og shift-klik
-- -----------------------------------------------------------------------------
table.insert(db.loot, { id = "lt-1", friend = "Nick", char = "Nickchar", class = "MAGE", item = "item:777:0",
    name = "Big Sword", quality = 4, how = "need", ctx = "dungeon", zone = "Deadmines", time = NOW - 1 })
ns.RefreshUI()
local row
for _, r in ipairs(panel.rows) do if r.line and r.line.item and r.line.item.link then row = r break end end
check(row and row.fs.text_:find("[Big Sword]", 1, true), "loot står med itemets navn")
TT = {} LINKED = nil
row.scripts.OnEnter(row)
check(LINKED == "item:777:0" and ttHas("Big Sword"), "musen over loot viser itemets tooltip")
SHIFT = true
row.scripts.OnClick(row)
SHIFT = false
check(#INSERTED == 1 and INSERTED[1]:find("|Hitem:777:0|h[Big Sword]|h", 1, true), "shift-klik sender linket i chatten")
TT = {}
panel.rows[1].scripts.OnEnter(panel.rows[1])
check(#TT > 0, "musen over en anden nyhed viser hele teksten")

-- -----------------------------------------------------------------------------
-- "[Loot]": navnet tages fra selve item-linket, ikke fra loot-historik-linket foran
-- -----------------------------------------------------------------------------
local n = #db.loot
local link = "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r"
Fire("CHAT_MSG_LOOT", "|HlootHistory:12|h[Loot]|h: You (Need - 87) Won: " .. link)
local ev = db.loot[#db.loot]
check(#db.loot == n + 1 and ev.name == "Dragonspine Trophy", "roll-sejr med [Loot]-link foran får itemets navn: " .. tostring(ev.name))
check(ev.quality == 4 and ev.how == "need" and ev.item:find("^item:28830"), "kvalitet, type og item er rigtige")
-- Farvet loot-historik-link foran: kvaliteten kommer stadig fra itemet
Fire("CHAT_MSG_LOOT", "|cff1eff00|HlootHistory:13|h[Loot]|h|r: You (Greed - 50) Won: |cffa335ee|Hitem:28831::::|h[Bracers]|h|r")
ev = db.loot[#db.loot]
check(ev.name == "Bracers" and ev.quality == 4 and ev.how == "greed", "farven på linket foran snyder ikke: " .. tostring(ev.name) .. "/" .. tostring(ev.quality) .. "/" .. tostring(ev.how))

-- Gamle data med "Loot" som navn rettes, når spillet kender itemet
ITEMS[4242] = { equip = true }
table.insert(db.loot, { id = "old-1", friend = "Jeppe", char = "Jepchar", class = "MAGE", item = "item:4242:0",
    name = "Loot", quality = 3, how = "roll", ctx = "dungeon", zone = "Stockades", time = NOW + 2 })
table.insert(db.loot, { id = "old-2", friend = "Nick", char = "Nickchar", class = "MAGE", item = "item:5353:0",
    name = "Loot", quality = 3, how = "roll", ctx = "dungeon", zone = "Stockades", time = NOW + 1 })
check(ns.core.LootLink(db.loot[#db.loot - 1]):find("[Item4242]", 1, true), "LootLink slår det rigtige navn op")
check(db.loot[#db.loot - 1].name == "Item4242", "og gemmer det")
check(ns.core.LootLink(db.loot[#db.loot]):find("[Loot]", 1, true), "ukendt item: navnet bliver stående uden fejl")
ns.ShowTab(1)
check(ns.lootTicker.text_:find("[Item4242]", 1, true), "Seneste loot på forsiden viser itemets navn")
ns.RefreshUI()
local found
for _, r in ipairs(panel.rows) do if r.shown and r.fs.text_:find("[Item4242]", 1, true) then found = true end end
check(found, "og det gør nyhedspanelet også")

-- -----------------------------------------------------------------------------
-- v0.26: filterknapper, ikoner og tidskolonne
-- -----------------------------------------------------------------------------
check(#panel.chips == 5 and panel.chips[1].active, "fem filterknapper, Alle er valgt")
Bar.SetPanelFilter("loot")
local onlyLoot = true
for _, r in ipairs(panel.rows) do
    if r.shown and r.line and r.line.item and r.line.item.key:sub(1, 1) ~= "o" then onlyLoot = false end
end
check(onlyLoot and panel.rows[1].shown and panel.chips[3].active and not panel.chips[1].active, "Loot viser kun loot")
check(not panel.rows[1].fs.text_:find("|T", 1, true), "itemets ikon står i ikonkolonnen, ikke i teksten")
Bar.SetPanelFilter("death")
check(panel.rows[1].line.item.key:sub(1, 1) == "d" and panel.offset == 0, "Død viser dødsfald fra toppen")
Bar.SetPanelFilter("level")
check(panel.rows[1].fs.text_:find("dingede 22"), "Level viser levels")
Bar.SetPanelFilter("all")
check(panel.chips[1].active and panel.count.text_ == "100", "tilbage til alle")
panel.chips[2].scripts.OnClick(panel.chips[2])
check(panel.filter == "death", "klik på en filterknap skifter filter")
Bar.SetPanelFilter("all")

-- Offline-kort: tiden står i hjørnet (ikke "OFFLINE"), og der er et kort til at invitere
ns.ShowTab(1)
ns.RefreshUI()
local nOff, okOff = 0, true
for _, c in ipairs(ns.offCards) do
    if c.shown ~= false and c.friend then
        nOff = nOff + 1
        local st, sub = c.state.text_ or "", c.sub.text_ or ""
        if st:find("OFFLINE", 1, true) or sub:find(" - ", 1, true) then okOff = false end
    end
end
check(nOff > 0 and okOff, "offline-kort: ingen OFFLINE-tekst, og karakterlinjen er kun karakteren")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
