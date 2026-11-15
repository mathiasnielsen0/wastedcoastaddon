# Test af hån-knappen (Haan.lua): prut-knappen på dødsannoncen, beskeden til den døde ven,
# vindue, cooldown og spam-værn, slå fra, lyd, bande-baren, sladder, synk, demo og kommandoer.
# Kør: pip install lupa && python3 tests/test_haan.py WastedCoast [forever]
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
PLAYED = {}
function PlaySoundFile(path, ch) PLAYED[#PLAYED+1] = path return SOUND_OK end
SOUND_OK = true
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
local function die(friend, char, class, at)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "D", char .. "-" .. at, char, class, "Defias Pillager", "Nærkamp", 30, "Westfall", at, friend, 31 }, ";"), "GUILD", char)
    return char .. "-" .. at
end
local function prut(from, to, death, nonce, line, snd, at)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XH", from, to, death, nonce, line or 1, snd or 1, at or NOW }, ";"), "GUILD", from .. "char")
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
local Haan = ns.Haan
check(Haan ~= nil and ns.HaanSend ~= nil and ns.HandleHaanMessage ~= nil, "Haan.lua er indlæst")
hb("Nick", "Nickchar", "MAGE", 34, "Westfall")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Westfall")

-- -----------------------------------------------------------------------------
-- Dødsannoncen har en prut-knap (men ikke når du selv dør)
-- -----------------------------------------------------------------------------
local nickDeath = die("Nick", "Nickchar", "MAGE", NOW)
local obit = lastToast("obit")
check(obit and obit.action and obit.action.label == "Prut", "dødsannoncen har en Prut-knap")
check(obit.dur == 10, "annoncen med knap står lidt længere")
check(Haan.LatestDead() == "Nick", "Nick er den senest døde")

