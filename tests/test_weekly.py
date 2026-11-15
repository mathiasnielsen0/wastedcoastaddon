# Test af ugens pokaler (Weekly.lua): dansk uge-tid, pokalerne, lige stilling, spilletid og levels
# via XW, uddelingen, kort, tooltips, nyheder, siden, låsning og at alle får de samme vindere.
# Kør: pip install lupa && python3 tests/test_weekly.py WastedCoast [forever]
import sys, calendar, lupa.lua51 as L
from wowmock import MOCK, load_addon

ADDON = sys.argv[1]
FOREVER = len(sys.argv) > 2 and sys.argv[2] == "forever"

def utc(y, mo, d, h=0, mi=0):
    return calendar.timegm((y, mo, d, h, mi, 0))

# Ugen, der slutter søndag 15/11-2026 kl. 20 dansk tid (19 UTC), er ISO-uge 46
END46 = utc(2026, 11, 15, 19)
START46 = END46 - 7 * 86400

def runtime():
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
''')
    ns = lua.table()
    load_addon(lua, ADDON, ns)
    return lua, ns

SETUP = r'''
local ns, START, END = ...
NOW = START + 3600
Fire("ADDON_LOADED", "WastedCoast")
WastedCoastDB.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
TOASTS = {}
local realToast = ns.Toast
ns.Toast = function(o) TOASTS[#TOASTS+1] = o return realToast(o) end
'''

# Ugens data. reverse = indsæt i omvendt rækkefølge (som hos en ven, der fik synken i en anden orden)
DATA = r'''
local ns, START, END, reverse = ...
local db = WastedCoastDB
local function at(h) return START + h * 3600 end
local events = {
    -- Nick og Frode dør begge 3 gange; Frode nåede det først
    { id = "d1", name = "Nickchar", friend = "Nick", killer = "Hogger", level = 30, klvl = 28, time = at(10) },
    { id = "d2", name = "Nickchar", friend = "Nick", killer = "Hogger", level = 30, klvl = 29, time = at(20) },
    { id = "d3", name = "Nickchar", friend = "Nick", killer = "Murloc Forager", level = 31, klvl = 12, time = at(100) },
    { id = "d4", name = "Frodechar", friend = "Frode", killer = "Defias", level = 40, klvl = 39, time = at(11) },
    { id = "d5", name = "Frodechar", friend = "Frode", killer = "Defias", level = 40, klvl = 39, time = at(12) },
    { id = "d6", name = "Frodechar", friend = "Frode", killer = "Gankmaster", level = 40, klvl = 10, pvp = true, time = at(13) },
    -- Uden for ugen: tæller ikke
    { id = "d7", name = "Rasmuschar", friend = "Rasmus", killer = "Hogger", level = 30, klvl = 30, time = START - 10 },
    { id = "d8", name = "Rasmuschar", friend = "Rasmus", killer = "Hogger", level = 30, klvl = 30, time = START - 20 },
    { id = "d9", name = "Rasmuschar", friend = "Rasmus", killer = "Hogger", level = 30, klvl = 30, time = START - 30 },
    { id = "d10", name = "Rasmuschar", friend = "Rasmus", killer = "Hogger", level = 30, klvl = 30, time = END },
    -- Demo tæller aldrig i pokalskabet
    { id = "demo-1", name = "Jeppechar", friend = "Jeppe", killer = "Hogger", level = 30, klvl = 30, time = at(5) },
    { id = "demo-2", name = "Jeppechar", friend = "Jeppe", killer = "Hogger", level = 30, klvl = 30, time = at(6) },
    { id = "demo-3", name = "Jeppechar", friend = "Jeppe", killer = "Hogger", level = 30, klvl = 30, time = at(7) },
    { id = "demo-4", name = "Jeppechar", friend = "Jeppe", killer = "Hogger", level = 30, klvl = 30, time = at(8) },
}
local loot = {
    { id = "l1", friend = "Søren", char = "Sø", item = "item:1", name = "A", quality = 3, time = at(30) },
    { id = "l2", friend = "Søren", char = "Sø", item = "item:2", name = "B", quality = 4, time = at(31) },
    { id = "l3", friend = "Mikkel", char = "Mik", item = "item:3", name = "C", quality = 4, time = at(32) },
    -- Grønne items tæller ikke (minimumskvaliteten er en lokal indstilling)
    { id = "l4", friend = "Mikkel", char = "Mik", item = "item:4", name = "D", quality = 2, time = at(33) },
    { id = "l5", friend = "Mikkel", char = "Mik", item = "item:5", name = "E", quality = 2, time = at(34) },
}
local function put(list, src)
    if reverse then for i = #src, 1, -1 do list[#list + 1] = src[i] end
    else for _, x in ipairs(src) do list[#list + 1] = x end end
end
put(db.events, events)
put(db.loot, loot)
db.needShame = db.needShame or {}
put(db.needShame, { { id = "n1", friend = "Andreas", time = at(40) }, { id = "n2", friend = "Andreas", time = at(41) },
                    { id = "n3", friend = "Nick", time = at(42) } })
db.duels = db.duels or {}
db.duels.Jeppe = { { id = "u1", won = true, t = at(50) }, { id = "u2", won = true, t = at(51) }, { id = "u3", won = false, t = at(52) } }
db.duels.Nick = { { id = "u4", won = true, t = at(53) } }
db.rareLog = db.rareLog or {}
put(db.rareLog, { { friend = "Mikkel", mob = "Rak'shiri", t = at(60) } })
db.stomi = db.stomi or { log = {} }
db.stomi.log = db.stomi.log or {}
db.haan = db.haan or { log = {} }
db.haan.log = db.haan.log or {}
put(db.haan.log, { { id = "Frode-1", from = "Frode", to = "Nick", t = at(80) }, { id = "Frode-2", from = "Frode", to = "Søren", t = at(81) },
                   { id = "Frode-2", from = "Frode", to = "Søren", t = at(81) },   -- samme prut to gange
                   { id = "Nick-1", from = "Nick", to = "Frode", t = at(82) } })
put(db.stomi.log, { { id = "s1", from = "Mathias", to = "Nick", r = "y", t = at(70) },
                    { id = "s2", from = "Mathias", to = "Frode", r = "y", t = at(71) },
                    { id = "s3", from = "Andreas", to = "Nick", r = "y", t = at(72) },
                    { id = "s4", from = "Andreas", to = "Nick", r = "n", t = at(73) } })
'''

PASSES = 0
def check(cond, msg):
    global PASSES
    if not cond:
        raise SystemExit("FAIL: " + msg)
    PASSES += 1

lua, ns = runtime()
G = lua.globals()
lua.execute(SETUP, ns, START46, END46)
W = ns.Weekly
def num(n): return W.Number(n)[0]

# ---------- Tid ----------
check(W.Offset(utc(2026, 1, 10)) == 3600, "vintertid: UTC+1")
check(W.Offset(utc(2026, 7, 10)) == 7200, "sommertid: UTC+2")
check(W.Offset(utc(2026, 3, 29, 0, 59)) == 3600 and W.Offset(utc(2026, 3, 29, 1)) == 7200, "sommertid starter 29/3-2026 kl. 01 UTC")
check(W.Offset(utc(2026, 10, 25, 0, 59)) == 7200 and W.Offset(utc(2026, 10, 25, 1)) == 3600, "sommertid slutter 25/10-2026 kl. 01 UTC")
n46 = W.Index(END46 - 1)
check(W.Index(END46) == n46 + 1, "ugen skifter søndag kl. 20 dansk tid")
check(W.End(n46) == END46 and W.Start(n46) == START46, "start og slut i UTC")
check(num(n46) == 46, "ISO-uge 46, fik %s" % num(n46))
# Sommer: søndag 12/7-2026 kl. 20 = 18 UTC
s28 = utc(2026, 7, 12, 18)
check(W.Index(s28) == W.Index(s28 - 1) + 1 and W.End(W.Index(s28 - 1)) == s28, "sommeruge slutter kl. 18 UTC")
check(num(W.Index(s28 - 1)) == 28, "uge 28")
# Ugen hen over sommertidens slutning er 7 døgn og en time
w44 = W.Index(utc(2026, 10, 25, 12))
check(W.End(w44) - W.Start(w44) == 7 * 86400 + 3600, "ugen med vintertid er en time længere")
# Årsskifte: uge 53 i 2026 og uge 1 i 2027
check(num(W.Index(utc(2027, 1, 2, 12))) == 53, "2/1-2027 ligger i uge 53")
check(num(W.Index(utc(2027, 1, 9, 12))) == 1, "9/1-2027 ligger i uge 1")
y, m, d = W.CivilFromDays(W.DaysFromCivil(2024, 2, 29))
check((y, m, d) == (2024, 2, 29), "kalenderregning frem og tilbage")

# ---------- Pokalerne ----------
lua.execute(DATA, ns, START46, END46, False)
# Spilletid og levels fra vennerne (XW), og ugyldige beskeder ignoreres
def msg(m):
    G.Fire("CHAT_MSG_ADDON", "WCOAST", m, "GUILD", "X")
msg("XW;Andreas;%d;%d;%d" % (n46, 9 * 3600, 3))
msg("XW;Andreas;%d;%d;%d" % (n46, 5 * 3600, 1))         # ældre, mindre tal: det største vinder
msg("XW;Søren;%d;%d;%d" % (n46, 3 * 3600, 0))
msg("XW;Nick;%d;%d;%d" % (n46, 12 * 3600, 2))
msg("XW;Mikkel;%d;%d;%d" % (n46, 30 * 60, 5))
msg("XW;Ukendt;%d;%d;%d" % (n46, 99 * 3600, 9))
msg("XW;Jeppe;%d;%d;%d" % (n46, 8 * 86400, 1))         # mere end en uge: umuligt
msg("XW;Jeppe;%d;%d;%d" % (n46 + 5, 3600, 1))          # en uge i fremtiden
msg("XW;Mathias;%d;%d;%d" % (n46, 99 * 3600, 9))        # dine egne tal måler du selv
res = W.Compute(n46, False)
w = res.w
def win(cup): return w[cup] and w[cup].f
check(win("dead") == "Frode" and w["dead"].v == 3, "Frode nåede 3 dødsfald før Nick: %s" % win("dead"))
check(res.rank["dead"][2].f == "Nick" and res.rank["dead"][2].v == 3, "Nick er nummer to")
check(win("shame") == "Nick" and w["shame"].v == 19 and w["shame"].k == "Murloc Forager", "pinligste død: Nick til level 12 (PvP tæller ikke)")
check(W.ValueText("shame", w["shame"]) == "level 12 Murloc Forager (selv 31)", W.ValueText("shame", w["shame"]))
check(win("loot") == "Søren" and w["loot"].v == 2, "loot-goblin: Søren (grønne items tæller ikke)")
check(win("need") == "Andreas" and w["need"].v == 2, "need-goblin: Andreas")
check(win("duel") == "Jeppe" and w["duel"].v == 2, "duel-kongen: Jeppe")
check(win("rare") == "Mikkel", "rare-jægeren: Mikkel")
check(win("stomiG") == "Mathias" and w["stomiG"].v == 2, "stomi-mesteren: Mathias")
check(win("stomiR") == "Nick" and w["stomiR"].v == 2, "stomi-patienten: Nick (et nej tæller ikke)")
check(win("played") == "Nick" and w["played"].v == 12 * 3600, "ugens nolifer: Nick")
check(win("haan") == "Frode" and w["haan"].v == 2, "prut-kongen: Frode (samme prut tæller én gang)")
check(win("ding") == "Mikkel" and w["ding"].v == 5, "ding-maskinen: Mikkel")
check(win("immortal") == "Andreas" and w["immortal"].v == 9 * 3600, "udødelig: Andreas (Nick døde, Mikkel spillede for lidt)")
check(W.ValueText("played", w["played"]) == "12t 0m", W.ValueText("played", w["played"]))
check(not res.rank["dead"] or all(x.f != "Jeppe" and x.f != "Rasmus" for x in res.rank["dead"].values()), "demo og andre uger tæller ikke")
withDemo = W.Compute(n46, True).w
check(withDemo["dead"].f == "Jeppe" and withDemo["dead"].v == 4, "med demo-data (kun denne uges live-visning)")

# ---------- Samme vindere hos alle, uanset rækkefølgen data kom i ----------
lua2, ns2 = runtime()
lua2.execute(SETUP, ns2, START46, END46)
lua2.execute(DATA, ns2, START46, END46, True)
for m in ("XW;Nick;%d;%d;%d" % (n46, 12 * 3600, 2), "XW;Mikkel;%d;%d;%d" % (n46, 30 * 60, 5),
          "XW;Søren;%d;%d;%d" % (n46, 3 * 3600, 0), "XW;Andreas;%d;%d;%d" % (n46, 9 * 3600, 3)):
    lua2.globals().Fire("CHAT_MSG_ADDON", "WCOAST", m, "GUILD", "X")
# Mathias' egen stomi-pokal er data, ikke en XW-besked, så den anden klient har samme grundlag
w2 = ns2.Weekly.Compute(n46, False).w
for cup in ("dead", "shame", "loot", "need", "duel", "rare", "stomiG", "stomiR", "haan", "played", "ding", "immortal"):
    a, b = w[cup], w2[cup]
    check((a and a.f) == (b and b.f) and (a and a.v) == (b and b.v), "samme vinder hos begge: " + cup)

# ---------- Din egen spilletid og dine levels ----------
lua.execute(r'''
local ns = ...
local db = WastedCoastDB
db.friends.Mathias = db.friends.Mathias or { chars = {} }
db.friends.Mathias.chars.Mathiasx = { class = "WARRIOR", level = 40, played = { t = 100000, l = 10, at = NOW } }
db.friends.Mathias.chars.Altx = { class = "WARRIOR", level = 10, played = { t = 5000, l = 10, at = NOW } }
local m = ns.Weekly.Track(NOW)
assert(m.p == 0, "første måling er udgangspunktet")
db.friends.Mathias.chars.Mathiasx.played.t = 100000 + 7200
db.friends.Mathias.chars.Altx.played.t = 5000 + 1800
m = ns.Weekly.Track(NOW)
assert(m.p == 9000, "to timer på main og en halv på alt: " .. m.p)
Fire("PLAYER_LEVEL_UP", 41)
SENT = {}
ns.Weekly.Send()
''', ns)
mine = G.WastedCoastDB.weekly.rep[n46]["Mathias"]
check(mine.p == 9000 and mine.l == 1, "dine tal står i ugens rapport")
def pump():
    for _ in range(600):
        for tk in G.TICKERS.values():
            if tk.d == 0.3: tk.f()
pump()
sent = [s.msg for s in G.SENT.values() if s.msg.startswith("XW;")]
check("XW;Mathias;%d;9000;1" % n46 in sent, "XW sendes: %s" % sent)
G.SENT = lua.table()
ns.SendMyExtras(True)
pump()
check(any(s.msg.startswith("XW;Mathias;") for s in G.SENT.values()), "XW sendes også ved synk")

# ---------- Uddelingen ----------
G.NOW = END46 - 10
lua.execute("local ns = ...; ns.Weekly.Tick()", ns)
G.SENT = lua.table()
G.NOW = END46 + 30
G.TOASTS = lua.table()
lua.execute("local ns = ...; ns.Weekly.Tick()", ns)
pump()
check(any(s.msg.startswith("XW;Mathias;%d;" % n46) for s in G.SENT.values()), "ved ugeskiftet sendes den afsluttede uges tal")
check(len(G.TOASTS) == 0, "ingen uddeling de første minutter")
G.NOW = END46 + 200
G.PRINTS = lua.table()
lua.execute("local ns = ...; ns.Weekly.Tick()", ns)
toasts = list(G.TOASTS.values())
check(len(toasts) == 1 and toasts[0].kind == "trophy", "uddelings-toast")
t = toasts[0]
check("UGE 46" in t.head, t.head)
check(t.title == "Du vandt en pokal!" and "Stomi-mesteren" in t.text, "du vandt stomi-mesteren: %s / %s" % (t.title, t.text))
prints = list(G.PRINTS.values())
check(any("Ugens pokaler (uge 46)" in p for p in prints), "chatbesked om uddelingen")
check(any("Kirkegårdens stamgæst" in p and "Frode" in p for p in prints), "alle vindere står i chatten")
lua.execute("local ns = ...; ns.Weekly.Tick()", ns)
check(len(G.TOASTS) == 1, "uddelingen vises kun én gang")
check(G.WastedCoastDB.weekly.shown == n46, "husker den viste uge")

# ---------- Kort, tooltips, nyheder og bande-baren ----------
won = ns.Weekly.Won("Nick")[0]
names = [x.cup.name for x in won.values()]
check(names == ["Ugens pinligste død", "Ugens nolifer", "Stomi-patienten"], "Nicks pokaler i fast rækkefølge: %s" % names)
lines = list(ns.Weekly.TooltipLines("Nick").values())
check(lines[0] == "Ugens pokaler (uge 46)" and any("Ugens nolifer" in l for l in lines), "tooltip: %s" % lines)
check(any("Pokalskabet: 3 i alt" in l for l in lines), "pokalskabet i tooltippen")
r = list(ns.Weekly.TooltipLines("Rasmus").values())
check(r == ["Pokalskabet: 1 i alt"], "Rasmus vandt ugen før (dødsfald før uge 46), men intet i uge 46: %s" % r)
lua.execute('''
local ns = ...
ns.frame:Show()
ns.ShowTab(1)
''', ns)
def card_of(friend):
    for lst in (ns.cards, ns.offCards):
        for c in lst.values():
            if c.shown is not False and c.friend == friend: return c
c = card_of("Nick")
check(c is not None and c.cup.shown is True and c.cupN.text_ == "|cffffd1003x|r", "pokal og 3x på Nicks kort")
check(card_of("Rasmus").cup.shown is False, "ingen pokal på Rasmus' kort")
G.TT = lua.table()
c.scripts.OnEnter(c)
check(any(isinstance(s, str) and "Ugens pokaler (uge 46)" in s for s in G.TT.values()), "pokaler i kortets tooltip")
items = ns.Bar.Items(G.NOW)
news = [i.text for i in items.values() if i.key == "w%d" % n46]
check(len(news) == 1 and "uge 46" in news[0] and "Nick" in news[0] and "3" in news[0], "én nyhed om uddelingen: %s" % news)
bar_lines = ns.Bar.TooltipLines(lua.eval('{ name = "Nick", disp = "Nick", class = "MAGE", char = "Nickchar", level = 31, online = true }'), G.NOW)
check(any(l[1] == "Ugens pokaler" and "Ugens nolifer" in (l[2] or "") for l in bar_lines.values()), "bande-barens tooltip")

# ---------- Siden ----------
lua.execute('''
local ns = ...
ns.ShowTab(18)
''', ns)
ui = ns.Weekly.ui
check(ns.subTabs[5][4].active, "Ugens pokaler ligger under Sjov")
check("Frode" in ui.last[1].who.text_ and "3 dødsfald" in ui.last[1].who.text_, "sidste uge: Frode: %s" % ui.last[1].who.text_)
check(ui.lastSub.text_ == "uge 46", ui.lastSub.text_)
check("uddeles om" in ui.nowSub.text_, ui.nowSub.text_)
check("Nick" in ui.cabinet.text_.split("\n")[0], "Nick øverst i pokalskabet: %s" % ui.cabinet.text_)
G.TT = lua.table()
ui.last[1].scripts.OnEnter(ui.last[1])
tt = list(G.TT.values())
check(any("1. Frode" in s for s in tt) and any("2. Nick" in s for s in tt), "top 5 i tooltippen: %s" % tt)
G.SlashCmdList["WASTEDCOAST"]("pokaler")
check(any("Kirkegårdens stamgæst" in p for p in G.PRINTS.values()), "/wc4ever pokaler")

# ---------- Låsning: en uge kan rettes i en uge, derefter står den fast ----------
lua.execute('''
local ns, START = ...
table.insert(WastedCoastDB.events, { id = "late", name = "Nickchar", friend = "Nick", killer = "Hogger", level = 31, klvl = 31, time = START + 150 * 3600 })
table.insert(WastedCoastDB.events, { id = "late2", name = "Nickchar", friend = "Nick", killer = "Hogger", level = 31, klvl = 31, time = START + 151 * 3600 })
ns.Weekly.Update()
''', ns, START46)
check(ns.Weekly.Winners(n46)["dead"].f == "Nick", "data, der kommer for sent, tæller med den første uge")
G.NOW = END46 + 8 * 86400
G.CLOCK = G.CLOCK + 600
lua.execute("local ns = ...; ns.Weekly.Update()", ns)
check(G.WastedCoastDB.weekly.hist[n46].fz, "ugen er låst efter en uge")
lua.execute('''
local ns, START = ...
for i = 1, 5 do
    table.insert(WastedCoastDB.events, { id = "later" .. i, name = "Frodechar", friend = "Frode", killer = "Hogger", level = 31, klvl = 31, time = START + i * 3600 })
end
ns.Weekly.Update()
''', ns, START46)
check(ns.Weekly.Winners(n46)["dead"].f == "Nick", "en låst uge ændrer sig ikke")
check(len(ns.Weekly.Won("Nick")[0]) == 0, "efter næste uddeling er Nicks pokaler væk fra kortet")

# ---------- Nulstilling ----------
G.SlashCmdList["WASTEDCOAST"]("reset ja")
check(not lua.eval("next")(ns.Weekly.Winners(n46)) and not G.WastedCoastDB.weekly.rep[n46], "reset sletter pokalskabet")

print("OK,", PASSES, "checks passed", "(forever)" if FOREVER else "")
