# Test af hjemmesko-alarmen (Hjemmesko.lua): din egen AFK i byen (XZ), vennernes zZz på bande-baren,
# prik med vækkelyd (XV), cooldown og spam-værn, slå fra, ødelagte beskeder, synk, demo og kommandoer.
# Kør: pip install lupa && python3 tests/test_hjemmesko.py WastedCoast [forever]
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
AFK, RESTING = false, false
function UnitIsAFK() return AFK end
function IsResting() return RESTING end
SOUNDS = {}
function PlaySound(id) SOUNDS[#SOUNDS+1] = id end
FLASHES = 0
function FlashClientIcon() FLASHES = FLASHES + 1 end
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
local function zz(friend, state, secs, zone)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XZ", friend, state, secs or "", zone or "" }, ";"), "GUILD", friend .. "char")
end
local function poke(from, to, nonce, line, at)
    Fire("CHAT_MSG_ADDON", "WCOAST", table.concat({ "XV", from, to, nonce, line or 1, at or NOW }, ";"), "GUILD", from .. "char")
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
local H = ns.Hjemmesko
check(H ~= nil and ns.HjemmeskoWake ~= nil and ns.HandleHjemmeskoMessage ~= nil, "Hjemmesko.lua er indlæst")
hb("Nick", "Nickchar", "MAGE", 30, "Stormwind City")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Ironforge")

-- -----------------------------------------------------------------------------
-- Din egen AFK i byen
-- -----------------------------------------------------------------------------
SENT = {}
AFK, RESTING = true, false
H.Check()
check(H.mine.since == nil and #sentWith("XZ;") == 0, "AFK ude i verden tæller ikke")
AFK, RESTING = true, true
H.Check()
check(H.mine.since == NOW, "AFK i byen: du er AFK fra nu")
local msgs = sentWith("XZ;Mathias;1;")
check(#msgs == 1, "vennerne får besked: " .. #msgs)
local t = split(msgs[1])
check(t[4] == "0" and t[5] == "Westfall", "sekunder og zone: " .. msgs[1])
check(not H.Asleep("Mathias"), "du sover ikke endnu")
SENT = {}
NOW = NOW + 60
H.Check()
check(#sentWith("XZ;") == 0, "ingen ny besked hvert tjek")
NOW = NOW + H.RESEND
H.Check()
msgs = sentWith("XZ;Mathias;1;")
check(#msgs == 1 and tonumber(split(msgs[1])[4]) == 60 + H.RESEND, "sendes igen hvert 5. minut med sekunderne")
NOW = NOW + H.SLEEP
check(H.Asleep("Mathias") ~= nil, "efter 20 min. sover du")
-- Synk sender kun tilstanden, mens du er AFK
SENT = {}
ns.SendPrankExtras(true)
check(#sentWith("XZ;Mathias;1;") == 1, "synk sender din AFK")
-- Nick prikker til dig, mens du sover
toasts = {}
SOUNDS, FLASHES = {}, 0
poke("Nick", "Mathias", "123456", 3, NOW)
local got = lastToast("hjemmesko")
check(got and got.title:find("Nick") and got.text:find("Nick råber VÆK! lige ind i øret på dig.", 1, true), "du får en popup: " .. tostring(got and got.text))
check(#SOUNDS == 1 and FLASHES == 1, "med vækkelyd og blink")
check(printed("Nick råber"), "og en linje i chatten")
-- Du vågner
SENT = {}
PRINTS = {}
AFK = false
H.Check()
check(H.mine.since == nil and #sentWith("XZ;Mathias;0") == 1, "vågen: vennerne får besked")
check(printed("Godmorgen") and printed("Nick"), "du får at vide, hvem der prikkede")
SENT = {}
ns.SendPrankExtras(true)
check(#sentWith("XZ;") == 0, "vågen sendes ikke ved synk")

-- -----------------------------------------------------------------------------
-- Vennerne: zZz og prik
-- -----------------------------------------------------------------------------
hb("Nick", "Nickchar", "MAGE", 30, "Stormwind City")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Ironforge")
zz("Nick", "1", 25 * 60, "Stormwind City")
check(H.Asleep("Nick") == 25, "Nick har sovet i 25 min.")
zz("Jeppe", "1", 5 * 60, "Ironforge")
check(not H.Asleep("Jeppe"), "Jeppe er AFK, men sover ikke endnu")
local ok, why = H.Can("Jeppe")
check(not ok and why:find("sover ikke"), "Jeppe kan ikke vækkes: " .. tostring(why))
check(H.Sleepiest() == "Nick", "Nick har sovet længst")
ok, why = H.Can("Mathias")
check(not ok and why:find("dig selv"), "ikke dig selv")

-- Bande-baren
local Bar = ns.Bar
Bar.Refresh()
local nickBtn, jepBtn
for _, b in ipairs(ns.barFrame.icons) do
    if b.friend == "Nick" then nickBtn = b elseif b.friend == "Jeppe" then jepBtn = b end
end
check(nickBtn and nickBtn.zzz.shown and nickBtn.zzz.text_ == "zZz", "Nick har zZz på sit ikon")
check(jepBtn and not jepBtn.zzz.shown, "Jeppe har ikke")
TT = {}
nickBtn.scripts.OnEnter(nickBtn)
check(ttHas("Sover i hjemmeskoene") and ttHas("Stormwind City") and ttHas("væk Nick"), "tooltippen viser søvnen og klikket")
SENT = {}
nickBtn.scripts.OnClick(nickBtn, "LeftButton")
msgs = sentWith("XV;")
check(#msgs == 1, "klik på ikonet prikker: " .. #msgs)
t = split(msgs[1])
check(t[2] == "Mathias" and t[3] == "Nick" and t[4]:match("^%d+$"), "beskeden: fra, til og nonce")
check(#msgs[1] <= 255 and not msgs[1]:find("|", 1, true), "beskeden er kort og ren")
check(printed("Du prikkede til Nick"), "du får en bekræftelse")
local sent, recv = H.Counts()
check(sent.Mathias == 1 and recv.Nick == 1 and recv.Mathias == 1, "prik tælles")
-- Cooldown
ok, why = H.Can("Nick")
check(not ok and why:find("Rolig"), "cooldown: " .. tostring(why))
CLOCK = CLOCK + H.COOLDOWN + 1
ok, why = H.Can("Nick")
check(not ok and why:find("Rolig"), "samme ven kun én gang i minuttet")
CLOCK = CLOCK + H.PER_FRIEND
check(H.Can("Nick") == true, "efter et minut kan du igen")
-- Shift-klik åbner vennen i stedet
SENT = {}
IsShiftKeyDown = function() return true end
nickBtn.scripts.OnClick(nickBtn, "LeftButton")
IsShiftKeyDown = nil
check(#sentWith("XV;") == 0, "shift-klik prikker ikke")
-- I nyhederne
local found
for _, it in ipairs(Bar.Items(nil, 100)) do if it.kind == "hjemmesko" and it.text:find("vækkede", 1, true) then found = true end end
check(found, "prikket står i nyhederne")
-- Nick vågner
zz("Nick", "0")
check(not H.Asleep("Nick"), "Nick er vågen")
Bar.Refresh()
check(not nickBtn.zzz.shown, "og zZz er væk")
-- En gammel tilstand glemmes, hvis den ikke sendes igen
zz("Nick", "1", 30 * 60, "Stormwind City")
check(H.Asleep("Nick"), "Nick sover igen")
NOW = NOW + H.STALE + 1
hb("Nick", "Nickchar", "MAGE", 30, "Stormwind City")
check(not H.Asleep("Nick"), "uden ny besked i 11 min. glemmes den")

-- -----------------------------------------------------------------------------
-- Modtageren: spam-værn, slået fra og ødelagte beskeder
-- -----------------------------------------------------------------------------
toasts = {}
poke("Jeppe", "Mathias", "200001", 1, NOW)
check(lastToast("hjemmesko") ~= nil, "Jeppe prikker til dig")
toasts = {}
poke("Jeppe", "Mathias", "200002", 1, NOW)
check(not lastToast("hjemmesko"), "samme ven lige efter: ignoreres")
local before = #db.hjemmesko.log
poke("Nobody", "Mathias", "300001")
poke("Nick", "Mathias", "")
poke("Nick", "Mathias", "abc")
poke("Nick", "Nick", "300002")
poke("Nick", "Mathias", "300003", 1, "nu")
zz("Nobody", "1", 1500)
zz("Nick", "1", "lang tid")
zz("Nick", "1", -5)
zz("Nick", "2", 1500)
zz("Mathias", "1", 1500)
check(#db.hjemmesko.log == before, "ugyldige prik ignoreres")
check(not H.AfkSince("Nick") and not H.AfkSince("Nobody"), "ugyldige XZ ignoreres")
check(H.mine.since == nil, "en besked om dig selv ændrer intet")
-- Linjenummer uden for listen falder tilbage til 1
CLOCK = CLOCK + 100
poke("Søren", "Mathias", "400001", 99, NOW)
check(db.hjemmesko.log[#db.hjemmesko.log].line == 1, "ukendt tekst-nr bliver 1")
-- Slået fra: kun chat
db.settings.hjemmesko = false
toasts = {}
SOUNDS, FLASHES = {}, 0
PRINTS = {}
poke("Andreas", "Mathias", "500001", 1, NOW)
check(not lastToast("hjemmesko") and #SOUNDS == 0 and FLASHES == 0 and printed("Andreas"), "slået fra: ingen popup, lyd eller blink, kun chat")
db.settings.hjemmesko = nil
-- Gamle prik fra synk giver ingen popup
toasts = {}
CLOCK = CLOCK + 100
poke("Rasmus", "Mathias", "600001", 1, NOW - 3 * 86400)
check(not lastToast("hjemmesko") and #db.hjemmesko.log == before + 3, "gamle prik gemmes uden popup")
-- Prik mellem to andre venner
toasts = {}
poke("Rasmus", "Nick", "600002", 1, NOW)
check(not lastToast("hjemmesko"), "prik til en anden ven giver ingen popup hos dig")

-- -----------------------------------------------------------------------------
-- Synk, demo, nulstilling og kommandoer
-- -----------------------------------------------------------------------------
SENT = {}
H.SendLog()
msgs = sentWith("XV;Mathias;")
check(#msgs == 1, "synk sender dine egne prik: " .. #msgs)
SENT = {}
ns.SendPrankExtras(false)
check(#sentWith("XV;Mathias;") == 1, "også gennem den fulde synk")
local slash = SlashCmdList["WASTEDCOAST"]
slash("væk fra")
check(db.settings.hjemmesko == false, "/wc4ever væk fra")
slash("vaek til")
check(db.settings.hjemmesko == nil, "/wc4ever vaek til")
toasts = {}
SENT = {}
slash("væk test")
check(lastToast("hjemmesko") and #sentWith("XV;") == 0, "/wc4ever væk test viser popuppen uden at sende")
PRINTS = {}
slash("væk")
check(printed("Ingen af vennerne sover"), "/wc4ever væk uden sovende venner")
hb("Jeppe", "Jepchar", "ROGUE", 30, "Ironforge")
zz("Jeppe", "1", 40 * 60, "Ironforge")
CLOCK = CLOCK + H.PER_FRIEND + 1
SENT = {}
slash("væk")
check(#sentWith("XV;Mathias;Jeppe;") == 1, "/wc4ever væk vækker den, der har sovet længst")
CLOCK = CLOCK + H.PER_FRIEND + 1
SENT = {}
slash("wake jep")
check(#sentWith("XV;Mathias;Jeppe;") == 1, "/wc4ever wake jep")
PRINTS = {}
slash("væk xyz")
check(printed("Hvem?"), "ukendt ven")
H.MakeDemo()
local demos = 0
for _, e in ipairs(db.hjemmesko.log) do if e.demo then demos = demos + 1 end end
check(demos >= 1, "demo-prik")
SENT = {}
H.SendLog()
for _, m in ipairs(sentWith("XV;")) do check(not m:find("demo"), "demo sendes aldrig") end
H.ClearDemo()
for _, e in ipairs(db.hjemmesko.log) do check(not e.demo, "demo fjernet") end
for _, st in pairs(H.afk) do check(not st.demo, "demo-søvn fjernet") end
H.Reset()
check(#db.hjemmesko.log == 0, "nulstil")
-- Uden de API'er, der måske mangler, sker der ingen fejl
UnitIsAFK, IsResting = nil, nil
H.Check()
check(H.mine.since == nil, "uden UnitIsAFK/IsResting: aldrig AFK")
return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