SENT = {}
PLAYED = {}
check(obit.action.onClick() == true, "klik på knappen sender en prut")
local msgs = sentWith("XH;")
check(#msgs == 1, "én XH-besked: " .. #msgs)
local t = split(msgs[1])
check(t[2] == "Mathias" and t[3] == "Nick" and t[4] == nickDeath, "beskeden: fra, til og dødsfaldet")
check(#PLAYED == 1 and PLAYED[1]:find("sounds\\prut%d%.ogg$"), "du hører selv pruttet: " .. tostring(PLAYED[1]))
check(printed("Du pruttede af Nick."), "chatlinje hos dig")
check(#db.haan.log == 1 and db.haan.log[1].from == "Mathias", "pruttet er gemt")

-- Kun én prut pr. dødsfald, og cooldown
SENT = {}
PRINTS = {}
check(ns.HaanSend("Nick") == false and printed("allerede"), "kun én prut pr. dødsfald")
local jepDeath = die("Jeppe", "Jepchar", "ROGUE", NOW)
check(ns.HaanSend("Jeppe") == false and printed("Rolig nu"), "cooldown mellem dine prutter")
CLOCK = CLOCK + Haan.COOLDOWN + 1
check(ns.HaanSend("Jeppe") == true, "efter cooldown kan du prutte af Jeppe")
check(#sentWith("XH;") == 1, "kun den ene besked blev sendt")

-- Ikke af dig selv, og ikke af gamle dødsfald
CLOCK = CLOCK + Haan.COOLDOWN + 1
PRINTS = {}
check(ns.HaanSend("Mathias") == false and printed("dig selv"), "ikke af dig selv")
die("Frode", "Frochar", "PRIEST", NOW - Haan.WINDOW - 60)
check(ns.HaanSend("Frode") == false and printed("ikke død for nylig"), "ikke af et gammelt dødsfald")
check(ns.HaanSend("Sigurd") == false, "kun venner")

-- Egen død: ingen knap
local myDeath = die("Mathias", "Mathiasx", "WARRIOR", NOW)
check(lastToast("obit").action == nil, "ingen prut-knap på din egen dødsannonce")

-- -----------------------------------------------------------------------------
-- Modtag en prut
-- -----------------------------------------------------------------------------
PLAYED = {}
PRINTS = {}
prut("Nick", "Mathias", myDeath, "111", 2, 3)
local tt = lastToast("haan")
check(tt and tt.title:find("Nick") and tt.text:find("dig"), "popup: Nick prutter af dig: " .. tostring(tt and tt.text))
check(#PLAYED == 1 and PLAYED[1]:find("prut3.ogg", 1, true), "afsenderens valgte lyd spilles: " .. tostring(PLAYED[1]))
check(printed("Nick sender dig en varm hilsen bagfra."), "chatlinjen bruger den valgte tekst")
-- Samme besked igen (ny rute) og en ny nonce for samme dødsfald tæller ikke
prut("Nick", "Mathias", myDeath, "111", 2, 3)
prut("Nick", "Mathias", myDeath, "112", 1, 1)
check(#PLAYED == 1, "dubletter og ekstra prutter for samme dødsfald ignoreres")
-- Spam-værn: en anden død, men for tæt på
local myDeath2 = die("Mathias", "Mathiasx", "WARRIOR", NOW + 5)
prut("Nick", "Mathias", myDeath2, "113", 1, 1)
check(#PLAYED == 1, "højst én prut fra samme ven hvert 10. sekund")
CLOCK = CLOCK + Haan.RECV_GAP + 1
prut("Nick", "Mathias", myDeath2, "114", 1, 1)
check(#PLAYED == 2, "efter pausen kommer den igen")
-- Ukendte og falske afsendere
local n = #db.haan.log
prut("Sigurd", "Mathias", myDeath2, "115")
prut("Mathias", "Nick", myDeath2, "116")
Fire("CHAT_MSG_ADDON", "WCOAST", "XH;Jeppe;Mathias;;117;1;1;" .. NOW, "GUILD", "Jepchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XH;Jeppe;Mathias", "GUILD", "Jepchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XH;Jeppe;Mathias;x;118;99;abc;" .. NOW, "GUILD", "Jepchar")
check(#db.haan.log == n + 1, "fremmede, egne ekko og ødelagte beskeder giver ingen fejl (kun den sidste er gyldig): " .. (#db.haan.log - n))

-- Andre venners prutter: kun en linje i chatten og i nyhederne
PLAYED = {}
PRINTS = {}
prut("Jeppe", "Nick", nickDeath, "201", 1, 1)
check(#PLAYED == 0 and printed("Jeppe prutter af Nick."), "en prut mellem to andre: ingen lyd, en chatlinje")

-- Slå prutter fra
SlashCmdList["WASTEDCOAST"]("prut fra")
check(db.settings.haan == false, "prut fra")
local before = #toasts
PLAYED = {}
PRINTS = {}
CLOCK = CLOCK + 60
local myDeath3 = die("Mathias", "Mathiasx", "WARRIOR", NOW + 10)
before = #toasts
prut("Jeppe", "Mathias", myDeath3, "202", 1, 1)
check(#PLAYED == 0 and #toasts == before and printed("slået fra"), "slået fra: ingen lyd eller popup, kun chat")
check(#db.haan.log > 0 and db.haan.log[#db.haan.log].from == "Jeppe", "men den tælles stadig")
SlashCmdList["WASTEDCOAST"]("prut til")
check(db.settings.haan == nil, "prut til")

-- Lyd slået helt fra
db.settings.sound = false
PLAYED = {}
CLOCK = CLOCK + 60
prut("Nick", "Mathias", die("Mathias", "Mathiasx", "WARRIOR", NOW + 20), "203", 1, 1)
check(#PLAYED == 0 and lastToast("haan").title:find("Nick"), "uden lyd: popup, men ingen lyd")
db.settings.sound = true

-- Egen lyd fra Sounds.lua
ns.sounds.haan = { "minprut.ogg" }
PLAYED = {}
CLOCK = CLOCK + 60
prut("Jeppe", "Mathias", die("Mathias", "Mathiasx", "WARRIOR", NOW + 30), "204", 1, 1)
check(PLAYED[1] and PLAYED[1]:find("minprut.ogg", 1, true), "egen lyd fra Sounds.lua: " .. tostring(PLAYED[1]))
ns.sounds.haan = nil

-- Mangler lydfilen (spillet ikke genstartet): en besked én gang
SOUND_OK = false
PRINTS = {}
SlashCmdList["WASTEDCOAST"]("prut test")
check(printed("genstartet"), "besked om genstart, når lyden mangler")
PRINTS = {}
SlashCmdList["WASTEDCOAST"]("prut test")
check(not printed("genstartet"), "kun én gang")
SOUND_OK = true

-- Gamle prutter fra synk giver ingen lyd eller popup
PLAYED = {}
before = #toasts
prut("Nick", "Mathias", "Mathiasx-1", "301", 1, 1, NOW - 3 * 86400)
check(#PLAYED == 0 and #toasts == before and db.haan.log[1].id == "Nick-301", "gamle prutter fra synk gemmes stille")

-- -----------------------------------------------------------------------------
-- Tal, bande-baren, sladder og synk
-- -----------------------------------------------------------------------------
local sent, recv = Haan.Counts()
check(sent.Mathias == 2 and sent.Nick >= 3 and recv.Mathias >= 5, "tællere for givet og fået")
check(Haan.Summary():find("Flest prutter givet: Jeppe (4)", 1, true) and Haan.Summary():find("Flest fået: Mathias", 1, true), "opsummering: " .. Haan.Summary())

local items = ns.Bar.Items()
local found, deadLine
for _, it in ipairs(items) do
    if it.text:find("pruttede af", 1, true) then found = true end
end
for _, it in ipairs(ns.Bar.Items(nil, 100)) do if it.dead == "Jeppe" then deadLine = it end end
check(found, "prutter står i nyhederne")
check(deadLine ~= nil, "dødsfald i nyhederne ved, hvem der døde")

-- v0.30.1: klik på et frisk dødsfald i nyhederne prutter IKKE (kun dødsannoncens knap gør)
die("Rasmus", "Raschar", "HUNTER", NOW + 40)
local rl
for _, it in ipairs(ns.Bar.Items(nil, 100)) do if it.dead == "Rasmus" then rl = it end end
check(rl ~= nil and ns.Bar.CanTaunt == nil, "dødsfaldet står i nyhederne, men baren kan ikke prutte")
CLOCK = CLOCK + Haan.COOLDOWN + 1
SENT = {}
if ns.BuildBar then ns.BuildBar() end
-- Ræk ind i rækkens klik direkte
local row = { line = { item = rl } }
local rowClick
for _, f in ipairs(FRAMES) do
    if f.scripts.OnClick and f.scripts.OnDragStart and rawget(f, "line") ~= nil and rawget(f, "fs") and not rowClick then rowClick = f.scripts.OnClick end
end
check(rowClick ~= nil, "nyhedsrækken kan klikkes")
-- Musen over et dødsfald viser bare tiden, og et klik sender ingenting
ns.Bar.UpdateTicker()
local real = ns.barFrame.rows[1]
real.line = { text = "x", ago = "1m", item = rl }
local before = real.time.text_
real.scripts.OnEnter(real)
check(real.time.text_ == before, "musen over et dødsfald viser bare tiden")
real.scripts.OnLeave(real)
rowClick(row)
check(#sentWith("XH;") == 0, "klik på dødsfaldet i nyhederne sender ingen prut")
check(Haan.Can("Rasmus"), "man kan stadig prutte af Rasmus fra dødsannoncen")
ns.HaanSend("Rasmus")
check(#sentWith("XH;") == 1, "prut sendt på anden vis")

-- Tooltip på bande-baren
local s
for _, st in ipairs(ns.core.BuildStats()) do if st.name == "Nick" then s = st end end
local tl = ns.Bar.TooltipLines(s)
local hasCount
for _, l in ipairs(tl) do if l[1] == "Prutter" then hasCount = l[2] end end
check(hasCount and hasCount:find("givet"), "tooltip viser prutter givet og fået: " .. tostring(hasCount))

-- Sladder
local gossip = table.concat(ns.GossipLines(NOW - 3600, {}, nil, 99), "\n")
check(gossip:find("pruttede af de døde", 1, true), "prutter i sladderen")
check(gossip:find("blev pruttet af", 1, true), "flest fået i sladderen")

-- Synk: dine egne prutter sendes igen
SENT = {}
Haan.SendLog()
local syncs = sentWith("XH;Mathias;")
check(#syncs == 3, "synk sender dine prutter: " .. #syncs)

-- -----------------------------------------------------------------------------
-- Den rigtige toast-knap
-- -----------------------------------------------------------------------------
local tf = _G.WastedCoastToast
for i = 1, 30 do if tf.scripts.OnUpdate then tf.scripts.OnUpdate(tf, 100) end end
local clicked = 0
ns.Toast({ kind = "obit", title = "Test", text = "x", force = true, dur = 10,
           action = { label = "Prut", done = "Prut!", onClick = function() clicked = clicked + 1 return true end } })
check(tf.action and tf.action.shown and tf.action.text:GetText() == "Prut", "toasten viser knappen")
tf.action.scripts.OnClick(tf.action)
tf.action.scripts.OnClick(tf.action)
check(clicked == 1 and tf.action.text:GetText() == "Prut!", "knappen virker én gang og skifter tekst")
for i = 1, 30 do tf.scripts.OnUpdate(tf, 100) end
ns.Toast({ kind = "info", title = "Uden", text = "x", force = true })
check(not tf.action.shown, "toasts uden knap viser ingen knap")

-- -----------------------------------------------------------------------------
-- Kommandoer, demo og nulstilling
-- -----------------------------------------------------------------------------
PRINTS = {}
SlashCmdList["WASTEDCOAST"]("prut tal")
check(printed("Flest prutter"), "/wc4ever prut tal")
CLOCK = CLOCK + Haan.COOLDOWN + 1
die("Søren", "Sorchar", "PALADIN", NOW + 50)
SENT = {}
SlashCmdList["WASTEDCOAST"]("prut")
m = sentWith("XH;")
check(#m == 1 and split(m[1])[3] == "Søren", "/wc4ever prut uden navn: den senest døde")
CLOCK = CLOCK + Haan.COOLDOWN + 1
die("Mikkel", "Mikchar", "DRUID", NOW + 55)
SENT = {}
SlashCmdList["WASTEDCOAST"]("prut mik")
m = sentWith("XH;")
check(#m == 1 and split(m[1])[3] == "Mikkel", "/wc4ever prut mik")

local n0 = #db.haan.log
SlashCmdList["WASTEDCOAST"]("demo")
RunTimers()
local demo = 0
for _, e in ipairs(db.haan.log) do if e.demo then demo = demo + 1 end end
check(demo == 2, "demo-data")
SlashCmdList["WASTEDCOAST"]("demo slut")
check(#db.haan.log == n0, "demo fjernes igen")
-- -----------------------------------------------------------------------------
-- v0.30.1: prut-nægteren får en straffeprut hvert 5. minut
-- -----------------------------------------------------------------------------
local tick
for _, tk in ipairs(TICKERS) do if tk.d == 60 and tk.f == Haan.PenaltyTick then tick = tk.f end end
check(tick ~= nil, "straffeprut-uret kører hvert minut")
check(Haan.PenaltyTick() == false, "ingen straffeprut, når prutter er slået til")
SENT = {}
PRINTS = {}
SlashCmdList["WASTEDCOAST"]("prut fra")
check(printed("prut-nægter"), "advarsel, når man slår prutter fra")
local st = sentWith("XR;Mathias;1;")
check(#st == 1, "vennerne får at vide, at du er prut-nægter")
PLAYED = {}
before = #toasts
CLOCK = CLOCK + 60
check(Haan.PenaltyTick() == false and #PLAYED == 0, "ingen straffeprut efter 1 minut")
CLOCK = CLOCK + Haan.PENALTY
check(Haan.PenaltyTick() == true, "straffeprut efter 5 minutter")
check(#PLAYED == 1 and lastToast("haan").title == "Frygtsom prut-nægter", "lyd og popup til prut-nægteren")
check(Haan.PenaltyTick() == false, "ikke to i træk")
CLOCK = CLOCK + Haan.PENALTY
check(Haan.PenaltyTick() == true and db.haan.penalty.n == 2, "og igen 5 minutter senere")
local mine
for _, it in ipairs(ns.Bar.Items(nil, 100)) do if it.text:find("prut-nægter", 1, true) and it.text:find("Mathias", 1, true) then mine = it end end
check(mine ~= nil, "nyhed: du blev prut-nægter")
for _, st2 in ipairs(ns.core.BuildStats()) do if st2.name == "Mathias" then s = st2 end end
local found2
for _, l in ipairs(ns.Bar.TooltipLines(s)) do if tostring(l[1]):find("2 straffeprutter", 1, true) then found2 = true end end
check(found2, "tooltip viser dine straffeprutter")
SENT = {}
PRINTS = {}
SlashCmdList["WASTEDCOAST"]("prut til")
check(printed("2 straffeprutter") and #sentWith("XR;Mathias;0;") == 1, "slå til igen: stop og besked til vennerne")
CLOCK = CLOCK + Haan.PENALTY
check(Haan.PenaltyTick() == false, "ingen straffeprut efter, man har slået prutter til igen")

-- En vens status
PRINTS = {}
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Nick;1;" .. NOW .. ";4", "GUILD", "Nickchar")
check(Haan.IsRefuser("Nick") and printed("Nick har slået prutter fra"), "Nick er prut-nægter")
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Nick;1;" .. NOW .. ";5", "GUILD", "Nickchar")
check(db.haan.refusers.Nick.n == 5, "tælleren opdateres")
for _, st2 in ipairs(ns.core.BuildStats()) do if st2.name == "Nick" then s = st2 end end
found2 = nil
for _, l in ipairs(ns.Bar.TooltipLines(s)) do if tostring(l[1]):find("5 straffeprutter", 1, true) then found2 = true end end
check(found2, "Nicks tooltip viser straffeprutterne")
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Nick;0;" .. NOW .. ";5", "GUILD", "Nickchar")
check(not Haan.IsRefuser("Nick"), "Nick slog prutter til igen")
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Sigurd;1;1;1", "GUILD", "Sigurd")
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Jeppe;x", "GUILD", "Jepchar")
Fire("CHAT_MSG_ADDON", "WCOAST", "XR;Mathias;1;1;1", "GUILD", "Mathiasx")
check(not Haan.IsRefuser("Sigurd") and not Haan.IsRefuser("Jeppe") and not Haan.IsRefuser("Mathias"), "fremmede og ødelagte statusbeskeder ignoreres")
return PASSES

'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
