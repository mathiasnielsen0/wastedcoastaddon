# Sprogtest: med engelsk valgt må der ikke stå dansk nogen steder i vinduer, tooltips,
# popups eller chatbeskeder. Med standardindstillingen er alt stadig på dansk.
# Kør: pip install lupa && python3 tests/test_language.py WastedCoast [forever]
import sys, re, lupa.lua51 as L
from wowmock import MOCK, load_addon

ADDON = sys.argv[1]
FOREVER = len(sys.argv) > 2 and sys.argv[2] == "forever"

FOREVER_MOCK = '''
function GetBuildInfo() return "1.60.0", "1", "", 16001 end
C_Item = {
  GetItemInfo = GetItemInfo, IsEquippableItem = IsEquippableItem, IsEquippedItem = IsEquippedItem,
  GetItemCount = GetItemCount, GetItemIconByID = GetItemIcon,
}
GetItemInfo, IsEquippableItem, IsEquippedItem, GetItemCount, GetItemIcon = nil, nil, nil, nil, nil
'''

# Fanger alt, hvad addonet viser: tekst i frames, tooltips, popups og chat
CAPTURE = '''
FONTS = {}
do
    local mt = getmetatable(UIParent)
    local base = mt.__index
    mt.__index = function(t, k)
        if k == "CreateFontString" then
            return function() local o = setmetatable({ scripts = {}, shown = true, events = {} }, mt) FONTS[#FONTS+1] = o return o end
        end
        return base(t, k)
    end
end
TT = {}
local function grab(self, ...) for i = 1, select("#", ...) do local v = select(i, ...) if type(v) == "string" then TT[#TT+1] = v end end end
GameTooltip.AddLine = grab
GameTooltip.AddDoubleLine = grab
GameTooltip.SetText = grab
POPUPS = {}
StaticPopupDialogs = {}
function StaticPopup_Show(name) POPUPS[#POPUPS+1] = StaticPopupDialogs[name] end
RELOADED = 0
function ReloadUI() RELOADED = RELOADED + 1 end
'''

SCENARIO = r'''
local ns, preset = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
if preset then WastedCoastDB = { settings = { lang = preset } } end
Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
TOASTS = {}
local realToast = ns.Toast
ns.Toast = function(o) TOASTS[#TOASTS+1] = o return realToast(o) end
local slash = SlashCmdList["WASTEDCOAST"]
-- Demo-data, så alle sider har indhold
slash("demo")
RunTimers()
ns.frame:Show()
local function hoverAll()
    for _, f in ipairs(FRAMES) do
        if f.scripts.OnEnter then pcall(f.scripts.OnEnter, f) end
    end
end
for i = 1, #ns.pages do
    pcall(ns.ShowTab, i)
    if ns.RefreshUI then pcall(ns.RefreshUI) end
    hoverAll()
end
-- Klik på kort, instanser og lignende (viser undersider)
for _, f in ipairs(FRAMES) do
    if f.scripts.OnClick and rawget(f, "friend") then pcall(f.scripts.OnClick, f, "LeftButton") end
end
for i = 1, #ns.pages do pcall(ns.ShowTab, i) hoverAll() end
-- Kommandoer (hver to gange, så indstillinger kommer tilbage, hvor de var)
for _, c in ipairs({ "status", "sound", "toast", "loottoast", "raretoast", "kanal", "minimap", "stil",
                     "announce", "annonce", "emotes", "sladder fra", "sladder til" }) do slash(c) slash(c) end
for _, c in ipairs({ "testtoast", "testannonce", "test", "testloot", "loot", "loot epic", "loot rare", "efternavn",
                     "angrib", "angrib nick", "sound death", "sound xyz", "reset", "hjælp", "sync", "sladder" }) do
    pcall(slash, c)
    RunTimers()
end
if ns.ShowGroupWindow then ns.ShowGroupWindow() end
if ns.RefreshGroupWindow then ns.RefreshGroupWindow(true) end
if ns.options and ns.options.scripts.OnShow then ns.options.scripts.OnShow(ns.options) end
if ns.ShowGossip then pcall(ns.ShowGossip, false) end
-- Netværk: en vens død, loot og level, så annoncer og popups bliver bygget
Fire("CHAT_MSG_ADDON", "WCOAST", "D;net-1;Nickchar;WARRIOR;Hogger;Nærkamp;9;12;Westfall;" .. NOW .. ";Nick", "GUILD", "Nickchar")
RunTimers()
hoverAll()
for i = 1, #ns.pages do pcall(ns.ShowTab, i) end
return db
'''

