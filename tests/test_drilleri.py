# Test af addonet med en lille WoW-attrap. Kør: pip install lupa && python3 tests/test_drilleri.py WastedCoast [native]
import sys, lupa.lua51 as L

ADDON = sys.argv[1]
lua = L.LuaRuntime(unpack_returned_tuples=True)

from wowmock import MOCK, load_addon

lua.execute(MOCK)
# "native": test spillets egne rammer/faner (som på WoW Forever) i stedet for den klassiske stil
NATIVE = len(sys.argv) > 2 and sys.argv[2] == "native"
if NATIVE:
    lua.execute('''
WastedCoastDB = { settings = { skin = "native" } }
TABSET = {}
function PanelTemplates_SetTab(f, id) TABSET[#TABSET+1] = id or true end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_TabResize() end
''')
ns = lua.table()
load_addon(lua, ADDON, ns)

G = lua.globals()
run = lua.execute

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function lastPrint() return PRINTS[#PRINTS] or "" end
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function findSent(prefix) pump() for i = #SENT, 1, -1 do if SENT[i].msg:sub(1, #prefix) == prefix then return SENT[i].msg end end end
local function toastQueue() return ns.toastsSeen end

-- Hold styr på toasts
ns.toastsSeen = {}
local origToast = ns.Toast

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
check(db.group and db.group.legacy and db.group.admin == "Mathias" and db.myId == "Mathias", "de 8 venner flyttes ind i Wasted Coast-gruppen")
check(#ns.core.ROSTER == 8 and ns.core.ROSTER[2] == "Mathias", "samme rækkefølge som før")
local realToast = ns.Toast
ns.Toast = function(o) ns.toastsSeen[#ns.toastsSeen+1] = o return realToast(o) end

-- Sider: 16 (fordelt på 5 faner), og Drilleri-siden findes
check(#ns.pages == 17 and #ns.tabs == 5, "17 sider på 5 faner")

-- XP-procent i level
check(ns.LevelText(42, 63) == "42 |cff9a9aa6(63%)|r", "level med XP-procent: " .. ns.LevelText(42, 63))
check(ns.LevelText(42, nil) == "42", "ukendt XP viser kun level")
check(ns.LevelText(ns.core.MAX_LEVEL, 50) == tostring(ns.core.MAX_LEVEL), "max level viser ingen procent")
check(ns.LevelText(0, 10) == "-", "ukendt level")
check(ns.LevelText(12, 5, "Level ") == "Level 12 |cff9a9aa6(5%)|r", "med præfiks")
ns.frame:Show()
for i = 1, 17 do if ns.pages[i] then ns.ShowTab(i) end end

-- Dødsannonce: en vens død via netværket, med svagt mob
SENT = {}
CLOCK = CLOCK + 100
local msg = table.concat({ "D", "Nickchar-" .. NOW, "Nickchar", "MAGE", "Murloc Forager", "Nærkamp", 31, "Westfall", NOW, "Nick", 12 }, ";")
Fire("CHAT_MSG_ADDON", "WCOAST", msg, "GUILD", "Nickchar")
local t = ns.toastsSeen[#ns.toastsSeen]
check(t and t.kind == "obit", "dødsannonce-toast")
check(t.text:find("12") and t.text:find("Murloc Forager"), "svagt mob nævnes med level: " .. t.text)
check(ns.HatHolder() == "Nick", "Nick har hatten")
check(lastPrint():find("Skammens hat"), "hat-besked i chat: " .. lastPrint())

-- Skammens hat i titler
local titles, holders = nil, nil
ns.ShowTab(1)
-- Kortet for en ven: store kort (online) eller små kort (offline)
function CardOf(friend)
    for _, c in ipairs(ns.cards) do if c.shown ~= false and c.friend == friend then return c end end
    for _, c in ipairs(ns.offCards) do if c.shown ~= false and c.friend == friend then return c end end
end
check(CardOf("Nick").hat.shown == true, "hat-ikon på Nicks kort")
check(CardOf("Mathias").hat.shown == false, "intet hat-ikon på Mathias")
check(ns.cards[1].friend == "Mathias" and ns.cards[1].shown ~= false, "online (dig selv) står øverst")
check(CardOf("Nick") == ns.offCards[1] or CardOf("Nick").state ~= nil, "Nick (offline) ligger under Offline")
check(ns.onHead:GetText():find("Online") and ns.offHead:GetText():find("Offline"), "grupperne Online og Offline")

-- Egen død: klvl måles fra target og sendes som felt 11
TARGET_NAME, TARGET_LEVEL = "Defias Thug", 45
CLOCK = CLOCK + 10
NOW = NOW + 60
CombatLogGetCurrentEventInfo = function() return 0, "SWING_DAMAGE", nil, nil, "Defias Thug", nil, nil, "guid", PLAYER end
Fire("COMBAT_LOG_EVENT_UNFILTERED")
Fire("PLAYER_DEAD")
local d = findSent("D;")
check(d and d:match(";45$"), "killer-level sendes: " .. tostring(d))
check(ns.HatHolder() == "Mathias", "hatten går videre til Mathias")
check(lastPrint():find("fra Nick til Mathias"), "hat-overdragelse: " .. lastPrint())
local t2 = ns.toastsSeen[#ns.toastsSeen]
check(t2.kind == "obit" and (t2.text:find("Defias Thug") or t2.text:find("Mathias")), "egen dødsannonce: " .. t2.text)

-- Uden combat log (som på Forever): en fjende på en nameplate, der har dig i target, er dræberen
do
    local oldName, oldExists, oldLevel = UnitName, UnitExists, UnitLevel
    UnitCanAttack = function(_, u) return u == "nameplate3" end
    UnitIsDead = function() return false end
    UnitIsUnit = function(a, b) return a == "nameplate3target" and b == "player" end
    UnitExists = function(u) return u == "nameplate3" end
    UnitName = function(u) if u == "nameplate3" then return "Riverpaw Gnoll" end return oldName(u) end
    UnitLevel = function(u) if u == "nameplate3" then return 17 end return oldLevel(u) end
    CLOCK = CLOCK + 60
    local k, ab, lvl = ns.FindKiller()
    check(k == "Riverpaw Gnoll" and lvl == 17, "dræber fra nameplate uden combat log: " .. tostring(k))
    -- Ingen fjende, men du faldt lige langt ned og mistede liv ved landingen: faldskade
    UnitExists = function() return false end
    local hp = 1000
    UnitHealth = function() return hp end
    local function air(secs) -- i luften i secs sekunder, målt hvert 0,1 sekund
        IsFalling = function() return true end
        for _ = 0, math.floor(secs * 10 + 0.5) do ns.FallTick() CLOCK = CLOCK + 0.1 end
        CLOCK = CLOCK - 0.1
    end
    local function land() IsFalling = function() return false end CLOCK = CLOCK + 0.1 ns.FallTick() end
    CLOCK = CLOCK + 60
    air(1.6) hp = 0 land()
    k, ab = ns.FindKiller()
    check(k == "Omgivelserne" and ab == ns.core.ENV_NAMES.Falling, "fald uden combat log: " .. tostring(k) .. " " .. tostring(ab))
    -- Døde i selve landingen, før næste måling så dig på jorden: stadig faldskade
    CLOCK = CLOCK + 60 hp = 1000
    air(1.6) hp = 0
    k, ab = ns.FindKiller()
    check(k == "Omgivelserne" and ab == ns.core.ENV_NAMES.Falling, "død ved landing: " .. tostring(k) .. " " .. tostring(ab))
    land()
    -- Dræbt midt i et almindeligt hop: ikke faldskade
    CLOCK = CLOCK + 60 hp = 1000
    air(0.7) hp = 0
    k, ab = ns.FindKiller()
    check(not (k == "Omgivelserne" and ab == ns.core.ENV_NAMES.Falling), "død i et hop er ikke faldskade: " .. tostring(k) .. " " .. tostring(ab))
    land()
    k = ns.FindKiller()
    check(k == "Ukendt", "landing efter et hop er ikke faldskade: " .. tostring(k))
    -- Dræbt lige efter et hop af en fjende, du har i target: fjenden er dræberen
    CLOCK = CLOCK + 60 hp = 1000
    UnitCanAttack = function(_, u) return u == "target" end
    UnitExists = function(u) return u == "target" end
    UnitName = function(u) if u == "target" then return "Murloc Hunter" end return oldName(u) end
    air(0.7) land() hp = 0
    k, ab = ns.FindKiller()
    check(k == "Murloc Hunter", "dræbt i et hop af dit target: " .. tostring(k) .. " " .. tostring(ab))
    UnitExists = function() return false end
    UnitCanAttack = function(_, u) return u == "nameplate3" end
    -- Langt fald uden at miste liv (fx Slow Fall), så dør du: ikke faldskade
    CLOCK = CLOCK + 60 hp = 1000
    air(2) land() hp = 0
    k = ns.FindKiller()
    check(k == "Ukendt", "landede uskadt: ikke faldskade: " .. tostring(k))
    UnitHealth = nil
    CLOCK = CLOCK + 60
    k = ns.FindKiller()
    check(k == "Ukendt", "intet at gå efter: Ukendt")
    UnitName, UnitExists, UnitLevel = oldName, oldExists, oldLevel
    UnitCanAttack, UnitIsDead, UnitIsUnit, IsFalling = nil, nil, nil, nil
end

-- Efternavne: sat med /wc4ever efternavn, sendt i livstegn og dødsfald, vist overalt
SlashCmdList["WASTEDCOAST"]("efternavn Stormhammer")
check(db.settings.surnames[PLAYER] == "Stormhammer", "efternavn gemt")
check(findSent("H;Mathias;" .. PLAYER .. ";"):match(";Stormhammer;%d+$"), "efternavn i livstegn")

-- "Er online"-toasten: kun ved et rigtigt login, ikke når et par livstegn går tabt midt i en session
do
    local function onlineToasts()
        local n = 0
        for _, o in ipairs(ns.toastsSeen) do if o.kind == "online" and o.friend == "Jeppe" then n = n + 1 end end
        return n
    end
    local function hb(session) Fire("CHAT_MSG_ADDON", "WCOAST", "H;Jeppe;Bus Knud;PALADIN;30;100;Westfall;10;;" .. (session or ""), "PARTY", "Bus Knud") end
    local before = onlineToasts()
    local savedJeppe, savedNow, savedClock = db.friends.Jeppe, NOW, CLOCK
    db.friends.Jeppe = nil
    CLOCK = CLOCK + 1000; NOW = NOW + 1000
    hb(5000)
    check(onlineToasts() == before + 1, "Jeppe logger ind: én toast")
    -- Samme session hele aftenen, men livstegnene udebliver i 4-5 minutter flere gange (fx boss-lockdown)
    for i = 1, 6 do
        CLOCK = CLOCK + 280; NOW = NOW + 280
        hb(5000)
        for j = 1, 5 do CLOCK = CLOCK + 60; NOW = NOW + 60; hb(5000) end
    end
    check(onlineToasts() == before + 1, "ingen ny toast i samme session: " .. (onlineToasts() - before))
    -- Logger ud og ind igen: ny session, ny toast
    CLOCK = CLOCK + 1200; NOW = NOW + 1200
    hb(9000)
    check(onlineToasts() == before + 2, "nyt login giver ny toast")
    -- Ældre version uden session: et par mistede livstegn giver ingen toast, et langt hul gør
    db.friends.Jeppe.session = nil
    CLOCK = CLOCK + 300; NOW = NOW + 300
    hb(nil)
    check(onlineToasts() == before + 2, "uden session: kort hul giver ingen toast")
    CLOCK = CLOCK + 1800; NOW = NOW + 1800
    hb(nil)
    check(onlineToasts() == before + 3, "uden session: langt hul giver toast")
    check(ns.CameOnline(1, 1, 5000) == false and ns.CameOnline(2, 1, 10) == true, "session afgør, ikke hullet")
    -- Egen session: den samme ved /reload, ny efter et rigtigt login
    local id = ns.MySession()
    ns.sessionLive = nil; NOW = NOW + 30
    check(ns.MySession() == id, "/reload beholder sessionen")
    ns.sessionLive = nil; NOW = NOW + 3600
    check(ns.MySession() ~= id, "nyt login giver ny session")
    db.friends.Jeppe, db.chars["Bus Knud"], NOW, CLOCK = savedJeppe, nil, savedNow, savedClock
    ns.sessionLive = nil; db.session = nil
end
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Nick;Sigurd;WARRIOR;30;100;Westfall;10;Jernhånd", "GUILD", "Sigurd")
check(db.friends.Nick.chars.Sigurd.surname == "Jernhånd", "vennens efternavn gemmes")
NOW = NOW + 20
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", "Sigurd-" .. NOW, "Sigurd", "WARRIOR", "Defias Pillager", "Nærkamp", 30, "Westfall", NOW, "Nick", 31 }, ";"), "GUILD", "Sigurd")
local deathLine
for i = #PRINTS, math.max(1, #PRINTS - 5), -1 do if PRINTS[i]:find("døde til") then deathLine = PRINTS[i] break end end
check(deathLine and deathLine:find("%(Sigurd Jernhånd%)") and deathLine:find("Defias Pillager"), "fuldt navn i dødsbesked: " .. tostring(deathLine))
check(ns.toastsSeen[#ns.toastsSeen].title:find("Sigurd Jernhånd"), "fuldt navn i dødsannonce")
ns.frame:Show()
ns.SelectTarget("Nick")
ns.ShowTab(3)
local sigRow
for _, r in ipairs(ns.charRows) do if type(rawget(r, "data")) == "table" and r.data.name == "Sigurd" then sigRow = r end end
check(sigRow and sigRow.name:GetText() == "Sigurd Jernhånd", "Karakterer viser fornavn og efternavn")
ns.ShowTab(1)

-- Gamle klienter uden felt 11 virker stadig
NOW = NOW + 30
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", "Frodex-" .. NOW, "Frodex", "ROGUE", "Faldskade", "", 20, "Thousand Needles", NOW, "Frode" }, ";"), "GUILD", "Frodex")
local t3 = ns.toastsSeen[#ns.toastsSeen]
check(t3.kind == "obit" and t3.title:find("Frode"), "dødsannonce uden klvl")

-- Annoncen er den samme hos alle (afhænger kun af id)
local ev = db.events[#db.events]
check(ns.Obituary(ev, "Frode") == ns.Obituary(ev, "Frode"), "stabil annonce")
for _, kind in ipairs({ "Faldskade", "Drukning", "Udmattelse", "Lava", "Ukendt", "Boss" }) do
  for i = 1, 8 do
    local e = { id = "x" .. i .. kind, killer = kind == "Lava" and "Omgivelserne" or kind, ability = kind == "Lava" and "Lava" or "", level = 30, klvl = kind == "Boss" and -1 or nil, zone = "Z" }
    local s = ns.Obituary(e, "Søren")
    check(not s:find("{"), "alle felter udfyldt: " .. s)
  end
end

-- v0.16: toast hos alle ved rare/epic loot, med fuldt karakternavn og item-link
local nL = #ns.toastsSeen
NOW = NOW + 10
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "L", "L-Sigurd-" .. NOW, "Nick", "Sigurd", "WARRIOR", "item:30000", 4, "need", "raid", "Gruul's Lair", NOW, "Big Purple" }, ";"), "GUILD", "Sigurd")
local lt = ns.toastsSeen[#ns.toastsSeen]
check(#ns.toastsSeen == nL + 1 and lt.kind == "epicloot", "epic loot giver toast")
check(lt.title == "Sigurd Jernhånd", "fuldt karakternavn i loot-toast: " .. tostring(lt.title))
check(lt.text:find("|Hitem:30000|h%[Big Purple%]|h") and lt.text:find("a335ee"), "item-link i lilla: " .. lt.text)
check(lt.head:find("EPIC") and lt.head:find("Nick"), "overskrift med vennens navn: " .. lt.head)
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "L", "L-Sigurd-" .. NOW, "Nick", "Sigurd", "WARRIOR", "item:30000", 4, "need", "raid", "Gruul's Lair", NOW, "Big Purple" }, ";"), "CHANNEL", "Sigurd")
check(#ns.toastsSeen == nL + 1, "samme loot via to kanaler giver kun én toast")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "L", "L-Sigurd-old", "Nick", "Sigurd", "WARRIOR", "item:30001", 4, "need", "raid", "Gruul's Lair", NOW - 3600, "Old Purple" }, ";"), "GUILD", "Sigurd")
check(#ns.toastsSeen == nL + 1, "gammelt loot fra synk giver ingen toast")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "L", "L-Sigurd-g" .. NOW, "Nick", "Sigurd", "WARRIOR", "item:30002", 2, "drop", "world", "Westfall", NOW, "Green Thing" }, ";"), "GUILD", "Sigurd")
check(#ns.toastsSeen == nL + 1, "grønt loot giver ingen toast")
-- Eget rare drop: toast hos mig selv, og det sendes til de andre
SENT = {}
Fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:30003::::::::40:::::|h[Blue Thing]|h|r.")
RunTimers()
lt = ns.toastsSeen[#ns.toastsSeen]
check(lt.kind == "rareloot" and lt.title == PLAYER .. " Stormhammer" and lt.text:find("Blue Thing"), "eget rare loot giver toast: " .. tostring(lt.title))
check(findSent("L;") and findSent("L;"):find("item:30003"), "eget rare loot sendes til de andre")
SlashCmdList["WASTEDCOAST"]("loottoast")
NOW = NOW + 1
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "L", "L-Sigurd-o" .. NOW, "Nick", "Sigurd", "WARRIOR", "item:30004", 4, "need", "raid", "Gruul's Lair", NOW, "Off Purple" }, ";"), "GUILD", "Sigurd")
check(ns.toastsSeen[#ns.toastsSeen] == lt, "loottoast fra: ingen toast")
SlashCmdList["WASTEDCOAST"]("loottoast")
check(db.settings.lootToasts == true, "loottoast til igen")
-- Ryd test-loottet igen, så resten af testene (fx sladderen) ser det samme som før
for i = #db.loot, 1, -1 do if db.loot[i].item:find("^item:3000%d") then table.remove(db.loot, i) end end

-- v0.16: rare mobs. Et rare elite mob i target, i kamp, og så dødt
do
  local U = { target = { guid = "Creature-0-1-2-3-4-0000AAAA", name = "Rak'shiri", level = 64, cls = "rareelite", dead = false, combat = true, denied = false } }
  local o = { UnitExists, UnitGUID, UnitName, UnitLevel, UnitAffectingCombat }
  local function u(x) return U[x] end
  UnitExists = function(x) if u(x) then return true end return o[1](x) end
  UnitGUID = function(x) if u(x) then return u(x).guid end return o[2](x) end
  UnitName = function(x) if u(x) then return u(x).name end return o[3](x) end
  UnitLevel = function(x) if u(x) then return u(x).level end return o[4](x) end
  UnitAffectingCombat = function(x) if u(x) then return u(x).combat end return o[5](x) end
  UnitClassification = function(x) return u(x) and u(x).cls or "normal" end
  UnitIsDead = function(x) return u(x) and u(x).dead or false end
  UnitIsTapDenied = function(x) return u(x) and u(x).denied or false end
  local nR = #ns.toastsSeen
  SENT = {}
  Fire("PLAYER_TARGET_CHANGED")
  check(#ns.toastsSeen == nR, "levende rare giver ingen toast")
  U.target.dead = true
  Fire("UNIT_HEALTH", "target")
  local rt = ns.toastsSeen[#ns.toastsSeen]
  check(#ns.toastsSeen == nR + 1 and rt.kind == "raremob", "dræbt rare giver toast")
  check(rt.title == PLAYER .. " Stormhammer" and rt.text:find("Rak'shiri") and rt.text:find("64") and rt.text:find("Rare Elite"), "rare-toast: " .. rt.text)
  local rm = findSent("RM;")
  check(rm and rm:find("^RM;Mathias;" .. PLAYER .. ";WARRIOR;Rak'shiri;64;rareelite;"), "drabet sendes: " .. tostring(rm))
  ns.ScanRares()
  check(#ns.toastsSeen == nR + 1, "samme corpse giver kun én toast")
  -- En vens drab af samme mob (de var med i gruppen): ingen ekstra toast
  Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "RM", "Nick", "Sigurd", "WARRIOR", "Rak'shiri", 64, "rareelite", "Nagrand", NOW, U.target.guid }, ";"), "GUILD", "Sigurd")
  check(#ns.toastsSeen == nR + 1, "samme mob fra en ven giver ingen ekstra toast")
  -- En vens drab af et andet rare
  Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "RM", "Nick", "Sigurd", "WARRIOR", "Voidhunter Yar", 63, "rare", "Netherstorm", NOW, "Creature-0-1-2-3-5-0000BBBB" }, ";"), "GUILD", "Sigurd")
  rt = ns.toastsSeen[#ns.toastsSeen]
  check(#ns.toastsSeen == nR + 2 and rt.title == "Sigurd Jernhånd" and rt.text:find("Voidhunter Yar") and rt.text:find("Netherstorm"), "vens rare-drab: " .. tostring(rt.title))
  check(db.rareKills.Nick == 1 and db.rareKills.Mathias == 1, "rare-drab tælles")
  Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "RM", "Nick", "Sigurd", "WARRIOR", "Voidhunter Yar", 63, "rare", "Netherstorm", NOW, "Creature-0-1-2-3-5-0000BBBB" }, ";"), "CHANNEL", "Sigurd")
  check(#ns.toastsSeen == nR + 2, "samme besked to gange: én toast")
  Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "RM", "Nick", "Sigurd", "WARRIOR", "Old Rare", 63, "rare", "X", NOW - 3600, "Creature-0-9" }, ";"), "GUILD", "Sigurd")
  check(#ns.toastsSeen == nR + 2, "gammelt drab giver ingen toast")
  -- Et rare, en anden har tagget, tæller ikke
  U.target = { guid = "Creature-0-1-2-3-6-0000CCCC", name = "Stolen Rare", level = 60, cls = "rare", dead = false, combat = true, denied = true }
  Fire("PLAYER_TARGET_CHANGED")
  U.target.dead = true
  Fire("UNIT_HEALTH", "target")
  check(#ns.toastsSeen == nR + 2, "tagget af andre: ingen toast")
  -- Et normalt mob tæller ikke; et rare, vi aldrig har været i kamp med, heller ikke
  U.target = { guid = "Creature-0-1-2-3-7-0000DDDD", name = "Boar", level = 10, cls = "normal", dead = true, combat = false }
  Fire("PLAYER_TARGET_CHANGED")
  U.target = { guid = "Creature-0-1-2-3-8-0000EEEE", name = "Old Corpse", level = 30, cls = "rare", dead = true, combat = false }
  Fire("PLAYER_TARGET_CHANGED")
  check(#ns.toastsSeen == nR + 2, "normalt mob og fremmed corpse: ingen toast")
  -- Combat loggen (TBC): et husket rare dør uden at være i target
  U.target = { guid = "Creature-0-1-2-3-9-0000FFFF", name = "Log Rare", level = 61, cls = "rare", dead = false, combat = true }
  Fire("PLAYER_TARGET_CHANGED")
  U.target = nil
  ns.OnRareDied("Creature-0-1-2-3-9-0000FFFF")
  check(ns.toastsSeen[#ns.toastsSeen].text:find("Log Rare"), "rare fundet via combat log")
  ns.TestRareToast()
  check(ns.toastsSeen[#ns.toastsSeen].kind == "raremob", "test-toast for rare")
  UnitExists, UnitGUID, UnitName, UnitLevel, UnitAffectingCombat = o[1], o[2], o[3], o[4], o[5]
  UnitClassification, UnitIsDead, UnitIsTapDenied = nil, nil, nil
end

-- Need-politiet: et needet item, der bliver solgt
ITEMS[28830] = { equip = true, count = 1, equipped = false }
Fire("CHAT_MSG_LOOT", "You have selected Need for: |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
Fire("CHAT_MSG_LOOT", "You won: |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
local n = 0 for _ in pairs(db.needWatch) do n = n + 1 end
check(n == 1, "need-item under opsyn")
NOW = NOW + 120
ns.CheckNeeds()
n = 0 for _ in pairs(db.needWatch) do n = n + 1 end
check(n == 1, "stadig i tasken: ingen dom endnu")
ITEMS[28830].count = 0
SENT = {}
ns.CheckNeeds()
check(#db.needShame == 1 and db.needShame[1].why == "gone", "solgt uden brug bliver hængt ud")
local xn = findSent("XN;")
check(xn ~= nil, "XN sendes: " .. tostring(xn))
check(ns.toastsSeen[#ns.toastsSeen].kind == "police", "need-politi-toast")

-- Taget på = frikendt
ITEMS[27450] = { equip = true, count = 1, equipped = false }
ns.WatchNeed({ id = 27450, itemString = "item:27450", name = "Wrap of Unity", quality = 3 })
ITEMS[27450].equipped = true
ns.CheckNeeds()
check(#db.needShame == 1, "brugt item bliver ikke hængt ud")
-- Ubrugt i 3 dage
ITEMS[29434] = { equip = true, count = 1, equipped = false }
ns.WatchNeed({ id = 29434, itemString = "item:29434", name = "Belt", quality = 3 })
NOW = NOW + 3 * 86400 + 10
ns.CheckNeeds()
check(#db.needShame == 2 and db.needShame[2].why == "unused", "ubrugt i 3 dage")
-- Ikke-gear ignoreres
ITEMS[111] = { equip = false, count = 1 }
ns.WatchNeed({ id = 111, itemString = "item:111", name = "Pattern", quality = 3 })
n = 0 for _ in pairs(db.needWatch) do n = n + 1 end
check(n == 0, "opskrifter o.l. tælles ikke")

-- Modtag en vens need-synd, og dubletter filtreres
local xn2 = table.concat({ "XN", "N-Jeppe-1-5", "Jeppe", "Jeppex", "HUNTER", "item:28572", 4, "unused", NOW, "Blade of the Unrequited" }, ";")
Fire("CHAT_MSG_ADDON", "WCOAST", xn2, "GUILD", "Jeppex")
Fire("CHAT_MSG_ADDON", "WCOAST", xn2, "PARTY", "Jeppex")
check(#db.needShame == 3, "vens need-synd modtaget én gang")

-- Held: egne rolls fra loot og /roll
for _, v in ipairs({ 90, 85, 99, 70, 88, 95 }) do
  Fire("CHAT_MSG_SYSTEM", "Mathiasx rolls " .. v .. " (1-100)")
end
Fire("CHAT_MSG_SYSTEM", "Mathiasx rolls 3 (1-50)")
Fire("CHAT_MSG_SYSTEM", "Andreasx rolls 100 (1-100)")
Fire("CHAT_MSG_LOOT", "Need Roll - 77 for |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r by Mathiasx")
local r = db.rolls.Mathias
check(#r.last == 7, "7 rolls gemt (kun 1-100 og kun egne): " .. #r.last)
local pct = ns.LuckPercent("Mathias")
check(pct and pct > 95, "meget heldig: " .. tostring(pct))
SENT = {}
RunTimers()
local xk = findSent("XK;Mathias;")
check(xk ~= nil, "XK sendes")
-- Vens rolls (lave)
Fire("CHAT_MSG_ADDON", "WCOAST", "XK;Nick;" .. NOW .. ";5,10,22,3,40,12", "GUILD", "Nickchar")
check(#db.rolls.Nick.last == 6 and ns.LuckPercent("Nick") < 5, "Nick er uheldig")
-- Ældre data overskriver ikke nyere
Fire("CHAT_MSG_ADDON", "WCOAST", "XK;Nick;" .. (NOW - 100) .. ";99,99,99,99,99", "GUILD", "Nickchar")
check(#db.rolls.Nick.last == 6, "ældre XK ignoreres")
-- Normalt held ~50%
Fire("CHAT_MSG_ADDON", "WCOAST", "XK;Rasmus;" .. NOW .. ";50,51,50,51,50,51", "GUILD", "R")
local rp = ns.LuckPercent("Rasmus")
check(rp >= 45 and rp <= 55, "snit 50,5 = ca. 50%: " .. rp)
check(ns.LuckPercent("Frode") == nil, "for få rolls = ingen rating")
-- Titlen Fætter Højben og Skammens hat i scoreboard
ns.ShowTab(2)
check(ns.scoreInfo:GetText():find("Fætter Højben:|r Mathias"), "Fætter Højben: " .. ns.scoreInfo:GetText())
check(ns.scoreInfo:GetText():find("Skammens hat:|r Frode"), "Skammens hat-titel")

-- Level-snegl
ns.ShowTab(1)
check(ns.snailHolder == "Frode", "Frode (level 20) er sneglen: " .. tostring(ns.snailHolder))
check(CardOf("Frode").name:GetText():find("Turtle"), "snegl ved Frodes navn")
check(not CardOf("Nick").name:GetText():find("Turtle"), "ingen snegl ved Nick")
check(ns.SnailText("Frode"):find("mindst"), "gættet tid: " .. ns.SnailText("Frode"))
check(ns.SnailText("Nick") == nil, "kun sneglen har tekst")
Fire("CHAT_MSG_ADDON", "WCOAST", "XL;Frode;20;" .. (NOW - 2 * 86400) .. ";0", "GUILD", "Frodex")
check(ns.SnailText("Frode"):find("2 d") and not ns.SnailText("Frode"):find("mindst"), "vennens egen tid: " .. ns.SnailText("Frode"))
Fire("CHAT_MSG_ADDON", "WCOAST", "XL;Frode;20;" .. (NOW - 100) .. ";1", "GUILD", "Frodex")
check(ns.SnailText("Frode"):find("2 d"), "et gæt overskriver ikke en rigtig tid")
ns.ShowTab(2)
check(ns.scoreInfo:GetText():find("Level%-snegl:|r Frode"), "Level-snegl-titel")
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Frode;Frodex;ROGUE;45;100;Ogrimmar;3", "GUILD", "Frodex")
ns.ShowTab(1)
check(ns.snailHolder == "Nick", "Frode levelede forbi: nu er Nick sneglen: " .. tostring(ns.snailHolder))
SENT = {}
Fire("PLAYER_LEVEL_UP", 41)
check(WastedCoastDB.levelAt.Mathias.l == 41 and not WastedCoastDB.levelAt.Mathias.g, "eget level-up gemmes")
check(findSent("XL;Mathias;41;"), "eget level-up sendes")

-- Emote-angreb
SENT = {}
ns.EmoteAttack("Nick")
local xe = findSent("XE;Mathias;Nick;")
check(xe ~= nil, "XE sendes")
check(lastPrint():find("Nick"), "angrebet vises i chat: " .. lastPrint())
local before = #SENT
ns.EmoteAttack("Jeppe")
check(#SENT == before and lastPrint():find("Rolig"), "cooldown")
CLOCK = CLOCK + 20
TARGET_NAME = "Jeppex"
db.chars["Jeppex"] = "Jeppe"
ns.EmoteAttack("Jeppe")
check(#EMOTES == 1 and EMOTES[1]:find(">target$"), "rigtig emote på target: " .. tostring(EMOTES[1]))
-- Modtag et angreb
local nT = #ns.toastsSeen
Fire("CHAT_MSG_ADDON", "WCOAST", "XE;Søren;Mathias;4;123", "GUILD", "Sorenx")
Fire("CHAT_MSG_ADDON", "WCOAST", "XE;Søren;Mathias;4;123", "WHISPER", "Sorenx")
check(#ns.toastsSeen == nT + 1 and ns.toastsSeen[#ns.toastsSeen].kind == "emote", "angreb mod mig giver én popup")
check(db.emoteStats.recv.Mathias == 1 and db.emoteStats.sent.Mathias == 2, "emote-statistik")
-- Slå popups fra
SlashCmdList.WASTEDCOAST("emotes")
check(db.settings.emotes == false, "emotes slået fra")
Fire("CHAT_MSG_ADDON", "WCOAST", "XE;Søren;Mathias;5;124", "GUILD", "Sorenx")
check(#ns.toastsSeen == nT + 1, "ingen popup når slået fra")
SlashCmdList.WASTEDCOAST("emotes")
SlashCmdList.WASTEDCOAST("annonce")
check(db.settings.obits == false, "annoncer fra")
SlashCmdList.WASTEDCOAST("annonce")
check(db.settings.obits == true, "annoncer til")
CLOCK = CLOCK + 20
SENT = {}
SlashCmdList.WASTEDCOAST("angrib nic")
check(findSent("XE;Mathias;Nick;") ~= nil, "/wc4ever angrib nic")
SlashCmdList.WASTEDCOAST("testannonce")
SlashCmdList.WASTEDCOAST("testtoast")
SlashCmdList.WASTEDCOAST("hjælp")

-- Drilleri-siden kan tegnes
ns.ShowTab(13)
ns.ShowTab(8)

-- Synk: sender XK og egne need-synder
SENT = {}
ns.SendMyExtras()
check(findSent("XK;Mathias;") and findSent("XN;N-"), "synk sender drilleri-data")

-- Guild bank: guld ind og ud
SENT = {}
Fire("GUILDBANKFRAME_OPENED")
MONEY = MONEY - 500000
DepositGuildBankMoney(500000)
Fire("PLAYER_MONEY")
check(db.bank.Mathias and db.bank.Mathias.dg == 500000, "50g lagt i banken")
WithdrawGuildBankMoney(200000)
MONEY = MONEY + 200000
Fire("PLAYER_MONEY")
check(db.bank.Mathias.wg == 200000, "20g taget ud")
-- En hævning, der ikke går igennem, tæller ikke (heller ikke når pengene senere ændrer sig)
WithdrawGuildBankMoney(999999)
CLOCK = CLOCK + 20
MONEY = MONEY + 999999
Fire("PLAYER_MONEY")
check(db.bank.Mathias.wg == 200000, "afvist hævning tæller ikke")
-- Ting: 3 lagt ind, så 1 taget ud
BAGS[0][1].count = 2
Fire("BAG_UPDATE")
Fire("GUILDBANKBAGSLOTS_CHANGED")
RunTimers()
check(db.bank.Mathias.di == 3 and db.bank.Mathias.items[13446].d == 3, "3 ting lagt ind")
BAGS[0][2] = { id = 13446, count = 1 }
Fire("GUILDBANKBAGSLOTS_CHANGED")
Fire("BAG_UPDATE")
RunTimers()
check(db.bank.Mathias.wi == 1, "1 ting taget ud")
-- Spiser du, mens banken er åben, tæller det ikke
CLOCK = CLOCK + 10
BAGS[0][2].count = 0
Fire("BAG_UPDATE")
RunTimers()
CLOCK = CLOCK + 5
RunTimers()
Fire("BAG_UPDATE")
RunTimers()
check(db.bank.Mathias.di == 3, "spist mad tæller ikke som indsat: " .. db.bank.Mathias.di)
Fire("GUILDBANKFRAME_CLOSED")
local bk = findSent("BK;Mathias;")
check(bk and bk:find(";500000;200000;3;1;"), "BK sendes samlet: " .. tostring(bk))

-- Repair: selv betalt, betalt af guilden, og en solgt slidt ting (ikke repair)
REPAIR_COST = 150000
Fire("MERCHANT_SHOW")
RepairAllItems(false)
Fire("PLAYER_MONEY")
Fire("UPDATE_INVENTORY_DURABILITY")
RunTimers()
check(db.bank.Mathias.rep == 150000 and db.bank.Mathias.grep == 0 and db.bank.Mathias.nrep == 1, "15g repair betalt selv")
Fire("MERCHANT_CLOSED")
REPAIR_COST = 80000
Fire("MERCHANT_SHOW")
RepairAllItems(true)
Fire("UPDATE_INVENTORY_DURABILITY")
RunTimers()
check(db.bank.Mathias.rep == 230000 and db.bank.Mathias.grep == 80000 and db.bank.Mathias.maxrep == 150000, "8g repair betalt af guilden")
REPAIR_COST = 30000
Fire("UPDATE_INVENTORY_DURABILITY")
RunTimers()
REPAIR_COST = 10000
MONEY = MONEY + 5000
Fire("PLAYER_MONEY")
Fire("UPDATE_INVENTORY_DURABILITY")
RunTimers()
check(db.bank.Mathias.nrep == 2, "solgt slidt ting er ikke en reparation")
Fire("MERCHANT_CLOSED")

-- En vens totaler, store bevægelser nævnes, ældre beskeder ignoreres
local function bkmsg(at, wg, rep) return table.concat({ "BK", "Nick", at, 100000, wg, 2, 40, 500, 9000, rep, 0, 3, rep, "13446:30", "", NOW - 86400 }, ";") end
Fire("CHAT_MSG_ADDON", "WCOAST", bkmsg(NOW - 10, 1000000, 50000), "GUILD", "Nickchar")
check(db.bank.Nick and db.bank.Nick.wg == 1000000 and db.bank.Nick.tw == "13446:30", "Nicks bank-tal modtaget")
Fire("CHAT_MSG_ADDON", "WCOAST", bkmsg(NOW, 2000000, 250000), "GUILD", "Nickchar")
check(PRINTS[#PRINTS - 1]:find("tog lige") and lastPrint():find("reparere"), "stor hævning og repair nævnes: " .. lastPrint())
Fire("CHAT_MSG_ADDON", "WCOAST", bkmsg(NOW - 100, 5, 5), "GUILD", "Nickchar")
check(db.bank.Nick.wg == 2000000, "ældre BK ignoreres")
Fire("CHAT_MSG_ADDON", "WCOAST", "BK;Nick;" .. (NOW + 5) .. ";x", "GUILD", "Nickchar")
check(db.bank.Nick.wg == 2000000, "ødelagt BK ignoreres")
ns.ShowTab(15)
check(ns.subTabs[2][5].active, "Bank & repair under Rangliste")
check(ns.bankUI.bankFacts:GetText():find("Bankrøveren:|r .*Nick"), "Nick er bankrøver: " .. ns.bankUI.bankFacts:GetText())
check(ns.bankUI.repFacts:GetText():find("Rustbunken:|r .*Nick"), "Nick er rustbunke: " .. ns.bankUI.repFacts:GetText())
check(ns.bankUI.bankRows[1].f[2]:GetText() == "Nick", "Nick øverst på 'Taget'")
ns.bankSort = "gave"
ns.RefreshUI()
check(ns.bankUI.bankRows[1].f[2]:GetText() == "Mathias (dig)", "Mathias øverst på 'Lagt'")
ns.bankUI.bankRows[1].scripts.OnEnter(ns.bankUI.bankRows[1])
ns.bankUI.repRows[1].scripts.OnEnter(ns.bankUI.repRows[1])
SENT = {}
ns.SendMyExtras(true)
check(findSent("BK;Mathias;"), "let synk sender også BK")

-- Demo til og fra
SlashCmdList.WASTEDCOAST("demo")
ns.ShowTab(13)
ns.ShowTab(1)

-- Hele vinduet kan tegnes med demo-data: alle faner, fade-in og toast-animation
ns.frame:Show()
ns.frame.scripts.OnShow(ns.frame)
check(#ns.tabs == 5, "fem faner")
if TABSET then
  check(ns.native and ns.frame.chrome ~= nil, "native stil bruger spillets ramme")
  check(#TABSET > 0, "native faner vælges med PanelTemplates_SetTab")
else
  check(not ns.native, "klassisk stil uden for Forever")
end
for i = 1, #ns.pages do ns.ShowTab(i) end
ns.ShowTab(3)
check(ns.tabs[1].active and not ns.tabs[2].active, "karakterer hører under Venner")
check(ns.subTabs[1][2].active and ns.subTabs[1][2]:IsShown() and not ns.subTabs[3][1]:IsShown(), "undersider følger fanen")
ns.ShowTab(13)
check(ns.tabs[5].active and ns.subTabs[5][2].active, "drilleri hører under Sjov")
local seen = {}
for _, g in ipairs(ns.GROUPS) do for _, pg in ipairs(g.pages) do seen[pg] = true end end
for _, i in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do check(seen[i], "side " .. i .. " kan nås fra en fane") end
-- Loot-fanen er kun loot; død og instanser ligger under Død
local lootGrp, deathGrp = ns.GROUPS[3], ns.GROUPS[4]
check(lootGrp.label == "Loot" and #lootGrp.pages == 2 and lootGrp.pages[1] == 4 and lootGrp.pages[2] == 8, "Loot-fanen: Loot og Rolls")
check(deathGrp.label == "Død" and deathGrp.pages[1] == 16 and deathGrp.pages[2] == 5, "Død-fanen: Statistik og Instanser")
local tNew = 0
for _, ev in ipairs(db.events) do tNew = math.max(tNew, ev.time or 0) end
tNew = tNew + 1
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", "Sigurd-" .. tNew, "Sigurd", "WARRIOR", "Defias Pillager", "Nærkamp", 30, "Westfall", tNew, "Nick", 31 }, ";"), "GUILD", "Sigurd")
ns.ShowTab(16)
check(ns.tabs[4].active and not ns.tabs[3].active, "dødsstatistik hører under Død")
check(#db.events > 0 and ns.deathRecentText.text_:find("|cff888888i ", 1, true) and not ns.deathRecentText.text_:find("Ingen dødsfald"), "seneste dødsfald vises: " .. tostring(ns.deathRecentText.text_))
check(not ns.deathRecentText.text_:find("Omgivelserne"), "omgivelserne vises som selve årsagen")
check(ns.deathRecentText.text_:find("Sigurd Jernhånd", 1, true), "seneste dødsfald viser fornavn + efternavn: " .. tostring(ns.deathRecentText.text_))
check(ns.deathStatText.text_:find("Farligste mob"), "dødsstatistik vises")
ns.ShowTab(8)
check(ns.tabs[3].active and ns.rollRows[1]:IsShown(), "rolls hører under Loot")
ns.frame.scripts.OnUpdate(ns.frame, 2.1)
ns.Toast({ kind = "wipe", title = "Wipe", text = "test", force = true })
local tf = _G.WastedCoastToast
for _ = 1, 40 do tf.scripts.OnUpdate(tf, 0.25) end
ns.ShowTab(1)

-- Minimap-knappen: klik åbner/lukker, træk gemmer vinklen, /wc4ever minimap skjuler
local mb = _G.WastedCoastMinimapButton
check(mb ~= nil, "minimap-knap findes")
ns.frame:Hide()
mb.scripts.OnClick(mb, "LeftButton")
check(ns.frame:IsShown(), "klik på logoet åbner vinduet")
mb.scripts.OnEnter(mb)
mb.scripts.OnDragStart(mb)
mb.scripts.OnUpdate(mb, 0.1)
mb.scripts.OnDragStop(mb)
check(type(db.settings.minimapAngle) == "number", "træk gemmer placering")
SlashCmdList.WASTEDCOAST("minimap")
check(db.settings.minimapHide and not mb:IsShown(), "/wc4ever minimap skjuler knappen")
SlashCmdList.WASTEDCOAST("minimap")
check(not db.settings.minimapHide, "/wc4ever minimap viser knappen igen")
ns.ShowTab(14)
check(ns.DuelStats("Nick") ~= nil, "demo-dueller kan tegnes")
SlashCmdList.WASTEDCOAST("demo slut")
for _, e in ipairs(db.needShame) do check(not e.demo, "demo fjernet") end
for _, list in pairs(db.duels) do for _, d in ipairs(list) do check(not d.demo, "demo-dueller fjernet") end end

-- Spilletid og deaths/hr (Played.lua)
do
    local shown, asked = 0, 0
    RequestTimePlayed = function() asked = asked + 1 end
    ChatFrame_DisplayTimePlayed = function() shown = shown + 1 end
    ns.AskPlayed()
    check(asked == 1, "addonet spørger om /played")
    ChatFrame_DisplayTimePlayed(nil, 7200, 600)
    check(shown == 0, "addonets egen /played skrives ikke i chatten")
    SENT = {}
    Fire("TIME_PLAYED_MSG", 7200, 600)
    check(findSent("PT;Mathias;" .. PLAYER .. ";7200;600;"), "egen spilletid sendes: " .. tostring(findSent("PT;")))
    CLOCK = CLOCK + 10
    ChatFrame_DisplayTimePlayed(nil, 7200, 600)
    check(shown == 1, "selv skrevet /played vises som altid")
    local myDeaths = 0
    for _, ev in ipairs(db.events) do if ns.core.EventFriend(ev) == "Mathias" and ev.name == PLAYER then myDeaths = myDeaths + 1 end end
    local mt = ns.PlayedTotals("Mathias")
    check(mt.secs >= 7200 and mt.secs < 7300 and mt.rated == myDeaths, "egen spilletid og dødsfald: " .. tostring(mt.secs) .. " " .. mt.rated)
    check(math.abs(ns.DeathRate(myDeaths, 7200) - myDeaths / 2) < 1e-9, "deaths/hr = døde / timer")
    CLOCK = CLOCK + 600
    SENT = {}
    ns.SendMyExtras(true)
    check(findSent("PT;Mathias;" .. PLAYER .. ";78"), "spilletiden tæller videre: " .. tostring(findSent("PT;")))

    -- Vennens karakterer
    Fire("CHAT_MSG_ADDON", "WCOAST", "PT;Nick;Sigurd;36000;1200;" .. NOW, "GUILD", "Sigurd")
    check(db.friends.Nick.chars.Sigurd.played.t == 36000, "vennens spilletid gemmes")
    Fire("CHAT_MSG_ADDON", "WCOAST", "PT;Nick;Sigurd;100;5;" .. (NOW + 5), "GUILD", "Sigurd")
    check(db.friends.Nick.chars.Sigurd.played.t == 36000, "lavere spilletid ignoreres")
    Fire("CHAT_MSG_ADDON", "WCOAST", "PT;Nick;Sigurd;x;5;1", "GUILD", "Sigurd")
    Fire("CHAT_MSG_ADDON", "WCOAST", "PT;Fremmed;Bob;500;5;1", "GUILD", "Bob")
    check(db.friends.Nick.chars.Sigurd.played.t == 36000 and not (db.friends.Fremmed), "snyd ignoreres")
    Fire("CHAT_MSG_ADDON", "WCOAST", "PT;Nick;Nickchar;3600;100;" .. NOW, "GUILD", "Nickchar")
    local nt = ns.PlayedTotals("Nick")
    check(nt.known == 2 and nt.secs >= 39600, "Nicks spilletid lægges sammen: " .. tostring(nt.secs))
    local chars = ns.PlayedChars("Nick")
    check(chars[1].name == "Sigurd" and chars[1].full == "Sigurd Jernhånd", "mest spillede karakter først med fuldt navn")
    local g = ns.GroupPlayed()
    check(g.secs >= nt.secs + 7200 and g.topFriend == "Nick", "hele gruppens spilletid")
    check(ns.FormatPlayed(90061) == "1d 1t" and ns.FormatPlayed(3720) == "1t 2m" and ns.FormatPlayed(59) == "0m", "format af spilletid")
    check(ns.DeathRate(3, 600) == nil, "under en halv time: ingen deaths/hr")

    ns.ShowTab(17)
    check(ns.tabs[2].active and ns.subTabs[2][2].active, "Spilletid under Rangliste")
    local ui = ns.playedUI
    check(ui.total:GetText():find("Hele gruppen"), "gruppens spilletid vises: " .. tostring(ui.total:GetText()))
    check(ui.rows[1].f[2]:GetText() == "Nick", "mest spillet øverst: " .. tostring(ui.rows[1].f[2]:GetText()))
    ui.rows[1].scripts.OnClick(ui.rows[1])
    check(ui.rightHead:GetText() == "Nick" and ui.charRows[1].f[1]:GetText() == "Sigurd Jernhånd", "klik viser Nicks karakterer")
    ui.rows[1].scripts.OnEnter(ui.rows[1])
    ui.charRows[1].scripts.OnEnter(ui.charRows[1])
    ns.ShowTab(16)
    check(ns.deathStatText.text_:find("Deaths/hr"), "deaths/hr på dødsstatistikken")
    ns.ShowTab(3)
end
ns.ShowTab(13)

-- v0.15: PvP- og PvE-dødsfald
do
    -- Uden combat log (Forever): en fjendtlig spiller på en nameplate, der har dig i target
    local oldName, oldExists, oldLevel = UnitName, UnitExists, UnitLevel
    UnitCanAttack = function(_, u) return u == "nameplate5" end
    UnitIsDead = function() return false end
    UnitIsUnit = function(a, b) return a == "nameplate5target" and b == "player" end
    UnitExists = function(u) return u == "nameplate5" end
    UnitIsPlayer = function(u) return u == "nameplate5" end
    UnitName = function(u) if u == "nameplate5" then return "Grimgor" end return oldName(u) end
    UnitLevel = function(u) if u == "nameplate5" then return 41 end return oldLevel(u) end
    CLOCK = CLOCK + 60
    local k, _, lvl, pvp = ns.FindKiller()
    check(k == "Grimgor" and lvl == 41 and pvp == true, "spiller på nameplate er PvP: " .. tostring(k) .. " " .. tostring(pvp))
    SENT = {}
    NOW = NOW + 60
    Fire("PLAYER_DEAD")
    local d = findSent("D;")
    check(d and d:match(";1$"), "PvP sendes som felt 13: " .. tostring(d))
    local ev = db.events[#db.events]
    check(ev.killer == "Grimgor" and ev.pvp == true, "eget PvP-dødsfald gemmes")
    ns.CheckAchievements(true)
    check(db.ach[db.me] and db.ach[db.me].pvp1, "trofæet Ganket")
    check(ns.Obituary(ev, "Mathias"):find("Grimgor") and not ns.Obituary(ev, "Mathias"):find("{"), "PvP-dødsannonce: " .. ns.Obituary(ev, "Mathias"))
    -- Et mob er ikke PvP
    UnitIsPlayer = function() return false end
    CLOCK = CLOCK + 60
    k, _, _, pvp = ns.FindKiller()
    check(k == "Grimgor" and pvp == false, "et mob er PvE")
    UnitName, UnitExists, UnitLevel = oldName, oldExists, oldLevel
    UnitCanAttack, UnitIsDead, UnitIsUnit, UnitIsPlayer = nil, nil, nil, nil

    -- Med combat log: kildens flag afgør det (0x100 = styret af en spiller)
    bit = { band = function(a, b) return (math.floor(a / b) % 2 == 1) and b or 0 end }
    CLOCK = CLOCK + 60
    CombatLogGetCurrentEventInfo = function() return 0, "SWING_DAMAGE", nil, "Player-1-01", "Zugzug", 0x548, nil, "guid", PLAYER end
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    k, _, _, pvp = ns.FindKiller()
    check(k == "Zugzug" and pvp == true, "combat log: spiller er PvP")
    CombatLogGetCurrentEventInfo = function() return 0, "SPELL_DAMAGE", nil, "Creature-0-1", "Defias Mage", 0xa48, nil, "guid", PLAYER, nil, nil, 133, "Fireball" end
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    k, _, _, pvp = ns.FindKiller()
    check(k == "Defias Mage" and pvp == false, "combat log: mob er PvE")
    bit = nil
    CLOCK = CLOCK + 60

    -- Fra en ven: felt 13 = "1" (felt 12 tomt uden efternavn); gamle beskeder er PvE
    NOW = NOW + 30
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", "Nickchar-" .. NOW, "Nickchar", "WARRIOR", "Zugzug", "Nærkamp", 30, "Hillsbrad Foothills", NOW, "Nick", 32, "", "1" }, ";"), "GUILD", "Nickchar")
    local nev = db.events[#db.events]
    check(nev.pvp == true and nev.sur == nil, "vennens PvP-dødsfald modtages")
    local pvpLine
    for i = #PRINTS, math.max(1, #PRINTS - 5), -1 do if PRINTS[i]:find("døde til") then pvpLine = PRINTS[i] break end end
    check(pvpLine and pvpLine:find("Zugzug") and pvpLine:find("PvP"), "PvP i chatbeskeden: " .. tostring(pvpLine))
    NOW = NOW + 1
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", "Nickchar-" .. NOW, "Nickchar", "WARRIOR", "Murloc", "Nærkamp", 30, "Westfall", NOW, "Nick", 12 }, ";"), "GUILD", "Nickchar")
    check(db.events[#db.events].pvp == nil, "gammelt format er PvE")

    local nick
    for _, s in ipairs(ns.core.BuildStats()) do if s.name == "Nick" then nick = s end end
    check(nick.pvp == 1 and nick.pve == nick.deaths - 1, "Nick: PvP og PvE tælles hver for sig: " .. nick.pvp .. "/" .. nick.pve)
    local nt = ns.PlayedTotals("Nick")
    check(nt.ratedPvp == 1 and nt.pvpDph and nt.pveDph and math.abs(nt.pvpDph + nt.pveDph - nt.dph) < 1e-9, "deaths/hr deles i PvE og PvP")

    ns.ShowTab(2)
    local heads = {}
    for _, h in ipairs(ns.headers) do heads[#heads + 1] = h.text:GetText() end
    local hs = table.concat(heads, ",")
    check(hs:find("PvE") and hs:find("PvP"), "Ranglisten har PvE og PvP: " .. hs)
    ns.ShowTab(16)
    check(ns.deathStatText.text_:find("Farligste spiller") and ns.deathStatText.text_:find("Zugzug"), "farligste spiller: " .. ns.deathStatText.text_)
    check(ns.deathSplitText:GetText():find("PvP"), "PvE/PvP-fordeling på Død")
    check(ns.deathRecentText.text_:find("(PvP)", 1, true), "PvP markeres i seneste dødsfald")
    ns.ShowTab(17)
    check(ns.playedUI.total:GetText():find("PvP"), "PvP pr. time for hele gruppen")
    ns.ShowTab(1)
    check(CardOf("Nick").deaths:GetText():find("1 PvP"), "PvP på kortet: " .. CardOf("Nick").deaths:GetText())
    CardOf("Nick").scripts.OnEnter(CardOf("Nick"))
end

-- Level-toast: egen ding giver popup og XU med tid siden sidste level
local nT = #ns.toastsSeen
SENT = {}
db.myLevelT = { [PLAYER] = NOW - 5400 }
Fire("PLAYER_LEVEL_UP", 42)
local lt = ns.toastsSeen[#ns.toastsSeen]
check(#ns.toastsSeen == nT + 1 and lt.kind == "levelup" and lt.title == "Du nåede level 42", "egen level-toast")
check(lt.text:find("1 t siden sidste level"), "tid siden sidste level: " .. lt.text)
check(findSent("XU;Mathias;" .. PLAYER .. ";WARRIOR;42;5400"), "XU sendes")
-- Vens ding: én popup, selv om livstegnet kommer bagefter
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Andreas;Andyx;PRIEST;29;100;Elwynn;3", "GUILD", "Andyx")
STARTED_LONG_AGO = true
CLOCK = CLOCK + 1000
nT = #ns.toastsSeen
Fire("CHAT_MSG_ADDON", "WCOAST", "XU;Andreas;Andyx;PRIEST;30;7200", "GUILD", "Andyx")
Fire("CHAT_MSG_ADDON", "WCOAST", "XU;Andreas;Andyx;PRIEST;30;7200", "PARTY", "Andyx")
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Andreas;Andyx;PRIEST;30;100;Elwynn;3", "GUILD", "Andyx")
check(#ns.toastsSeen == nT + 1, "kun én level-toast pr. ding: " .. (#ns.toastsSeen - nT))
lt = ns.toastsSeen[#ns.toastsSeen]
check(lt.title == "Andreas nåede level 30" and lt.text:find("2 t") and lt.text:find("rundt tal"), "vens level-toast: " .. lt.text)
-- Gamle klienter uden XU: livstegnet giver stadig popup
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Andreas;Andyx;PRIEST;31;100;Elwynn;3", "GUILD", "Andyx")
check(#ns.toastsSeen == nT + 2 and ns.toastsSeen[#ns.toastsSeen].title == "Andreas nåede level 31", "level-toast fra livstegn")

-- Dueller
local w, l, fled = ns.ParseDuel("Mathiasx has defeated Nickchar in a duel")
check(w == "Mathiasx" and l == "Nickchar" and not fled, "knockout-tekst")
w, l, fled = ns.ParseDuel("Mathiasx has fled from Nickchar in a duel")
check(w == "Nickchar" and l == "Mathiasx" and fled, "flygte-tekst (nummererede felter)")
db.chars["Nickchar"] = "Nick"
SENT = {}
NOW = NOW + 10
Fire("CHAT_MSG_SYSTEM", "Mathiasx has defeated Nickchar in a duel")
NOW = NOW + 10
Fire("CHAT_MSG_SYSTEM", "Mathiasx has defeated Nickchar in a duel")
NOW = NOW + 10
Fire("CHAT_MSG_SYSTEM", "Mathiasx has fled from Nickchar in a duel")
NOW = NOW + 10
Fire("CHAT_MSG_SYSTEM", "Mathiasx has defeated Randomgnome in a duel")
Fire("CHAT_MSG_SYSTEM", "Frodex has defeated Randomgnome in a duel")
local st = ns.DuelStats("Mathias")
check(st.w == 3 and st.l == 1 and st.fw == 2 and st.fl == 1 and st.ow == 1 and st.fled == 1, "egne dueller tælles (ikke andres)")
check(st.opp.Nick.w == 2 and st.opp.Nick.l == 1 and st.opp.Randomgnome.w == 1, "mod hvem")
check(lastPrint():find("Randomgnome"), "chat ved duel: " .. lastPrint())
check(findSent("XD;Mathias;"), "XD sendes")
local w1, l1 = ns.DuelHeadToHead("Mathias", "Nick")
check(w1 == 2 and l1 == 1, "head-to-head")
-- Nick sender sin side af de samme dueller + en mod Jeppe
db.chars["Jeppex"] = "Jeppe"
nT = #ns.toastsSeen
Fire("CHAT_MSG_ADDON", "WCOAST", "XD;Nick;Nickchar-1-Mathiasx;Nickchar;Mathiasx;0;0;" .. NOW .. ";Elwynn", "GUILD", "Nickchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XD;Nick;Nickchar-2-Jeppex;Nickchar;Jeppex;1;0;" .. NOW .. ";Elwynn", "GUILD", "Nickchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XD;Nick;Nickchar-2-Jeppex;Nickchar;Jeppex;1;0;" .. NOW .. ";Elwynn", "PARTY", "Nickchar")
check(#ns.toastsSeen == nT + 1 and ns.toastsSeen[#ns.toastsSeen].title == "Nick slog Jeppe", "duel-toast mellem venner (ikke når jeg var med)")
check(ns.DuelStats("Nick").w == 1 and ns.DuelStats("Nick").l == 1, "vens dueller, uden dubletter")
check(ns.DuelStats("Mathias").w == 3, "vennens kopi tæller ikke dobbelt hos mig")
ns.ShowTab(14)
SENT = {}
ns.SendMyExtras()
check(findSent("XD;Mathias;"), "synk sender dueller")

-- Daglig sladder: bygges af de data, der allerede er, og sender intet
SENT = {}
local gl = ns.GossipLines(0)
local all = table.concat(ns.GossipLines(0, nil, nil, 99), "\n")
local perFriend = {}
for _, l in ipairs(gl) do if l:find("^Du ") then perFriend.me = (perFriend.me or 0) + 1 end end
check((perFriend.me or 0) <= 3, "højst 3 linjer om samme ven")
check(#gl > 0 and #gl <= 10, "sladder har linjer: " .. #gl)
check(all:find("Need%-politiet"), "need-politiet i sladderen: " .. all)
check(all:find("vandt %d+ duel"), "dueller i sladderen: " .. all)
check(all:find("ihjel") or all:find("døde"), "dødsfald i sladderen: " .. all)
check(not all:find("{") and not all:find("%%[sd]"), "ingen tomme felter")
check(#ns.GossipLines(NOW + 10) == 0, "intet nyt = ingen sladder")
SlashCmdList.WASTEDCOAST("sladder")
check(_G.WastedCoastGossip and _G.WastedCoastGossip:IsShown(), "sladder-vinduet vises")
pump()
check(#SENT == 0, "sladder sender ingen beskeder")
Fire("PLAYER_LOGOUT")
check(db.gossip.out == NOW and db.gossip.snap.Frode, "logout gemmer tid og levels")
local snap = {}
for k, v in pairs(db.gossip.snap) do snap[k] = v end
local rl = snap.Frode
NOW = NOW + 3600
Fire("CHAT_MSG_ADDON", "WCOAST", "H;Frode;Frodex;ROGUE;" .. (rl + 3) .. ";100;Nagrand;3", "GUILD", "Frodex")
local gl2 = table.concat(ns.GossipLines(NOW - 100, snap), "\n")
check(gl2:find("Frode") and gl2:find("3 levels"), "level-hop siden sidst: " .. gl2)
SlashCmdList.WASTEDCOAST("sladder fra")
check(db.settings.gossip == false, "sladder ved login fra")
SlashCmdList.WASTEDCOAST("sladder til")
check(db.settings.gossip == true, "sladder ved login til")
-- første login på en ny dato viser sladderen, næste login samme dag gør ikke
_G.WastedCoastGossip:Hide()
db.gossip.day = nil
Fire("PLAYER_LOGIN") RunTimers()
check(_G.WastedCoastGossip:IsShown() and db.gossip.day == date("%Y-%m-%d", NOW), "sladder ved første login på dagen")
_G.WastedCoastGossip:Hide()
NOW = NOW + 60
Fire("PLAYER_LOGIN") RunTimers()
check(not _G.WastedCoastGossip:IsShown(), "ikke igen samme dag")
NOW = NOW + 86400
Fire("PLAYER_LOGIN") RunTimers()
check(_G.WastedCoastGossip:IsShown(), "igen næste dag")
_G.WastedCoastGossip:Hide()

-- v0.19: mere "siden sidst" (loot, rare mobs, professions, rep, gear, spilletid, instanser, rolls, legacy)
do
    local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
    db.friends.Frode = db.friends.Frode or { chars = {} }
    db.friends.Frode.chars.Frodex = db.friends.Frode.chars.Frodex or {}
    local fc = db.friends.Frode.chars.Frodex
    fc.class, fc.level, fc.seen, fc.demo = "ROGUE", 70, NOW - 1000, nil
    fc.prof = "Alchemy=370/375,Mining=200/375"
    fc.rep = { ["Cenarion Expedition"] = "6:100:12000", ["Lower City"] = "5:0:6000" }
    fc.gear = { il = 100, me = "", mg = 0, t = NOW }
    fc.played = { t = 3600, l = 100, at = NOW - 1000 }
    db.runs.Frode = { Karazhan = { clears = 1, wipes = 0, boss = { Attumen = 1 }, last = NOW } }
    db.rolls.Frode = { rolls = 10, wins = 2, sum = 0, cnt = 0 }
    db.legacy.Frode = { p = 10, c = 1, t = NOW }
    db.friends.Jeppe = db.friends.Jeppe or { chars = {} }
    db.friends.Jeppe.chars.Jeppex = { class = "MAGE", level = 70, seen = NOW - 5000, rep = { ["Lower City"] = "5:0:6000" } }
    local st0 = copy(ns.GossipStats())
    check(st0.Frode and st0.Frode.prof.Alchemy == 370 and st0.Frode.rep["Cenarion Expedition"] == 6 and st0.Frode.il == 100, "øjebliksbillede af stats")
    check(st0.Frode.runs.Karazhan.c == 1 and st0.Frode.runs.Karazhan.b == 1 and st0.Frode.played == 3600, "øjebliksbillede af instanser og spilletid")
    local since = NOW
    NOW = NOW + 7200
    fc.prof = "Alchemy=375/375,Mining=230/375,Herbalism=1/375"
    fc.rep = { ["Cenarion Expedition"] = "8:0:999", ["Lower City"] = "7:0:21000" }
    db.friends.Jeppe.chars.Jeppex.rep = { ["Lower City"] = "5:0:6000", ["Sporeggar"] = "7:0:21000" }
    fc.gear.il = 105.5
    fc.played = { t = 3600 + 9 * 3600, l = 100, at = NOW - 1000 }
    fc.seen = NOW - 1000
    db.runs.Frode.Karazhan = { clears = 3, wipes = 4, boss = { Attumen = 3, Moroes = 2 }, last = NOW }
    db.rolls.Frode = { rolls = 16, wins = 2, sum = 0, cnt = 0 }
    db.legacy.Frode = { p = 25, c = 3, t = NOW }
    db.chars.Nickchar = "Nick"
    table.insert(db.loot, { id = "g-1", friend = "Frode", char = "Frodex", class = "ROGUE", quality = 5, item = "item:19019", name = "Thunderfury", zone = "Molten Core", time = NOW - 60, how = "need" })
    for i = 1, 3 do
        table.insert(db.loot, { id = "g-r" .. i, friend = "Nick", char = "Nickchar", class = "WARRIOR", quality = 3, item = "item:" .. (100 + i), name = "Blå ting " .. i, zone = "Nagrand", time = NOW - 100 + i, how = "need" })
    end
    table.insert(db.loot, { id = "g-j", friend = "Jeppe", char = "Jeppex", class = "MAGE", quality = 3, item = "item:200", name = "Jeppes stav", zone = "Zangarmarsh", time = NOW - 50, how = "greed" })
    db.rareLog = { { friend = "Jeppe", mob = "Old Gobblegut", lvl = 30, cls = "rare", zone = "Hillsbrad", t = since - 10 },
                   { friend = "Jeppe", mob = "Marticar", lvl = 64, cls = "rare", zone = "Nagrand", t = NOW - 30 },
                   { friend = "Nick", mob = "Voidhunter Yar", lvl = 66, cls = "rareelite", zone = "Netherstorm", t = NOW - 20 },
                   { friend = "Nick", mob = "Ever-Core", lvl = 70, cls = "rareelite", zone = "Netherstorm", t = NOW - 10 } }
    local lines = ns.GossipLines(since, {}, st0, 99)
    local txt = table.concat(lines, "\n")
    check(txt:find("LEGENDARY") and txt:find("Thunderfury"), "legendary loot: " .. txt)
    check(txt:find("samlede 3 rare items op, bl.a.") and txt:find("Blå ting 3"), "rare-optælling med nyeste eksempel")
    check(txt:find("scorede") and txt:find("Jeppes stav"), "enkelt rare item med navn")
    check(txt:find("vandt 3 need%-rolls"), "need-goblin")
    check(txt:find("nedlagde det sjældne mob") and txt:find("Marticar") and not txt:find("Old Gobblegut"), "rare mob siden sidst (ikke ældre)")
    check(txt:find("nedlagde 2 sjældne mobs, senest") and txt:find("Ever%-Core"), "flere rare mobs")
    check(txt:find("har maxet") and txt:find("Alchemy") and txt:find("375"), "maxet profession")
    check(txt:find("skillede Mining fra 200 til 230"), "profession-fremgang")
    check(not txt:find("Herbalism"), "ny profession på level 1 er ikke sladder")
    check(txt:find("Exalted") and txt:find("Cenarion Expedition"), "exalted")
    check(not txt:find("Lower City"), "kun bedste rep pr. ven")
    check(txt:find("nåede Revered med Sporeggar"), "ny fraktion tæller fra neutral")
    check(txt:find("5%.5 item levels") and txt:find("105%.5"), "item level op")
    check(txt:find("har spillet") and txt:find("9 timer"), "spilletid siden sidst")
    check(txt:find("klarede Karazhan 2 gange og dræbte 4 bosser"), "instanser: " .. txt)
    check(txt:find("wipede") and txt:find("4 gange"), "wipes")
    check(txt:find("rullede 6 gange og vandt ingenting"), "uheldige rolls")
    check(txt:find("tjente 15 legacy points og klarede 2 challenges"), "legacy points")
    check(not txt:find("{") and not txt:find("%%[sd]") and not txt:find("nil"), "ingen tomme felter: " .. txt)
    local short = ns.GossipLines(since, {}, st0)
    check(#short == 10 and short[1]:find("LEGENDARY"), "højst 10 linjer, legendary øverst")
    -- intet nyt, når øjebliksbilledet er det samme som nu
    local stNow = copy(ns.GossipStats())
    local again = table.concat(ns.GossipLines(NOW, {}, stNow, 99), "\n")
    check(not again:find("maxet") and not again:find("Exalted") and not again:find("item levels") and not again:find("wipede"), "ingen gentagelser: " .. again)
    -- login gemmer det gamle billede til sammenligning og måler på ny
    db.gossip.st = copy(st0)
    db.gossip.day = date("%Y-%m-%d", NOW)
    Fire("PLAYER_LOGIN") RunTimers()
    check(db.gossip.st.Frode and db.gossip.st.Frode.il == 105.5, "nyt øjebliksbillede efter login")
    local afterLogin = table.concat(ns.GossipLines(since, {}, nil, 99), "\n")
    check(afterLogin:find("Exalted"), "sessionen sammenligner med billedet fra før login")
    -- navneskift flytter rare mob-loggen med
    check(db.rareLog[#db.rareLog].friend == "Nick", "rare-log har ven")
    -- rare mob dræbt af en ven havner i loggen
    local n0 = #db.rareLog
    Fire("CHAT_MSG_ADDON", "WCOAST", "RM;Andreas;Andreasx;HUNTER;Doomsayer Jurim;68;rare;Shadowmoon Valley;" .. NOW .. ";Creature-x-9", "GUILD", "Andreasx")
    check(#db.rareLog == n0 + 1 and db.rareLog[#db.rareLog].mob == "Doomsayer Jurim", "vens rare mob logges")
end

SlashCmdList.WASTEDCOAST("reset ja")
check(#db.needShame == 0, "reset sletter need-synder")
check(db.rareLog == nil, "reset sletter rare mob-loggen")
check(next(db.duels) == nil, "reset sletter dueller")
ns.ShowTab(13)
ns.ShowTab(14)

-- =============================================================================
-- Grupper: navn, kode, nye medlemmer, omdøbning, admin fjerner, snyd afvises
-- =============================================================================
check(db.group == nil and db.me == nil and #ns.core.ROSTER == 0, "efter reset: ingen gruppe")
check(ns.CleanMemberName("  Sø;ren|x  ") == "Sørenx", "navn renses for ; og |")
local long = ns.CleanMemberName(string.rep("ø", 20))
check(#long <= 24 and #long % 2 == 0, "langt navn klippes uden at dele et ø")
check(ns.ParseGroupCode("wc-wasted-coast").legacy, "den gamle gruppes kode")
check(ns.ParseGroupCode("nonsens") == nil, "ugyldig kode afvises")
check(not ns.CreateGroup(), "kan ikke oprette uden navn")
check(ns.SetMyName("Mads"), "navn gemt")
SENT = {}
check(ns.CreateGroup(), "gruppe oprettet")
local g = db.group
local me = db.me
check(me:match("^u%w+$") and #me == 9, "unikt ID: " .. tostring(me))
check(g.admin == me and ns.IsGroupAdmin(), "opretteren er admin")
check(g.code:match("^WC%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w$"), "kode-format: " .. g.code)
local parsed = ns.ParseGroupCode(" " .. g.code:lower() .. " ")
check(parsed and parsed.id == g.id and parsed.admin == me, "koden indeholder gruppe og admin")
check(ns.route.CHANNEL == "WCg" .. g.id, "egen skjult kanal")
check(#ns.core.ROSTER == 1 and ns.core.ROSTER[1] == me, "kun mig i gruppen")
check(findSent("GM;" .. me .. ";" .. g.id .. ";" .. me .. ";Mads;"), "melder mig selv")
check(ns.core.Name(me) == "Mads", "mit navn vises")

-- En ven melder sig ind
local bob = "uBBBBBBBB"
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", bob, g.id, bob, "Bob", NOW, NOW }, ";"), "CHANNEL", "Bobchar")
check(ns.core.ROSTER_SET[bob] and #ns.core.ROSTER == 2, "Bob er med")
check(lastPrint():find("Bob") and lastPrint():find("kommet med"), "besked om nyt medlem: " .. lastPrint())
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. bob .. ";Bobchar;MAGE;12;100;Goldshire;10", "CHANNEL", "Bobchar")
check(db.friends[bob] and db.friends[bob].chars.Bobchar, "Bobs livstegn gemmes")
check(g.owners.Bobchar == bob, "Bobchar hører til Bob")
ns.frame:Show()
ns.ShowTab(1)
local bobCard
for _, c in ipairs(ns.cards) do if c.friend == bob then bobCard = c end end
check(bobCard and bobCard.name.text_:find("Bob") and not bobCard.name.text_:find(bob), "kortet viser navnet, ikke ID'et")
check(ns.cards[3].shown == false, "tomme kort skjules")
for i = 1, #ns.pages do ns.ShowTab(i) end

-- Fremmede kan ikke melde andre ind, og andre gruppers beskeder ignoreres
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", "uCCCCCCCC", g.id, "uDDDDDDDD", "Snyder", NOW, NOW }, ";"), "GUILD", "Snyder")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", "uEEEEEEEE", "ANDENGRP", "uEEEEEEEE", "Fremmed", NOW, NOW }, ";"), "GUILD", "Fremmed")
check(#ns.core.ROSTER == 2, "snyd og andre grupper ignoreres")
SENT = {}
Fire("CHAT_MSG_ADDON", "WCOAST", "H;uFFFFFFFF;Ukendt;MAGE;12;100;Goldshire;10", "GUILD", "Ukendt")
check(findSent("GW;" .. me .. ";" .. g.id), "ukendt medlem: spørg hvem der er med")
check(not db.friends.uFFFFFFFF, "ukendte gemmes ikke")

-- Omdøbning
NOW = NOW + 5
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", bob, g.id, bob, "Bobby", NOW, NOW - 5 }, ";"), "CHANNEL", "Bobchar")
check(ns.core.Name(bob) == "Bobby", "Bob hedder nu Bobby")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", bob, g.id, bob, "Gammel", NOW - 100, NOW - 5 }, ";"), "CHANNEL", "Bobchar")
check(ns.core.Name(bob) == "Bobby", "ældre navn vinder ikke")
SENT = {}
ns.SetMyName("Mads Mikkelsen")
check(ns.core.Name(me) == "Mads Mikkelsen" and findSent("GM;" .. me .. ";" .. g.id .. ";" .. me .. ";Mads Mikkelsen;"), "mit nye navn sendes")

-- Admin fjerner Bob
SENT = {}
ns.ShowGroupWindow()
ns.KickMember(bob, true)
check(not ns.core.ROSTER_SET[bob] and #ns.core.ROSTER == 1, "Bob er fjernet")
check(findSent("GK;" .. me .. ";" .. g.id .. ";" .. bob .. ";"), "fjernelsen sendes")
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. bob .. ";Bobchar;MAGE;13;100;Goldshire;10", "CHANNEL", "Bobchar")
check(db.friends[bob].chars.Bobchar.level == 12, "fjernede medlemmer ignoreres")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", bob, g.id, bob, "Bob", NOW + 50, NOW }, ";"), "CHANNEL", "Bobchar")
check(not ns.core.ROSTER_SET[bob], "fjernet medlem kan ikke melde sig ind igen")
SENT = {}
ns.SendGroupInfo(true)
check(findSent("GK;" .. me .. ";" .. g.id .. ";" .. bob .. ";"), "admin gentager fjernelser ved synk")
NOW = NOW + 5
ns.KickMember(bob, false)
check(ns.core.ROSTER_SET[bob], "Bob er taget ind igen")
ns.RefreshGroupWindow()

-- v0.17: plads til 10 medlemmer (kort, rækker, knapper, dueller og guldgraf)
check(ns.MAX_MEMBERS == 10, "max 10 medlemmer")
local extra = {}
for i = 1, 8 do
  local id = "uX" .. ("ABCDEFGH"):sub(i, i) .. "XXXXXX"
  extra[i] = id
  Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", id, g.id, id, "Ven" .. i, NOW, NOW }, ";"), "CHANNEL", "Ven" .. i .. "char")
  Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. id .. ";Ven" .. i .. "char;MAGE;" .. (10 + i) .. ";100;Goldshire;10", "CHANNEL", "Ven" .. i .. "char")
end
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. bob .. ";Bobchar;MAGE;12;100;Goldshire;10", "CHANNEL", "Bobchar")
check(#ns.core.ROSTER == 10 and (ns.groupOverflow or 0) == 0, "10 medlemmer vises, ingen overløb: " .. table.concat(ns.core.ROSTER, ","))
for i = 1, #ns.pages do ns.ShowTab(i) end
ns.ShowTab(1)
check(#ns.cards == 10, "10 kort")
check(ns.cards[1].narrow and ns.cards[1].w * 5 + 4 * 12 <= 732, "over 8 online: fem smalle kort pr. række")
-- Den 11. vises ikke, men jeg er altid med
local nr11 = "uYYYYYYYY"
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", nr11, g.id, nr11, "Elleve", NOW, NOW }, ";"), "CHANNEL", "Ellevechar")
check(#ns.core.ROSTER == 10 and ns.groupOverflow == 1 and ns.core.ROSTER_SET[me], "11. medlem giver overløb, jeg er stadig med")
for i = 1, #ns.pages do ns.ShowTab(i) end
NOW = NOW + 5
for _, id in ipairs(extra) do ns.KickMember(id, true) end
ns.KickMember(nr11, true)
check(#ns.core.ROSTER == 2, "tilbage til mig og Bob")
ns.ShowTab(1)
check(not ns.cards[1].narrow, "store kort igen med få online")

-- Som almindeligt medlem i en andens gruppe
ns.LeaveGroup()
check(db.group == nil and db.me == nil and #ns.core.ROSTER == 0, "har forladt gruppen")
local admin = "uAAAAAAAA"
local code = "WC-GRPK-EY23-AAAA-AAAA"
check(ns.JoinGroup(code), "deltager med kode")
g = db.group
check(db.me == me and g.admin == admin and g.id == "GRPKEY23", "samme ID, admin fra koden")
check(ns.route.CHANNEL == "WCgGRPKEY23", "gruppens kanal")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", admin, g.id, admin, "Anne", NOW, NOW - 100 }, ";"), "CHANNEL", "Annechar")
check(ns.core.ROSTER[1] == admin and ns.core.Name(admin) == "Anne", "admin dukker op først")
check(ns.GroupName() == "Annes gruppe", "gruppens navn")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GM", bob, g.id, bob, "Bob", NOW, NOW }, ";"), "CHANNEL", "Bobchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. bob .. ";Bobchar;MAGE;12;100;Goldshire;10", "CHANNEL", "Bobchar")
-- Bob udgiver sig for at være admin og fjerner mig: afvises
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GK", admin, g.id, me, NOW, 1 }, ";"), "CHANNEL", "Bobchar")
check(db.group and db.me == me, "falsk admin afvises")
-- Et livstegn fra admins karakter, der påstår at være en anden, giver ikke admin-rettigheder
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. admin .. ";Annechar;PRIEST;20;100;Goldshire;10", "CHANNEL", "Bobchar")
check(g.owners.Annechar == nil, "karakter bindes kun, når den selv sender")
Fire("CHAT_MSG_ADDON", "WCOAST", "H;" .. admin .. ";Annechar;PRIEST;20;100;Goldshire;10", "CHANNEL", "Annechar")
check(g.owners.Annechar == admin, "admins karakter genkendt")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GK", admin, g.id, bob, NOW, 1 }, ";"), "CHANNEL", "Annechar")
check(not ns.core.ROSTER_SET[bob], "admin fjerner Bob")
Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "GK", admin, g.id, me, NOW, 1 }, ";"), "CHANNEL", "Annechar")
check(db.group == nil and db.me == nil, "admin fjerner mig: jeg er ude")
check(lastPrint():find("fjernet"), "besked om at være fjernet: " .. lastPrint())

-- En af de oprindelige venner, der installerer forfra, får sit gamle ID igen
ns.SetMyName("nick")
check(ns.JoinGroup("WC-WASTED-COAST"), "deltager i Wasted Coast")
check(db.me == "Nick" and #ns.core.ROSTER == 8 and db.group.admin == "Mathias", "Nick med de 8 venner")
check(ns.route.CHANNEL == "WC4Lsync", "gamle kanal, så ældre versioner er med")
check(ns.GroupName() == "Wasted Coast", "gruppens navn")
for i = 1, #ns.pages do ns.ShowTab(i) end
return PASSES
'''
passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed")
