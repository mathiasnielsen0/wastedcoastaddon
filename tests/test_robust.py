# Robusthedstest: rettede fejl, skæve beskeder fra netværket og forskelle mellem klienterne.
# Kør: pip install lupa && python3 tests/test_robust.py WastedCoast [forever]
#   forever: som WoW Forever (interface 16xxx, ingen combat log og kun C_Item-udgaverne af item-API'et)
import sys, random, lupa.lua51 as L
from wowmock import MOCK, load_addon

ADDON = sys.argv[1]
FOREVER = len(sys.argv) > 2 and sys.argv[2] == "forever"
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
if FOREVER:
    # Den moderne motor: de gamle globale item-funktioner er væk, kun C_Item findes
    lua.execute('''
function GetBuildInfo() return "1.60.0", "1", "", 16001 end
C_Item = {
  GetItemInfo = GetItemInfo, IsEquippableItem = IsEquippableItem, IsEquippedItem = IsEquippedItem,
  GetItemCount = GetItemCount, GetItemIconByID = GetItemIcon,
}
GetItemInfo, IsEquippableItem, IsEquippedItem, GetItemCount, GetItemIcon = nil, nil, nil, nil, nil
''')
lua.execute('BASE_GLOBALS = {} for k in pairs(_G) do BASE_GLOBALS[k] = true end')

ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns, FOREVER = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function findSent(prefix) pump() for i = #SENT, 1, -1 do if SENT[i].msg:sub(1, #prefix) == prefix then return SENT[i].msg end end end
local function msg(m, ch, sender) Fire("CHAT_MSG_ADDON", "WCOAST", m, ch or "GUILD", sender or "Nickchar") end
local toasts = {}
local function toastSince(n, kind) for i = n + 1, #toasts do if toasts[i].kind == kind then return toasts[i] end end end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
local realToast = ns.Toast
ns.Toast = function(o) toasts[#toasts + 1] = o return realToast(o) end
check(ns.core.GAME.isForever == (FOREVER == true), "rigtig spilversion: " .. ns.core.GAME.label)
STARTED_LONG_AGO = true
CLOCK = CLOCK + 1000   -- forbi "lige logget ind", så toasts vises

-- -----------------------------------------------------------------------------
-- Ingen globale variabler slipper ud af addonet (ud over dem, spillet kræver)
-- -----------------------------------------------------------------------------
do
    local allowed = { WastedCoastDB = true, SLASH_WASTEDCOAST1 = true, SLASH_WASTEDCOAST2 = true, SLASH_WASTEDCOAST3 = true,
        WastedCoastFrame = true, WastedCoastChrome = true, WastedCoastGossip = true, WastedCoastGroup = true, WastedCoastMinimapButton = true,
        WastedCoastOptions = true, WastedCoastToast = true, ChatFrame_DisplayTimePlayed = true, STARTED_LONG_AGO = true,
        PASSES = true }
    local leaked = {}
    for k in pairs(_G) do if not BASE_GLOBALS[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end end
    check(#leaked == 0, "ingen globale variabler slipper ud: " .. table.concat(leaked, ", "))
end

-- -----------------------------------------------------------------------------
-- Migrering af gamle SavedVariables (v0.2: ven-felter direkte på vennen)
-- -----------------------------------------------------------------------------
do
    local saved = WastedCoastDB
    WastedCoastDB = { friends = { Nick = { char = "Oldnick", class = "MAGE", level = 33, gold = 5, zone = "Duskwood", seen = 100 } },
                      settings = { minQuality = 4 }, ratings = { x = 1 } }
    Fire("ADDON_LOADED", "WastedCoast")
    local m = WastedCoastDB
    check(m.friends.Nick.chars.Oldnick and m.friends.Nick.chars.Oldnick.level == 33 and m.friends.Nick.char == nil,
          "v0.2-felter flyttes ind under karakterer")
    check(m.ratings == nil and m.schemaVersion and m.settings.minQuality == 3 and m.settings.qualityV2,
          "gamle ratings fjernes, og loot-grænsen flyttes til rare")
    check(m.settings.lootToasts == true and m.settings.rareToasts == true and m.settings.announce == true,
          "nye indstillinger får standardværdier")
    m.settings.minQuality = 4
    Fire("ADDON_LOADED", "WastedCoast")
    check(WastedCoastDB.settings.minQuality == 4, "et bevidst valg af loot-grænse bevares ved næste login")
    WastedCoastDB = saved
    Fire("ADDON_LOADED", "WastedCoast")
    db = WastedCoastDB
    check(db.me == "Mathias" and #ns.core.ROSTER == 8, "tilbage til de rigtige data")
end

-- -----------------------------------------------------------------------------
-- Livstegn (H) og karakterer (C)
-- -----------------------------------------------------------------------------
do
    -- Fejl rettet: et livstegn uden karakternavn fra en ukendt ven gav en Lua-fejl
    local ok, err = pcall(msg, "H;Rasmus;;MAGE;10;1;Z;1;;5")
    check(ok, "livstegn uden karakter giver ingen fejl: " .. tostring(err))
    check(not (db.friends.Rasmus and db.friends.Rasmus.session), "livstegn uden karakter ignoreres")

    msg("H;Rasmus;Rasmuschar;HUNTER;22;5000;Westfall;40;;7", "GUILD", "Rasmuschar")
    local c = db.friends.Rasmus.chars.Rasmuschar
    check(c.level == 22 and c.xp == 40 and c.class == "HUNTER" and db.friends.Rasmus.session == 7, "livstegn gemmes")
    check(ns.core.IsOnline("Rasmus"), "ven er online lige efter et livstegn")
    NOW = NOW + 151
    check(ns.core.IsOnline("Rasmus"), "to mistede livstegn: stadig online (v0.18.5)")
    NOW = NOW + 180
    check(not ns.core.IsOnline("Rasmus"), "offline efter 5½ minut uden livstegn")
    msg("H;Rasmus;Rasmuschar;HUNTER;0;5000;Westfall;40;;7", "GUILD", "Rasmuschar")
    check(c.level == 22, "level 0 overskriver ikke et kendt level")

    -- Fejl rettet: en karakter med "sidst set" i fremtiden (vennens ur går forkert) viste vennen online for længe
    msg("C;Søren;Sorenalt;PRIEST;12;10;Elwynn;" .. (NOW + 3600) .. ";5", "GUILD", "Sorenchar")
    local alt = db.friends["Søren"].chars.Sorenalt
    check(alt.level == 12 and alt.seen <= NOW, "sidst set i fremtiden klippes til nu: " .. tostring(alt.seen - NOW))
    NOW = NOW + 200
    check(not ns.core.IsOnline("Søren"), "vennen med forkert ur er ikke online i en time")
    msg("C;Søren;Sorenalt;PRIEST;12;10;Elwynn;0;5", "GUILD", "Sorenchar")
    check(alt.seen <= NOW, "sidst set 0 ødelægger ikke tidspunktet")

    -- Beskeder fra spillere uden for gruppen gemmes ikke
    msg("H;Fremmed;Fremmedchar;MAGE;10;1;Z;1", "GUILD", "Fremmedchar")
    check(db.friends.Fremmed == nil and db.chars.Fremmedchar == nil, "fremmede gemmes ikke")
end

-- -----------------------------------------------------------------------------
-- "Er online"-toast og level-toast fra livstegn
-- -----------------------------------------------------------------------------
do
    check(ns.CameOnline(nil, nil, nil) == true, "aldrig set: kom online")
    check(ns.CameOnline(nil, 3, 599) == false and ns.CameOnline(3, nil, 700) == true, "uden begge sessioner afgør hullet")
    local n = #toasts
    db.friends.Andreas = nil
    msg("H;Andreas;Andychar;ROGUE;29;1;Westfall;90;;100", "GUILD", "Andychar")
    check(#toasts == n + 1 and toasts[#toasts].kind == "online", "første livstegn: online-toast")
    NOW = NOW + 60
    msg("H;Andreas;Andychar;ROGUE;30;1;Westfall;0;;100", "GUILD", "Andychar")
    check(#toasts == n + 2 and toasts[#toasts].kind == "levelup" and toasts[#toasts].title:find("30"), "level-up i livstegnet giver level-toast")
    NOW = NOW + 60
    msg("H;Andreas;Andychar;ROGUE;30;1;Westfall;5;;100", "GUILD", "Andychar")
    check(#toasts == n + 2, "samme level igen: ingen ny toast")
    NOW = NOW + 60
    msg("H;Andreas;Andychar;ROGUE;33;1;Westfall;5;;100", "GUILD", "Andychar")
    check(#toasts == n + 2, "hop på flere levels (fx efter en pause) giver ingen level-toast")
end

-- -----------------------------------------------------------------------------
-- Dødsfald: miljø i combat loggen, uanset store/små bogstaver (kun hvor combat loggen findes)
-- -----------------------------------------------------------------------------
check(ns.EnvName("Falling") == "Faldskade" and ns.EnvName("FALLING") == "Faldskade" and ns.EnvName("lava") == "Lava",
      "miljøtyper genkendes med store og små bogstaver")
check(ns.EnvName("Weird") == "Weird" and ns.EnvName(nil) == "", "ukendte miljøtyper vises som de er")
if not FOREVER then
    SENT = {}
    CLOCK = CLOCK + 100
    NOW = NOW + 100
    CombatLogGetCurrentEventInfo = function() return 0, "ENVIRONMENTAL_DAMAGE", nil, nil, nil, nil, nil, "guid", PLAYER, nil, nil, "FALLING", 500 end
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    Fire("PLAYER_DEAD")
    local ev = db.events[#db.events]
    check(ev.killer == "Omgivelserne" and ev.ability == "Faldskade" and not ev.pvp, "FALLING fra combat loggen er faldskade: " .. tostring(ev.ability))
    local d = findSent("D;")
    check(d and d:find(";Omgivelserne;Faldskade;"), "faldskaden sendes")
    -- PvP via kildens flag (COMBATLOG_OBJECT_CONTROL_PLAYER), og egen skade er ikke PvP
    CLOCK = CLOCK + 100
    NOW = NOW + 100
    CombatLogGetCurrentEventInfo = function() return 0, "SPELL_DAMAGE", nil, "Player-1-AAA", "Gankeren", 0x548, nil, "guid", PLAYER, nil, nil, 133, "Fireball" end
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    Fire("PLAYER_DEAD")
    ev = db.events[#db.events]
    check(ev.killer == "Gankeren" and ev.ability == "Fireball" and ev.pvp == true, "spiller med kontrol-flag er PvP")
    CLOCK = CLOCK + 100
    NOW = NOW + 100
    CombatLogGetCurrentEventInfo = function() return 0, "SPELL_PERIODIC_DAMAGE", nil, "guid", PLAYER, 0x511, nil, "guid", PLAYER, nil, nil, 1, "Hellfire" end
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    Fire("PLAYER_DEAD")
    ev = db.events[#db.events]
    check(ev.killer == PLAYER and not ev.pvp, "egen skade er ikke PvP")
    CombatLogGetCurrentEventInfo = nil
end

-- Samme dødsfald via to kanaler tælles én gang, og et gammelt dødsfald giver ingen toast
do
    local nEv, nT = #db.events, #toasts
    local line = table.concat({ "D", "Jeppex-" .. NOW, "Jeppex", "PALADIN", "Hogger", "Nærkamp", 11, "Elwynn", NOW, "Jeppe", 11 }, ";")
    msg(line, "GUILD", "Jeppex")
    msg(line, "CHANNEL", "Jeppex")
    check(#db.events == nEv + 1 and #toasts == nT + 1, "samme dødsfald via to kanaler: én gang")
    msg(table.concat({ "D", "Jeppex-old", "Jeppex", "PALADIN", "Hogger", "Nærkamp", 11, "Elwynn", NOW - 86400, "Jeppe" }, ";"), "GUILD", "Jeppex")
    check(#db.events == nEv + 2 and #toasts == nT + 1, "gammelt dødsfald fra synk: gemt, men ingen toast")
    msg("D;kort;besked", "GUILD", "Jeppex")
    check(#db.events == nEv + 2, "for kort dødsbesked ignoreres")
end

-- -----------------------------------------------------------------------------
-- Loot: links i den nye farve-form (|cnIQ4:) og for lange beskeder
-- -----------------------------------------------------------------------------
do
    SENT = {}
    local n, nT = #db.loot, #toasts
    NOW = NOW + 10
    Fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ4:|Hitem:31000::::::::70:::::|h[New Style Epic]|h|r.")
    RunTimers()
    local ev = db.loot[#db.loot]
    check(#db.loot == n + 1 and ev.quality == 4 and ev.name == "New Style Epic", "link med |cnIQ4: giver epic loot")
    check(toastSince(nT, "epicloot"), "epic-toast for link i ny form")

    -- Et link med mange bonus-ID'er: beskeden holdes under 255 tegn, og item-ID'et kommer frem
    SENT = {}
    local bonus = {}
    for i = 1, 40 do bonus[#bonus + 1] = tostring(10000 + i) end
    local longItem = "item:31001::::::::70:::::40:" .. table.concat(bonus, ":")
    NOW = NOW + 10
    Fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|H" .. longItem .. "|h[An Epic With A Rather Long Name Indeed]|h|r.")
    RunTimers() RunTimers() RunTimers()
    check(#TIMERS < 50, "timere kører: " .. #TIMERS)
    local l = findSent("L;L-" .. PLAYER .. "-" .. NOW .. "-31001-")
    check(l and #l <= 255 and l:find(";item:31001;"), "for lang loot-besked sendes med kun item-ID: " .. tostring(l))
    -- Og den kommer frem hos en anden som en gyldig loot-besked
    local saved = db.lootSeen[db.loot[#db.loot].id]
    db.lootSeen[db.loot[#db.loot].id] = nil
    table.remove(db.loot)
    msg(l, "GUILD", PLAYER)
    check(db.loot[#db.loot].item == "item:31001" and db.loot[#db.loot].quality == 4, "den forkortede loot-besked kan læses")

    -- Generelt: en besked over 255 tegn sendes slet ikke (spillet ville give en fejl)
    SENT = {}
    local dropped = ns.route.stats.dropped
    ns.core.Send("X;" .. string.rep("a", 300))
    pump()
    check(#SENT == 0 and ns.route.stats.dropped == dropped + 1, "for lange beskeder droppes")

    -- Grønt loot under grænsen gemmes ikke
    n = #db.loot
    Fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:31002::::::::70:::::|h[Green]|h|r.")
    RunTimers()
    check(#db.loot == n, "grønt loot gemmes ikke med rare-grænse")
end

-- -----------------------------------------------------------------------------
-- Need-politiet virker også med kun C_Item (Forever)
-- -----------------------------------------------------------------------------
do
    ITEMS[32000] = { equip = true, count = 1, equipped = false }
    db.needWatch = {}
    ns.WatchNeed({ id = 32000, itemString = "item:32000", name = "Shiny", quality = 4 })
    local key = next(db.needWatch)
    check(key ~= nil, "needet item kommer under opsyn")
    ITEMS[32000].equipped = true
    ns.CheckNeeds()
    check(next(db.needWatch) == nil, "taget på: frikendt (også uden de globale item-funktioner)")
    ITEMS[32001] = { equip = false, count = 1 }
    ns.WatchNeed({ id = 32001, itemString = "item:32001", name = "Recipe", quality = 3 })
    check(next(db.needWatch) == nil, "ting, der ikke kan tages på, tælles ikke")
end

-- -----------------------------------------------------------------------------
-- Guild bank: "målt siden" og tingenes værdi
-- -----------------------------------------------------------------------------
do
    db.bank = {}
    -- Fejl rettet: "since" lå i felt 16, men blev læst fra felt 17
    local since = NOW - 30 * 86400
    msg(table.concat({ "BK", "Nick", NOW, 100, 200, 1, 2, 3, 4, 5, 6, 1, 5, "123:4", "456:7", since }, ";"), "GUILD", "Nickchar")
    local e = db.bank.Nick
    check(e and e.since == since, "målt siden kommer frem fra vennen: " .. tostring(e and e.since))
    check(e.dg == 100 and e.wg == 200 and e.maxrep == 5 and e.tw == "123:4" and e.td == "456:7", "alle bank-felter læses")
    check(ns.BankTopItem("Nick", "w") == 123, "vennens mest hævede ting")
    -- En ældre besked overskriver ikke en nyere
    msg(table.concat({ "BK", "Nick", NOW - 10, 999, 999, 1, 2, 3, 4, 5, 6, 1, 5, "", "", since }, ";"), "GUILD", "Nickchar")
    check(db.bank.Nick.dg == 100, "ældre bank-besked ignoreres")
    -- Egen besked kan læses af de andre (samme felter frem og tilbage)
    ns.RecordBankGold("d", 50000)
    SENT = {}
    ns.SendBank()
    local bk = findSent("BK;Mathias;")
    local parts = { strsplit(";", bk) }
    check(#parts == 16 and tonumber(parts[16]) == db.bank.Mathias.since, "egen BK-besked har since som felt 16")

    -- Fejl rettet: tingenes vendor-værdi brugte den globale GetItemInfo, som ikke findes på Forever
    local old = ns.core.GAME.ItemInfo
    ns.core.GAME.ItemInfo = function(id) if id == 33000 then return "Bar", nil, 2, nil, nil, nil, nil, nil, nil, nil, 250 end end
    local before = db.bank.Mathias.dv
    ns.RecordBankItem("d", 33000, 4)
    ns.core.GAME.ItemInfo = old
    check(db.bank.Mathias.dv == before + 1000, "vendor-værdi via GAME.ItemInfo: " .. tostring(db.bank.Mathias.dv - before))
end

-- -----------------------------------------------------------------------------
-- Dueller: to venner melder samme duel (hver sin side), og toasten vises kun én gang
-- -----------------------------------------------------------------------------
do
    db.chars.Jeppex = "Jeppe"
    db.chars.Nickchar = "Nick"
    local n = #toasts
    NOW = NOW + 30
    CLOCK = CLOCK + 30
    msg("XD;Nick;Nickchar-" .. NOW .. "-Jeppex;Nickchar;Jeppex;1;0;" .. NOW .. ";Elwynn", "GUILD", "Nickchar")
    msg("XD;Jeppe;Jeppex-" .. NOW .. "-Nickchar;Jeppex;Nickchar;0;0;" .. NOW .. ";Elwynn", "GUILD", "Jeppex")
    check(#toasts == n + 1 and toasts[#toasts].kind == "duel", "duel mellem to venner: én toast, ikke to (" .. (#toasts - n) .. ")")
    check(ns.DuelStats("Nick").w >= 1 and ns.DuelStats("Jeppe").l >= 1, "begge sider gemmes hos hver sin ven")
    -- En ny duel mellem dem lidt senere giver en ny toast
    NOW = NOW + 60
    CLOCK = CLOCK + 60
    msg("XD;Jeppe;Jeppex-" .. NOW .. "-Nickchar;Jeppex;Nickchar;1;0;" .. NOW .. ";Elwynn", "GUILD", "Jeppex")
    check(#toasts == n + 2 and toasts[#toasts].title:find("Jeppe slog Nick"), "ny duel: ny toast")
end

-- -----------------------------------------------------------------------------
-- Synk-veje: battleground-gruppen er ikke din egen gruppe
-- -----------------------------------------------------------------------------
do
    local oldRaid, oldGroup, oldGuild = IsInRaid, IsInGroup, IsInGuild
    LE_PARTY_CATEGORY_HOME = 1
    -- I en battleground uden eget party: IsInRaid() er sand, men kun for instans-gruppen
    IsInRaid = function(cat) return cat ~= 1 end
    IsInGroup = function(cat) return cat ~= 1 end
    IsInGuild = function() return false end
    ns.route.shared.Nick = { RAID = NOW }
    local kinds = {}
    for _, c in ipairs(ns.route.Targets()) do kinds[#kinds + 1] = c[1] end
    check(not table.concat(kinds, ","):find("RAID") and not table.concat(kinds, ","):find("PARTY"),
          "battleground-gruppen bruges ikke som RAID: " .. table.concat(kinds, ","))
    -- I eget raid: RAID
    IsInRaid = function() return true end
    IsInGroup = function() return true end
    kinds = {}
    for _, c in ipairs(ns.route.Targets()) do kinds[#kinds + 1] = c[1] end
    check(table.concat(kinds, ","):find("RAID"), "eget raid bruges: " .. table.concat(kinds, ","))
    IsInRaid, IsInGroup, IsInGuild, LE_PARTY_CATEGORY_HOME = oldRaid, oldGroup, oldGuild, nil
    ns.route.shared.Nick = nil
end

-- -----------------------------------------------------------------------------
-- Synk-svar: højst ét svar ad gangen, og den lette synk sender kun det seneste
-- -----------------------------------------------------------------------------
do
    for i = 1, 30 do
        table.insert(db.events, { id = "Mathiasx-hist" .. i, name = PLAYER, friend = "Mathias", killer = "Mob", ability = "",
                                  level = 30, zone = "Z", time = NOW - 100000 + i })
    end
    TIMERS = {}
    SENT = {}
    msg("Q;Nick;0;L", "GUILD", "Nickchar")
    msg("Q;Frode;0;L", "GUILD", "Frodex")
    check(#TIMERS == 1, "to forespørgsler på én gang giver ét svar")
    RunTimers()
    pump()
    local function deathsSent()
        local seen, n = {}, 0
        for _, s in ipairs(SENT) do
            if s.msg:sub(1, 2) == "D;" and not seen[s.msg] then seen[s.msg] = true n = n + 1 end
        end
        return n
    end
    local d = deathsSent()
    check(d == 10, "let synk: højst 10 dødsfald (" .. d .. ")")
    TIMERS = {}
    msg("Q;Nick;0;L", "GUILD", "Nickchar")
    check(#TIMERS == 0, "samme ven kan ikke bede om endnu en let synk med det samme")
    CLOCK = CLOCK + 120
    NOW = NOW + 130
    SENT = {}
    msg("Q;Frode", "GUILD", "Frodex")
    RunTimers()
    pump()
    d = deathsSent()
    check(d > 10 and d <= 60, "fuld synk sender historikken (" .. d .. ")")
    for i = #db.events, 1, -1 do if tostring(db.events[i].id):find("^Mathiasx%-hist") then table.remove(db.events, i) end end
end

-- -----------------------------------------------------------------------------
-- Ekstra-beskeder: kun den nyeste/største vinder
-- -----------------------------------------------------------------------------
do
    msg("LP;Frode;120;6;" .. NOW, "GUILD", "Frodex")
    msg("LP;Frode;80;4;" .. (NOW - 100), "GUILD", "Frodex")
    check(db.legacy.Frode.p == 120, "ældre legacy points ignoreres")
    msg("HP;Frode;Frodex;500;20;" .. NOW, "GUILD", "Frodex")
    msg("HP;Frode;Frodex;100;2;" .. (NOW - 100), "GUILD", "Frodex")
    check(db.friends.Frode.chars.Frodex.honor.h == 500, "ældre honor ignoreres")
    check(ns.HonorTotals("Frode") == 500, "honor lægges sammen pr. ven")
    msg("S;Frode;Karazhan;3;1;" .. NOW, "GUILD", "Frodex")
    msg("S;Frode;Karazhan;1;0;" .. NOW, "GUILD", "Frodex")
    check(db.runs.Frode.Karazhan.wipes == 3 and db.runs.Frode.Karazhan.clears == 1, "instans-tal vokser kun")
    msg("B;Frode;Karazhan;Attumen;4", "GUILD", "Frodex")
    msg("B;Frode;Karazhan;Attumen;2", "GUILD", "Frodex")
    check(db.runs.Frode.Karazhan.boss.Attumen == 4, "boss-tal vokser kun")
    msg("R;Frode;10;3;500;10;2;99", "GUILD", "Frodex")
    msg("R;Frode;5;1;100;2;5;50", "GUILD", "Frodex")
    check(db.rolls.Frode.rolls == 10 and db.rolls.Frode.high == 99, "roll-tal vokser kun")
    msg("PT;Frode;Frodex;7200;600;" .. NOW, "GUILD", "Frodex")
    msg("PT;Frode;Frodex;-5;0;" .. NOW, "GUILD", "Frodex")
    check(db.friends.Frode.chars.Frodex.played.t == 7200, "negativ spilletid ignoreres")
    msg("E;Frode;Frodex;1155;Head;3;" .. NOW, "GUILD", "Frodex")
    check(math.abs(db.friends.Frode.chars.Frodex.gear.il - 115.5) < 0.01, "item level sendes i tiendedele")
    msg("F;Frode;Frodex;Stormwind=5:3000,Darnassus=4:100", "GUILD", "Frodex")
    check(db.friends.Frode.chars.Frodex.rep.Stormwind == "5:3000", "reputation læses")
    msg("A;Frode;ikke_et_trofae;" .. NOW, "GUILD", "Frodex")
    check(not (db.ach.Frode and db.ach.Frode.ikke_et_trofae), "ukendte trofæer ignoreres")
    msg("W;Frode;Karazhan;" .. (NOW - 1000), "GUILD", "Frodex")
    check(toasts[#toasts].kind ~= "wipe", "gammelt wipe giver ingen toast")
end

-- -----------------------------------------------------------------------------
-- Gruppe-beskeder: kun admin kan fjerne, og kun fra sin egen karakter
-- -----------------------------------------------------------------------------
do
    local g = db.group
    msg(table.concat({ "GK", "Nick", g.id, "Frode", NOW, 1 }, ";"), "GUILD", "Nickchar")
    check(ns.core.ROSTER_SET.Frode, "kun admin kan fjerne et medlem")
    msg(table.concat({ "GM", "Nick", g.id, "Frode", "Frode;|cffHack", NOW + 1, 1 }, ";"), "GUILD", "Nickchar")
    check(not ns.core.Name("Frode"):find("|") and not ns.core.Name("Frode"):find(";"), "navne renses for farvekoder og ;")
end

-- -----------------------------------------------------------------------------
-- Samme ven med to ID'er (fx McAndze med både et gammelt og et nyt ID) vises kun én gang
-- -----------------------------------------------------------------------------
do
    local g = db.group
    local R, RS = ns.core.ROSTER, ns.core.ROSTER_SET
    local before = #R
    -- Det gamle ID: hverken set eller med data. Et dødsfald og en loot hænger på det.
    g.members.uMCANDZE2 = { n = "McAndze", nt = 1, j = 1 }
    db.events[#db.events + 1] = { id = "dup-death", friend = "uMCANDZE2", name = "Oldchar", time = NOW - 50 }
    db.runs.uMCANDZE2 = { Deadmines = { wipes = 2, clears = 1 } }
    ns.RebuildRoster()
    check(RS.uMCANDZE2 and #R == before + 1, "et nyt medlem kommer på listen")
    -- Det nye ID melder sig og sender livstegn
    msg(table.concat({ "GM", "uMCANDZE3", g.id, "uMCANDZE3", "mcandze", NOW, NOW }, ";"), "GUILD", "Murer")
    msg(table.concat({ "H", "uMCANDZE3", "Murer", "DRUID", "16", "0", "Stormwind City" }, ";"), "GUILD", "Murer")
    check(#R == before + 1, "samme navn (uanset store/små bogstaver) vises kun én gang: " .. #R)
    check(RS.uMCANDZE3 and not RS.uMCANDZE2, "det aktive ID vises, det gamle skjules")
    check(ns.memberAlias.uMCANDZE2 == "uMCANDZE3", "det gamle ID peger på det nye")
    check(db.events[#db.events].friend == "uMCANDZE3" and db.runs.uMCANDZE3 and db.runs.uMCANDZE2 == nil,
          "det gamle ID's data flyttes over til det nye")
    local n = 0
    for _, s in ipairs(ns.core.BuildStats()) do if s.disp == "McAndze" or s.disp == "mcandze" then n = n + 1 end end
    check(n == 1, "kortet viser McAndze én gang: " .. n)
    -- Logger han ind på det gamle ID igen, skifter visningen over (og data følger med)
    NOW = NOW + 10
    msg(table.concat({ "H", "uMCANDZE2", "Oldchar", "DRUID", "20", "0", "Darnassus" }, ";"), "GUILD", "Oldchar")
    check(RS.uMCANDZE2 and not RS.uMCANDZE3 and #R == before + 1, "det senest aktive ID vises")
    check(db.friends.uMCANDZE2 and db.friends.uMCANDZE2.chars.Murer and db.friends.uMCANDZE2.chars.Oldchar,
          "karaktererne følger med ved skiftet")
    -- Dig selv vinder altid over en dublet med dit navn
    g.members.uMEDUPLCX = { n = ns.core.Name(db.me), nt = 1, j = 1 }
    ns.RebuildRoster()
    check(RS[db.me] and not RS.uMEDUPLCX, "dit eget ID vises altid")
    g.members.uMEDUPLCX, g.members.uMCANDZE2, g.members.uMCANDZE3 = nil, nil, nil
    ns.RebuildRoster()
    check(#R == before, "tilbage til den normale gruppe")
end

-- -----------------------------------------------------------------------------
-- v0.18.1: online i guild-listen tæller, og livstegnet går også i guild, til vennen er hørt i kanalen
-- -----------------------------------------------------------------------------
do
    local route, C = ns.route, ns.core
    -- En kendt karakter, der ikke har sendt livstegn i lang tid
    db.friends.Nick = db.friends.Nick or { chars = {} }
    db.friends.Nick.chars = db.friends.Nick.chars or {}
    db.friends.Nick.chars.Nickchar = { level = 30, seen = NOW - 5000 }
    for cn, c in pairs(db.friends.Nick.chars) do c.seen = NOW - 5000 end
    db.chars.Nickchar = "Nick"
    check(not C.IsOnline("Nick"), "uden livstegn er vennen offline")
    local roster = { { "Nickchar-Realm", true }, { "Fremmed", true }, { "Frodex", false } }
    GetNumGuildMembers = function() return #roster end
    GetGuildRosterInfo = function(i) local r = roster[i] return r[1], "", 0, 30, "", "", "", "", r[2] end
    Fire("GUILD_ROSTER_UPDATE")
    check(C.IsOnline("Nick"), "online i guild-listen = online")
    check(not ns.guild.chars.Fremmed, "kun vennernes karakterer gemmes")
    roster[1][2] = false
    Fire("GUILD_ROSTER_UPDATE")
    check(not C.IsOnline("Nick"), "logget ud i guild-listen = offline igen")
    roster[1][2] = true
    Fire("GUILD_ROSTER_UPDATE")
    NOW = NOW + 200
    check(not C.IsOnline("Nick"), "en gammel guild-liste tæller ikke")
    -- v0.18.5: et par mistede livstegn gør ikke vennen offline (uden guild-liste)
    db.friends.Nick.chars.Nickchar.seen, db.friends.Nick.chars.Nickchar.hb = NOW - 200, NOW - 200
    check(C.IsOnline("Nick"), "200 sek. uden livstegn: stadig online")
    db.friends.Nick.chars.Nickchar.hb = nil
    check(not C.IsOnline("Nick"), "fristen gælder kun livstegn, ikke synk-data")
    db.friends.Nick.chars.Nickchar.seen, db.friends.Nick.chars.Nickchar.hb = NOW - 400, NOW - 400
    check(not C.IsOnline("Nick"), "400 sek. uden livstegn: offline")
    -- Guild-listen siger offline efter sidste livstegn: offline med det samme
    db.friends.Nick.chars.Nickchar.seen = NOW - 30
    roster[1][2] = false
    NOW = NOW + 1
    Fire("GUILD_ROSTER_UPDATE")
    check(not C.IsOnline("Nick"), "logout i guild-listen vinder over et lidt ældre livstegn")
    -- Efternavn i guild-listen (Forever) genkendes
    roster[1] = { "Nickchar Stormhammer", true }
    Fire("GUILD_ROSTER_UPDATE")
    check(C.IsOnline("Nick"), "navn med efternavn i guild-listen genkendes")
    roster[1] = { "Nickchar-Realm", true }
    GetNumGuildMembers, GetGuildRosterInfo = nil, nil
    NOW = NOW + 400

    -- Kanalen er oppe, men vennen er ikke hørt i den: livstegnet skal også i guild
    local oldGCN = GetChannelName
    GetChannelName = function() return 5 end
    route.channelOK = true
    wipe(route.shared)
    local function has(list, kind) for _, c in ipairs(list) do if c[1] == kind then return true end end return false end
    check(has(route.Targets(true), "CHANNEL") and has(route.Targets(true), "GUILD"), "livstegn: kanal og guild, når vennen ikke er hørt i kanalen")
    check(not has(route.Targets(), "GUILD"), "almindelige beskeder: kun kanalen")
    for _, f in ipairs(C.ROSTER) do route.shared[f] = { CHANNEL = time() } end
    check(not has(route.Targets(true), "GUILD"), "alle hørt i kanalen: livstegnet går kun i kanalen")
    wipe(route.shared)
    GetChannelName = oldGCN
end

-- -----------------------------------------------------------------------------
-- Fuzz: tilfældige og ødelagte beskeder af alle typer må aldrig give en Lua-fejl
-- -----------------------------------------------------------------------------
do
    local kinds = { "D", "L", "H", "C", "RM", "LP", "HP", "PT", "BK", "S", "B", "W", "A", "R", "G", "P", "E", "F",
                    "XE", "XN", "XK", "XU", "XD", "XL", "GM", "GW", "GK", "Q", "", "ZZ" }
    local vals = { "", "Nick", "Mathias", "abc", "0", "-5", "99999999999", "item:123", "1", "x:y", "1:2,3:4",
                   "WASTEDCOAST", "need", "raid", "rareelite", "Nick-1", tostring(NOW), "a=1:2", "nan", "1e400", "-1e400",
                   "Frode", "uAAAAAAAA", "|cffff0000x|r", "æøå" }
    local friends = { "Nick", "Frode", "Mathias", "Jeppe", "Søren", "Rasmus", "Mikkel", "Andreas", "uBBBBBBBB" }
    local seed = 12345
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return (seed % n) + 1 end
    local errors = {}
    for i = 1, 4000 do
        if i % 400 == 0 then db.friends = {} db.bank = {} db.duels = {} db.levelAt = {} db.runs = {} end
        local parts = { kinds[rnd(#kinds)] }
        for j = 1, rnd(15) - 1 do parts[#parts + 1] = vals[rnd(#vals)] end
        if #parts >= 2 and rnd(2) == 1 then parts[2] = friends[rnd(#friends)] end
        local m = table.concat(parts, ";")
        local ok, err = pcall(msg, m, ({ "GUILD", "PARTY", "CHANNEL", "WHISPER" })[rnd(4)], ({ "Nickchar", "Frodex", "X-Realm" })[rnd(3)])
        if not ok and #errors < 5 then errors[#errors + 1] = m .. " => " .. tostring(err) end
    end
    check(#errors == 0, "ingen Lua-fejl fra ødelagte beskeder:\n" .. table.concat(errors, "\n"))
    -- Og vinduet kan stadig tegnes bagefter, på alle sider
    ns.frame:Show()
    local bad = {}
    for i = 1, #ns.pages do
        local ok, err = pcall(ns.ShowTab, i)
        if not ok then bad[#bad + 1] = i .. ": " .. tostring(err) end
    end
    check(#bad == 0, "alle sider kan tegnes efter fuzz: " .. table.concat(bad, "; "))
    -- Ikke-tekst fra spillet (fx secret values) ignoreres
    local ok = pcall(Fire, "CHAT_MSG_ADDON", "WCOAST", nil, "GUILD", "x")
    check(ok, "besked uden tekst ignoreres")
end

return PASSES
'''
passes = lua.execute(TESTS, ns, FOREVER)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
