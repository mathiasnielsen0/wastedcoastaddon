# Test af stomi-fælden (Stomi.lua): lokkemad, popup med stor JA under musen, svar, cooldown,
# kamp, indstilling, bande-baren, sladder, synk og at intet rigtigt sker i spillet.
# Kør: pip install lupa && python3 tests/test_stomi.py WastedCoast [forever]
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
-- Spillets rigtige handlinger: ingen af dem må blive kaldt af fælden
GAME_ACTIONS = {}
for _, fn in ipairs({ "AcceptGroup", "DeclineGroup", "AcceptDuel", "CancelDuel", "StartDuel", "ConfirmSummon",
                      "CancelSummon", "AcceptResurrect", "DeclineResurrect", "AcceptTrade", "InitiateTrade",
                      "InviteUnit", "SendMail", "PickupContainerItem", "UseContainerItem", "StaticPopup_Show" }) do
    _G[fn] = function() GAME_ACTIONS[#GAME_ACTIONS+1] = fn end
end
IN_COMBAT = false
function UnitAffectingCombat() return IN_COMBAT end
DEAD = false
function UnitIsDeadOrGhost() return DEAD end
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
-- Samme besked kan gå ud på flere ruter (guild, gruppe, kanal): tæl hver besked én gang
local function sentWith(prefix) pump() local out, seen = {}, {} for _, s in ipairs(SENT) do if s.msg:sub(1, #prefix) == prefix and not seen[s.msg] then seen[s.msg] = true out[#out+1] = s.msg end end return out end
local function split(s) local t = {} for p in (s .. ";"):gmatch("(.-);") do t[#t+1] = p end return t end
local function online()
    hb("Nick", "Nickchar", "MAGE", 34, "Duskwood")
    hb("Jeppe", "Jepchar", "ROGUE", 30, "Westfall")
    hb("Frode", "Frochar", "PRIEST", 30, "Westfall")
end
local function printed(s) for _, p in ipairs(PRINTS) do if p:find(s, 1, true) then return true end end end
local function ttHas(s) for _, l in ipairs(TT) do if tostring(l):find(s, 1, true) then return true end end end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
CLOCK = CLOCK + 1000
ns.toastsSeen = {}
local realToast = ns.Toast
ns.Toast = function(o) ns.toastsSeen[#ns.toastsSeen+1] = o return realToast(o) end
local Stomi = ns.Stomi
check(Stomi ~= nil and ns.StomiTrap ~= nil and ns.HandleStomiMessage ~= nil, "Stomi.lua er indlæst")

-- -----------------------------------------------------------------------------
-- Lokkematen
-- -----------------------------------------------------------------------------
local function pick(v) return function() return v end end
local b = Stomi.Bait({ char = "Nickchar", class = "PRIEST", dead = true, grouped = false, zone = "Nagrand", myZone = "Westfall" })
check(b.kind == "rez" and b.text:find("Nickchar", 1, true) and b.text:find("rezze"), "død ven + præst = rez: " .. b.text)
b = Stomi.Bait({ char = "Nickchar", class = "MAGE", dead = true, grouped = true, zone = "Nagrand", myZone = "Westfall" }, pick(0))
check(b.kind ~= "rez" and b.kind ~= "summon", "en mage kan ikke rezze, og døde kan ikke summones: " .. b.kind)
b = Stomi.Bait({ char = "Nickchar", class = "WARLOCK", grouped = true, zone = "Shattrath City", myZone = "Westfall" }, pick(0))
check(b.kind == "summon" and b.text:find("Shattrath City", 1, true), "warlock i en anden zone = summon: " .. b.text)
b = Stomi.Bait({ char = "Nickchar", class = "MAGE", grouped = true, zone = "Westfall", myZone = "Westfall",
                 itemId = 28830, quality = 4, itemName = "Dragonspine Trophy" }, pick(0))
check(b.kind == "gift" and b.text:find("Dragonspine Trophy", 1, true) and b.text:find("|Hitem:28830", 1, true),
      "gave med et rigtigt item-link: " .. b.text)
b = Stomi.Bait({ char = "Nickchar", class = "MAGE", grouped = false, zone = "Westfall", myZone = "Westfall" }, pick(0))
check(b.kind == "invite" and b.text:find("Nickchar", 1, true), "ikke i gruppe = invite")
b = Stomi.Bait({ char = "Nickchar", class = "MAGE", grouped = true, zone = "Westfall", myZone = "Westfall", gold = 250000 }, pick(0))
check(b.kind == "gold", "guld som lokkemad: " .. b.kind)
local kinds = {}
for i = 0, 99 do
    kinds[Stomi.Bait({ char = "X", class = "WARLOCK", grouped = false, zone = "Nagrand", myZone = "Westfall",
        itemId = 1, quality = 3, itemName = "Y", gold = 50000 }, pick(i / 100)).kind] = true
end
check(kinds.invite and kinds.summon and kinds.gift and kinds.gold and kinds.carry, "der er flere slags lokkemad")

-- Popuppen står, så JA-knappen er lige under musen
local x, y = Stomi.PopupCenter(500, 400, 1)
check(x == 500 and y == 400 + (75 - 58), "JA-knappens midte er ved musen: " .. x .. "," .. y)
x, y = Stomi.PopupCenter(1000, 800, 2)
check(x == 500 and y == 400 + 17, "UI-skalering regnes med")
x, y = Stomi.PopupCenter(5, 5, 1, 1920, 1080)
check(x == 170 and y == 75, "popuppen holdes inde på skærmen")

-- -----------------------------------------------------------------------------
-- Send en fælde
-- -----------------------------------------------------------------------------
ITEMS[13446] = { equip = false, count = 5 }
SENT = {}
check(ns.StomiTrap("Mathias") == false and printed("dig selv"), "man kan ikke give sig selv stomi")
check(ns.StomiTrap("Nick") == false and printed("ikke online"), "en ven, der ikke er online, kan ikke fanges")
hb("Nick", "Nickchar", "MAGE", 34, "Duskwood")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Westfall")
hb("Frode", "Frochar", "PRIEST", 30, "Westfall")
MONEY = 3000000
check(ns.StomiTrap("Nick") == true, "fælden sendes")
local xs = sentWith("XS;")
check(#xs == 1, "én XS-besked")
local t = split(xs[1])
check(t[2] == "Mathias" and t[3] == "Nick" and t[5] == "Mathiasx" and t[6] == "WARRIOR" and t[7] == "Westfall",
      "fra, til, karakter, klasse og zone: " .. xs[1])
check(t[8] == "13446" and t[9] == "3" and t[11] == "Item13446", "bedste item fra tasken er med: " .. xs[1])
check(t[10] == "300000", "guld-gaven er en tiendedel af guldet, højst 50g: " .. t[10])
check(#xs[1] <= 255, "beskeden er kort nok")
check(ns.StomiTrap("Jeppe") == false and printed("Rolig nu"), "lang cooldown mellem fælder")
check(Stomi.COOLDOWN >= 3 * 3600, "cooldown er mindst 3 timer")
NOW = NOW + Stomi.COOLDOWN + 1
online()
check(ns.StomiTrap("Jeppe") == true, "efter cooldown kan man igen")

-- -----------------------------------------------------------------------------
-- Modtag en fælde: JA
-- -----------------------------------------------------------------------------
local function trap(from, nonce, char, class, zone)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XS", from, "Mathias", nonce, char, class, zone, "28830", "4", "500000", "Dragonspine Trophy" }, ";"), "GUILD", char)
    RunTimers()
end
SENT = {}
-- En fælde til en anden end mig vises ikke
Fire("CHAT_MSG_ADDON", "WCOAST", "XS;Nick;Jeppe;111;Nickchar;MAGE;Duskwood;;;0;", "GUILD", "Nickchar")
RunTimers()
check(Stomi.popup == nil or not Stomi.popup.shown, "fælder til andre vises ikke hos mig")

trap("Nick", "222", "Nickchar", "MAGE", "Duskwood")
local p = Stomi.popup
check(p and p.shown, "popuppen vises")
check(p.text.text_ ~= "HAR DU STOMI?" and p.text.text_:find("Nickchar", 1, true), "først står lokkematen: " .. tostring(p.text.text_))
check(p.yes.text_ == "JA!" and p.no.label.text_ == "nej", "stor JA og lille nej")
check(p.x ~= nil and p.y ~= nil, "popuppen er placeret ved musen")
-- Samme fælde igen (dublet) giver ikke en ny popup
trap("Nick", "222", "Nickchar", "MAGE", "Duskwood")
-- Musen ned på JA: spørgsmålet skifter med det samme, knappen bliver stående
p.yes.scripts.OnMouseDown(p.yes)
check(p.text.text_ == "HAR DU STOMI?", "musen ned skifter til HAR DU STOMI?")
check(p.yes.text_ == "JA!", "JA-knappen er der stadig")
p.yes.scripts.OnClick(p.yes)
check(not p.shown, "popuppen lukker")
check(Stomi.Has("Mathias") ~= nil and Stomi.Has("Mathias").from == "Nick", "jeg har stomi fra Nick")
check(Stomi.Remaining("Mathias") == 24 * 3600, "i 24 timer")
local xt = sentWith("XT;")
check(#xt == 1 and xt[1]:find("^XT;Mathias;Nick;222;y;"), "svaret sendes til alle: " .. tostring(xt[1]))
local last = ns.toastsSeen[#ns.toastsSeen]
check(last.kind == "stomi" and last.head == "STOMI!", "toast hos mig")
check(#GAME_ACTIONS == 0, "ingen rigtige handlinger i spillet: " .. table.concat(GAME_ACTIONS, ","))

-- Klik på JA uden musen ned (fx tastatur) spørger først
NOW = NOW + 25 * 3600
online()
check(Stomi.Has("Mathias") == nil, "stomien forsvinder efter 24 timer")
trap("Jeppe", "333", "Jepchar", "ROGUE", "Westfall")
p.yes.scripts.OnClick(p.yes)
check(p.shown and p.text.text_ == "HAR DU STOMI?", "første klik uden musen ned viser spørgsmålet")
-- Nu den lille nej
SENT = {}
p.no.scripts.OnClick(p.no)
check(not p.shown and Stomi.Has("Mathias") == nil, "nej efter spørgsmålet = ingen stomi")
check(sentWith("XT;")[1]:find(";333;n;"), "resultat n")

-- Nej til lokkematen, før spørgsmålet skifter
trap("Frode", "444", "Frochar", "PRIEST", "Westfall")
check(p.shown and p.text.text_ ~= "HAR DU STOMI?", "ny fælde fra Frode")
p.no.scripts.OnClick(p.no)
check(sentWith("XT;")[#sentWith("XT;")]:find(";444;d;"), "resultat d")
check(printed("stomi-fælde fra Frode"), "afsløring i chatten bagefter")

-- Samme ven kan ikke spamme (også hvis giverens cooldown er pillet ved)
trap("Frode", "445", "Frochar", "PRIEST", "Westfall")
check(not p.shown, "anden fælde fra samme ven kort efter ignoreres")

-- Escape lukker = ignoreret
CLOCK = CLOCK + Stomi.COOLDOWN
trap("Nick", "555", "Nickchar", "MAGE", "Duskwood")
check(p.shown, "fælde vises igen efter et stykke tid")
p:Hide()
p.scripts.OnHide(p)
check(sentWith("XT;")[#sentWith("XT;")]:find(";555;x;"), "escape = x")

-- Timeout
CLOCK = CLOCK + Stomi.COOLDOWN
trap("Jeppe", "666", "Jepchar", "ROGUE", "Westfall")
p.scripts.OnUpdate(p, 30)
check(p.shown, "stadig åben efter 30 sek.")
p.scripts.OnUpdate(p, 31)
check(not p.shown and sentWith("XT;")[#sentWith("XT;")]:find(";666;x;"), "lukker selv efter 60 sek.")

-- I kamp: venter, til kampen er slut
CLOCK = CLOCK + Stomi.COOLDOWN
IN_COMBAT = true
trap("Nick", "777", "Nickchar", "MAGE", "Duskwood")
check(not p.shown, "ingen popup midt i kamp")
IN_COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
RunTimers()
check(p.shown, "popuppen kommer, når kampen er slut")
p.no.scripts.OnClick(p.no)

-- Slået fra i indstillingerne
CLOCK = CLOCK + Stomi.COOLDOWN
local opts = ns.options
if not opts and ns.OpenOptions then ns.OpenOptions() opts = ns.options end
local cb
for _, c in ipairs(opts.checks) do if c.label.text_ == "Stomi-fælden" then cb = c end end
check(cb ~= nil, "indstillingen findes")
check(cb.get() == true, "slået til som standard")
rawset(cb, "GetChecked", function() return false end)
cb.scripts.OnClick(cb)
check(db.settings.stomi == false, "afkrydsningen slår den fra")
trap("Jeppe", "888", "Jepchar", "ROGUE", "Westfall")
check(not p.shown, "ingen popup, når den er slået fra")
rawset(cb, "GetChecked", function() return true end)
cb.scripts.OnClick(cb)
check(db.settings.stomi == nil, "og til igen")
SlashCmdList["WASTEDCOAST"]("stomi fra")
check(db.settings.stomi == false, "/wc4ever stomi fra")
SlashCmdList["WASTEDCOAST"]("stomi til")
check(db.settings.stomi == nil, "/wc4ever stomi til")
check(#GAME_ACTIONS == 0, "stadig ingen rigtige handlinger i spillet")

-- -----------------------------------------------------------------------------
-- En vens stomi: toast, bar, ticker, sladder og tællere
-- -----------------------------------------------------------------------------
local before = #ns.toastsSeen
Fire("CHAT_MSG_ADDON", "WCOAST", "XT;Nick;Jeppe;999;y;" .. NOW .. ";gift", "GUILD", "Nickchar")
check(Stomi.Has("Nick") and Stomi.Has("Nick").from == "Jeppe", "Nick har stomi fra Jeppe")
check(#ns.toastsSeen == before + 1 and ns.toastsSeen[#ns.toastsSeen].title:find("Nick"), "toast hos alle")
Fire("CHAT_MSG_ADDON", "WCOAST", "XT;Nick;Jeppe;999;y;" .. NOW .. ";gift", "GUILD", "Nickchar")
check(#ns.toastsSeen == before + 1, "dubletter tælles ikke")
-- Svar fra fremtiden gør ikke stomien længere
Fire("CHAT_MSG_ADDON", "WCOAST", "XT;Andreas;Jeppe;998;y;" .. (NOW + 99999) .. ";gift", "GUILD", "Andchar")
check(Stomi.Remaining("Andreas") <= 24 * 3600, "tid i fremtiden klippes")

local Bar = ns.Bar
Bar.Refresh()
local icon
for _, bb in ipairs(ns.barFrame.icons) do if bb.shown and bb.friend == "Nick" then icon = bb end end
check(icon and icon.stomi.shown == true, "stomipose på Nicks ikon")
for _, bb in ipairs(ns.barFrame.icons) do if bb.shown and bb.friend == "Frode" then check(bb.stomi.shown == false, "ingen pose hos Frode") end end
TT = {}
icon.scripts.OnEnter(icon)
check(ttHas("stomi") and ttHas("Jeppe"), "tooltip: har stomi fra Jeppe")
local found = false
for _, it in ipairs(Bar.Items()) do if it.text:find("stomi") and it.text:find("Nick") then found = true end end
check(found, "nyheden står i tickeren")

local lines = ns.GossipLines(NOW - 3600, {}, {}, 30)
local gl = false
for _, l in ipairs(lines) do if l:find("stomi") and l:find("Nick") then gl = true end end
check(gl, "linje i dagens sladder")

local c = Stomi.Counts()
check(c.given.Jeppe == 2 and c.recv.Nick == 1 and c.recv.Mathias == 1, "tællere for givet og fået")
check(c.escaped.Mathias == 3, "tre gange slap jeg (n, d og d efter kampen)")
local sum = Stomi.Summary()
check(sum:find("Nick") and sum:find("Flest givet: Jeppe"), "opsummering: " .. sum)

-- Drilleri-siden: højreklik sætter en fælde, opsummeringen står der
ns.frame:Show()
for i = 1, #ns.pages do if ns.pages[i] then ns.ShowTab(i) end end
ns.RefreshUI()
NOW = NOW + Stomi.COOLDOWN + 1
online()
SENT = {}
local btn
for _, f in ipairs(FRAMES) do if rawget(f, "friend") == "Frode" and f.scripts.OnClick and rawget(f, "text") then btn = f end end
check(btn ~= nil, "Frodes knap på Drilleri-siden")
btn.scripts.OnClick(btn, "RightButton")
check(#sentWith("XS;") == 1 and sentWith("XS;")[1]:find("^XS;Mathias;Frode;"), "højreklik sætter en stomi-fælde")

-- Synk sender de seneste svar
SENT = {}
Stomi.SendLog()
check(#sentWith("XT;") >= 3, "synk sender svarene")

-- Test-popuppen: giver ikke stomi og sender intet
SENT = {}
NOW = NOW + 25 * 3600
online()
SlashCmdList["WASTEDCOAST"]("stomi test")
check(p.shown, "/wc4ever stomi test viser popuppen")
p.yes.scripts.OnMouseDown(p.yes)
p.yes.scripts.OnClick(p.yes)
check(not p.shown and Stomi.Has("Mathias") == nil and #sentWith("XT;") == 0, "testen giver ikke stomi og sender intet")
-- Bagefter virker en rigtig fælde stadig
CLOCK = CLOCK + Stomi.COOLDOWN
trap("Nick", "1001", "Nickchar", "MAGE", "Duskwood")
p.yes.scripts.OnMouseDown(p.yes)
p.yes.scripts.OnClick(p.yes)
check(Stomi.Has("Mathias") ~= nil, "en rigtig fælde efter testen virker")

-- Demo og nulstilling
SlashCmdList["WASTEDCOAST"]("demo")
RunTimers()
local demo = 0
for _, e in ipairs(db.stomi.log) do if e.demo then demo = demo + 1 end end
check(demo == 2, "demo-data")
SlashCmdList["WASTEDCOAST"]("demo slut")
demo = 0
for _, e in ipairs(db.stomi.log) do if e.demo then demo = demo + 1 end end
check(demo == 0, "demo fjernes igen")
check(#GAME_ACTIONS == 0, "ingen rigtige handlinger i hele testen")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
