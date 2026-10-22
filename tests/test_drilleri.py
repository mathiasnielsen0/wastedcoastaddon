# Test af addonet med en lille WoW-attrap. Kør: pip install lupa && python3 tests/test_drilleri.py WastedCoast [native]
import sys, lupa.lua51 as L

ADDON = sys.argv[1]
lua = L.LuaRuntime(unpack_returned_tuples=True)

MOCK = r'''
NOW = 1800000000
CLOCK = 1000
SENT = {}
PRINTS = {}
TIMERS = {}
TICKERS = {}
FRAMES = {}
EMOTES = {}
function time() return NOW end
date = os.date
function GetTime() return CLOCK end
function GetBuildInfo() return "2.5.5", "1", "", 20506 end
local real_print = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end PRINTS[#PRINTS+1] = table.concat(t, " ") end
PLAYER = "Mathiasx"
function UnitName(u) if u == "player" then return PLAYER end if u == "target" then return TARGET_NAME end end
function UnitClass(u) return "Warrior", "WARRIOR" end
function UnitLevel(u) if u == "target" then return TARGET_LEVEL end return 40 end
function UnitExists(u) if u == "target" then return TARGET_NAME ~= nil end return false end
function UnitGUID() return "guid" end
function UnitXP() return 10 end
function UnitXPMax() return 100 end
function UnitIsAFK() return false end
function UnitAffectingCombat() return false end
function GetMoney() return 12345 end
function GetZoneText() return "Westfall" end
function IsInRaid() return false end
function IsInGroup() return true end
function IsInGuild() return true end
function GetChannelName() return 0 end
function ChatFrame_AddMessageEventFilter() end
function GetNumGroupMembers() return 0 end
function IsInInstance() return false, "none" end
function strsplit(sep, s, n)
  local res, i = {}, 1
  if n then
    local a, b = s:find(sep, 1, true)
    if a then return s:sub(1, a-1), s:sub(b+1) end
    return s
  end
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do res[#res+1] = part end
  return unpack(res)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_ChatInfo = {
  SendAddonMessage = function(prefix, msg, ch, target) SENT[#SENT+1] = { msg = msg, ch = ch, target = target } end,
  RegisterAddonMessagePrefix = function() return true end,
}
C_Timer = {
  After = function(d, f) TIMERS[#TIMERS+1] = f end,
  NewTicker = function(d, f) TICKERS[#TICKERS+1] = { d = d, f = f } return {} end,
}
function RunTimers() local n = 0 while #TIMERS > 0 and n < 200 do local f = table.remove(TIMERS, 1) f() n = n + 1 end end
ITEMS = {}  -- id -> { equip = bool, count = n, equipped = bool }
function GetItemInfo(x) local id = tonumber(tostring(x):match("(%d+)")) if ITEMS[id] then return "Item" .. id, nil, 3 end end
function IsEquippableItem(id) return ITEMS[id] and ITEMS[id].equip end
function IsEquippedItem(id) return ITEMS[id] and ITEMS[id].equipped end
function GetItemCount(id) return ITEMS[id] and ITEMS[id].count or 0 end
function GetItemIcon() return "icon" end
function DoEmote(token, unit) EMOTES[#EMOTES+1] = token .. ">" .. tostring(unit) end
function PlaySound() end
function PlaySoundFile() return true end
SOUNDKIT = { RAID_WARNING = 1, LEVELUP = 2 }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
LOCALIZED_CLASS_NAMES_MALE = {}
UISpecialFrames = {}
SlashCmdList = {}
YOU = "You"
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ITEM_SELF = "You receive loot: %s."

local frameMT
local function newObj()
  local o = { scripts = {}, shown = true, events = {} }
  return setmetatable(o, frameMT)
end
frameMT = { __index = function(t, k)
  if k == "SetScript" then return function(self, name, f) self.scripts[name] = f end end
  if k == "GetScript" then return function(self, name) return self.scripts[name] end end
  if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
  if k == "CreateTexture" or k == "CreateFontString" then return function() return newObj() end end
  if k == "SetText" then return function(self, s) self.text_ = s end end
  if k == "GetText" then return function(self) return self.text_ end end
  if k == "Show" then return function(self) self.shown = true end end
  if k == "Hide" then return function(self) self.shown = false end end
  if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
  if k == "IsShown" then return function(self) return self.shown end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "GetChecked" then return function() return false end end
  return function() end
end }
function CreateFrame(kind, name, parent)
  local f = newObj()
  FRAMES[#FRAMES+1] = f
  if name then _G[name] = f end
  return f
end
UIParent = newObj()
Minimap = newObj()
Minimap.GetCenter = function() return 0, 0 end
Minimap.GetEffectiveScale = function() return 1 end
function GetCursorPosition() return 10, 20 end
GameTooltip = newObj()
function Fire(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
'''

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
for f in ["Sounds.lua", "WastedCoast.lua", "Drilleri.lua", "Dueller.lua"]:
    code = open(f"{ADDON}/{f}", encoding="utf-8").read()
    fn = lua.eval("function(code, name) local f, err = loadstring(code, name) if not f then error(err) end return f end")(code, "@" + f)
    fn("WastedCoast", ns)

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
local realToast = ns.Toast
ns.Toast = function(o) ns.toastsSeen[#ns.toastsSeen+1] = o return realToast(o) end

-- Sider: 13 (fordelt på 4 faner), og Drilleri-siden findes
check(#ns.pages == 14 and #ns.tabs == 4, "14 sider på 4 faner")
ns.frame:Show()
for i = 1, 13 do ns.ShowTab(i) end

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
check(ns.cards[3].hat.shown == true, "hat-ikon på Nicks kort")
check(ns.cards[2].hat.shown == false, "intet hat-ikon på Mathias")

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
check(ns.cards[5].name:GetText():find("Turtle"), "snegl ved Frodes navn")
check(not ns.cards[3].name:GetText():find("Turtle"), "ingen snegl ved Nick")
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

-- Demo til og fra
SlashCmdList.WASTEDCOAST("demo")
ns.ShowTab(13)
ns.ShowTab(1)

-- Hele vinduet kan tegnes med demo-data: alle faner, fade-in og toast-animation
ns.frame:Show()
ns.frame.scripts.OnShow(ns.frame)
check(#ns.tabs == 4, "fire faner")
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
check(ns.tabs[4].active and ns.subTabs[4][2].active, "drilleri hører under Sjov")
local seen = {}
for _, g in ipairs(ns.GROUPS) do for _, pg in ipairs(g.pages) do seen[pg] = true end end
for i = 1, 13 do check(seen[i], "side " .. i .. " kan nås fra en fane") end
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
ns.ShowTab(13)

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

SlashCmdList.WASTEDCOAST("reset ja")
check(#db.needShame == 0, "reset sletter need-synder")
check(next(db.duels) == nil, "reset sletter dueller")
ns.ShowTab(13)
ns.ShowTab(14)
return PASSES
'''
passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed")