def runtime(preset):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if FOREVER:
        lua.execute(FOREVER_MOCK)
    lua.execute(CAPTURE)
    ns = lua.table()
    load_addon(lua, ADDON, ns)
    db = lua.execute(SCENARIO, ns, preset)
    return lua, ns, db

def texts(lua):
    out = []
    g = lua.globals()
    for f in g.FRAMES.values():
        t = f.text_
        if isinstance(t, str): out.append(t)
    for f in g.FONTS.values():
        t = f.text_
        if isinstance(t, str): out.append(t)
    out += [s for s in g.PRINTS.values() if isinstance(s, str)]
    out += [s for s in g.TT.values() if isinstance(s, str)]
    for o in g.TOASTS.values():
        for k in ("head", "title", "text"):
            if isinstance(o[k], str): out.append(o[k])
    return out

# Ord, der kun findes på dansk (navne som Søren og selve sprognavnet Dansk er tilladt)
DANISH = re.compile(r"[æøåÆØÅ]|\b(og|ikke|endnu|med|der|har|kan|af|på|til|fra|er|den|det|ingen|Ingen|siden|"
                    r"venner|vennerne|gruppe|gruppen|Skriv|Vis|slå|Klik|Hold|musen|karakterer|dødsfald|Døde|"
                    r"Venner|Indstillinger|Opdater|Sjov|Død|Rangliste|Trofæer|Spilletid|sladder|Sladder|lige|nu)\b")
ALLOWED = re.compile(r"Søren|\bSø\b|Dansk|/wc4ever sprog da|Sprog|Honor Hold|Timbermaw Hold")

PASSES = 0
def check(cond, msg):
    global PASSES
    if not cond:
        raise SystemExit("FAIL: " + msg)
    PASSES += 1

# ---------- Engelsk ----------
lua, ns, db = runtime("en")
g = lua.globals()
check(ns.lang == "en", "engelsk er valgt fra indstillingerne")
check(ns.L("Venner") == "Friends", "L oversætter")
bad = {}
seen = texts(lua)
check(len(seen) > 500, "testen ser mange tekster (%d)" % len(seen))
for s in seen:
    clean = re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|H[^|]*\|h|\|h|\|T[^|]*\|t", " ", s)
    clean = ALLOWED.sub(" ", clean)
    if DANISH.search(clean):
        bad[s] = True
check(not bad, "dansk tekst i engelsk tilstand:\n  " + "\n  ".join(sorted(bad)[:60]))
# Fanerne og trofæerne er oversat
tabs = [t for t in seen if t in ("Friends", "Rankings", "Fun", "Death")]
check(len(set(tabs)) == 4, "fanerne er på engelsk")
check(any("OBITUARY" == t for t in seen), "dødsannoncen er på engelsk")
# Skift tilbage til dansk med kommandoen: gemmes og beder om /reload
g.SlashCmdList["WASTEDCOAST"]("language da")
check(db.settings.lang == "da", "/wc4ever language da gemmer dansk")
check(len(list(g.POPUPS.values())) == 1, "der spørges om genindlæsning")
popup = list(g.POPUPS.values())[0]
check("Genindlæs" in popup.button1, "popuppen er på det nye sprog: " + popup.button1)
popup.OnAccept()
check(g.RELOADED == 1, "Genindlæs nu kalder ReloadUI")
check(ns.ParseLanguage("English") == "en" and ns.ParseLanguage("dansk") == "da" and ns.ParseLanguage("x") is None, "sprognavne tolkes")

# ---------- Dansk (standard) ----------
lua, ns, db = runtime(None)
g = lua.globals()
check(ns.lang == "da" and db.settings.lang is None, "dansk er standard")
seen = texts(lua)
check("Venner" in seen and "Rangliste" in seen, "fanerne er på dansk")
check(any("DØDSANNONCE" == t for t in seen), "dødsannoncen er på dansk")
check(not any(t == "Friends" for t in seen), "ingen engelske faner på dansk")
g.SlashCmdList["WASTEDCOAST"]("sprog en")
check(db.settings.lang == "en", "/wc4ever sprog en gemmer engelsk")
popup = list(g.POPUPS.values())[0]
check(popup.button1 == "Reload now", "popuppen er på engelsk, når man vælger engelsk")
# Valg af det sprog, der allerede er i brug, kræver ingen genindlæsning
g.SlashCmdList["WASTEDCOAST"]("sprog da")
check(len(list(g.POPUPS.values())) == 1, "ingen ny popup, når sproget ikke skifter")

print("OK,", PASSES, "checks passed", "(forever)" if FOREVER else "")
