# Test af spilletid pr. dag (Spilletid.lua): måling fra /played, udgangspunkt for nye karakterer,
# dagsskifte i dansk tid, loft over tilvæksten, XP-beskeden (send, modtag, ødelagte), siden med
# grafen, tooltips, demo, /wc4ever timer og nulstilling.
# Kør: pip install lupa && python3 tests/test_spilletid.py WastedCoast [forever]
import sys, calendar, lupa.lua51 as L
from wowmock import MOCK, load_addon

ADDON = sys.argv[1]
FOREVER = len(sys.argv) > 2 and sys.argv[2] == "forever"

def utc(y, mo, d, h=0, mi=0):
    return calendar.timegm((y, mo, d, h, mi, 0))

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
GameTooltip.AddLine = function(_, s) TT[#TT+1] = tostring(s) end
GameTooltip.AddDoubleLine = function(_, a, b) TT[#TT+1] = tostring(a) .. " | " .. tostring(b) end
''')
ns = lua.table()
load_addon(lua, ADDON, ns)
G = lua.globals()

PASSES = 0
def check(cond, msg):
    global PASSES
    if not cond:
        raise SystemExit("FAIL: " + msg)
    PASSES += 1

def pump():
    for _ in range(600):
        for tk in G.TICKERS.values():
            if tk.d == 0.3: tk.f()

def sent(prefix):
    # Samme besked kan gå ad flere veje (kanal og guild): hver tæller én gang
    return list(dict.fromkeys(s.msg for s in G.SENT.values() if s.msg.startswith(prefix)))

def msg(m, char="Nickchar"):
    G.Fire("CHAT_MSG_ADDON", "WCOAST", m, "GUILD", char)

# Søndag 22/11-2026 kl. 11 dansk tid
G.NOW = utc(2026, 11, 22, 10)
lua.execute('''
Fire("ADDON_LOADED", "WastedCoast")
WastedCoastDB.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
''')
PD = ns.PlayedDays
db = G.WastedCoastDB

# ---------- Dage i dansk tid ----------
check(PD.Day(utc(2026, 11, 22, 22, 59)) == PD.Day(utc(2026, 11, 22, 10)), "22:59 UTC er stadig søndag i Danmark (vintertid)")
check(PD.Day(utc(2026, 11, 22, 23, 0)) == PD.Day(utc(2026, 11, 22, 10)) + 1, "kl. 00 dansk tid er en ny dag")
check(PD.Day(utc(2026, 7, 1, 22, 0)) == PD.Day(utc(2026, 7, 1, 12)) + 1, "sommertid: dagen skifter kl. 22 UTC")
today = PD.Day()
check(PD.DayStart(today) == utc(2026, 11, 22, 23) - 86400, "dagens start i UTC")
check(PD.DayLabel(today) == "22/11" and PD.DayLabel(today, True) == "søn 22/11", "dato-tekst: %s" % PD.DayLabel(today, True))

# ---------- Måling ----------
lua.execute('''
local ns = ...
-- En gammel alt med masser af spilletid fra før versionen
local alt = ns.core.UpdateChar("Mathias", "Altx", nil, time())
alt.played = { t = 900000, l = 0, at = time() - 86400 }
ns.OnTimePlayed(100000, 500)
ns.PlayedDays.Track()
''', ns)
check(not db.playedDay or not db.playedDay.Mathias or not db.playedDay.Mathias[today],
      "første måling er kun udgangspunktet (ingen gammel spilletid på én dag)")
check(db.playedDayLast.Mathias.Altx.s == 900000, "altens spilletid huskes som udgangspunkt")
check(db.playedDaySince == G.NOW, "målingen begyndte nu")

G.NOW = G.NOW + 3600
G.CLOCK = G.CLOCK + 3600
lua.execute("local ns = ...; ns.PlayedDays.Track()", ns)
check(db.playedDay.Mathias[today] == 3600, "en times spil: %s" % db.playedDay.Mathias[today])
lua.execute("local ns = ...; ns.PlayedDays.Track()", ns)
check(db.playedDay.Mathias[today] == 3600, "samme måling to gange tæller ikke dobbelt")

# Ticker hvert minut
ticks = [tk for tk in G.TICKERS.values() if tk.d == 60]
check(len(ticks) >= 1, "måling hvert minut")
G.NOW = G.NOW + 60
G.CLOCK = G.CLOCK + 60
for tk in ticks: tk.f()
check(db.playedDay.Mathias[today] == 3660, "tickeren måler: %s" % db.playedDay.Mathias[today])

# Spilletid, der vokser mere end uret (spillet uden addonet): kun op til tiden siden sidst + lidt
G.NOW = G.NOW + 600
G.CLOCK = G.CLOCK + 600
lua.execute('''
local ns = ...
local alt = WastedCoastDB.friends.Mathias.chars.Altx
alt.played.t = alt.played.t + 50000
ns.PlayedDays.Track()
''', ns)
v = db.playedDay.Mathias[today]
check(v <= 3660 + 600 + 600 + PD.SLACK, "tilvækst over uret klippes: %s" % v)
check(v >= 3660 + 600, "men den rigtige tid tæller: %s" % v)
before = v

# Dagsskifte: næste dag kl. 00:30 dansk tid
G.NOW = utc(2026, 11, 22, 23, 30)
G.CLOCK = G.CLOCK + 1800
lua.execute("local ns = ...; ns.PlayedDays.Track()", ns)
check(db.playedDay.Mathias[today + 1] and db.playedDay.Mathias[today] == before, "ny dag får sit eget tal")
check(db.playedDay.Mathias[today + 1] <= 1800 + PD.SLACK, "højst tiden siden sidst")

# ---------- Afsendelse ----------
G.SENT = lua.table()
ns.SendMyExtras(False)
pump()
xp = sent("XP;")
check(len(xp) == 1 and xp[0].startswith("XP;Mathias;"), "XP ved synk: %s" % xp)
check(("%d=%d" % (today, before)) in xp[0] and ("%d=" % (today + 1)) in xp[0], "begge dage i beskeden: %s" % xp)

# Mange dage deles op i beskeder på højst 255 tegn
lua.execute('''
local ns = ...
local r = WastedCoastDB.playedDay.Mathias
local t = ns.PlayedDays.Day()
for d = t - 29, t - 2 do r[d] = 80000 + d % 1000 end
''', ns)
G.SENT = lua.table()
ns.SendMyExtras(False)
pump()
xp = sent("XP;")
days = sum(len(m.split(";")[2].split(",")) for m in xp)
check(len(xp) >= 2 and all(len(m) <= 255 for m in xp), "opdelt i flere beskeder: %s" % [len(m) for m in xp])
check(days == 30, "alle 30 dage sendt: %d" % days)
G.SENT = lua.table()
ns.SendMyExtras(True)
pump()
xp = sent("XP;")
check(len(xp) == 1 and len(xp[0].split(";")[2].split(",")) == 2, "den lette synk: kun i går og i dag: %s" % xp)

# Kvarterets udsendelse sender kun det, der har ændret sig
resend = [tk for tk in G.TICKERS.values() if tk.d == 900]
G.SENT = lua.table()
for tk in resend: tk.f()
pump()
check(not any(m.startswith("XP;Mathias;") for m in sent("XP;")), "intet nyt: ingen XP")
G.NOW = G.NOW + 300
G.CLOCK = G.CLOCK + 300
for tk in resend: tk.f()
pump()
check(len(sent("XP;Mathias;")) >= 1, "ny spilletid: XP hvert kvarter")

# ---------- Modtagelse ----------
t2 = PD.Day()
msg("XP;Nick;%d=3600,%d=7200" % (t2 - 1, t2))
check(db.playedDay.Nick[t2] == 7200 and db.playedDay.Nick[t2 - 1] == 3600, "Nicks dage gemt")
msg("XP;Nick;%d=1000" % t2)
check(db.playedDay.Nick[t2] == 7200, "en mindre værdi vinder ikke")
msg("XP;Nick;%d=9000" % t2)
check(db.playedDay.Nick[t2] == 9000, "en større værdi vinder")
for bad in ["XP;Nick;%d=99999" % t2, "XP;Nick;%d=100" % (t2 + 5), "XP;Nick;%d=100" % (t2 - 999),
            "XP;Nick;abc", "XP;Nick", "XP;Ukendt;%d=100" % t2, "XP;Mathias;%d=1" % (t2 - 3), "XP;;", "XP;Nick;-5=10"]:
    msg(bad)
check(db.playedDay.Nick[t2] == 9000 and not db.playedDay.Nick[t2 + 5] and not db.playedDay.Nick[t2 - 999], "ødelagte XP ignoreres")
check(not db.playedDay["Ukendt"], "ukendt ven ignoreres")
check(db.playedDay.Mathias[t2 - 3] != 1, "dine egne tal kan ikke overskrives udefra")

# ---------- Siden ----------
lua.execute('''
local ns = ...
ns.frame:Show()
ns.ShowTab(21)
''', ns)
ui = PD.ui
check(ns.subTabs[2][3].active and ns.subTabs[2][3].text.text_ in ("Timer pr. dag",), "Timer pr. dag under Rangliste")
check("I perioden" in ui.info.text_, "info: %s" % ui.info.text_)
check(ui.graph.empty.text_ == "", "grafen har data")
cols = [c for c in ui.graph.cols.values() if c.shown]
check(len(cols) == 7, "7 dage som standard: %d" % len(cols))
G.TT = lua.table()
cols[-1].scripts.OnEnter(cols[-1])
tt = list(G.TT.values())
check(any("i dag" in s for s in tt) and any(s.startswith("Nick |") for s in tt) and any(s.startswith("I alt") for s in tt),
      "dagens tooltip: %s" % tt)
nick = [b for b in ui.friendBtns.values() if b.who == "Nick"][0]
G.TT = lua.table()
nick.scripts.OnEnter(nick)
tt = list(G.TT.values())
check(any(s.startswith("I dag | 2t 30m") for s in tt) and any(s.startswith("Mest på én dag") for s in tt), "Nicks knap: %s" % tt)
nick.scripts.OnClick(nick)
check(ui.hidden["Nick"], "klik skjuler Nick")
G.TT = lua.table()
cols[-1].scripts.OnEnter(cols[-1])
check(not any(s.startswith("Nick |") for s in G.TT.values()), "skjult ven er ikke i tooltippen")
nick.scripts.OnClick(nick)
# Perioder og "Samlet"
ui.rangeBtns[4].scripts.OnClick(ui.rangeBtns[4])
cols = [c for c in ui.graph.cols.values() if c.shown]
check(len(cols) == 30, "90 dage, men kun fra første måling: %d" % len(cols))
ui.modeBtns[2].scripts.OnClick(ui.modeBtns[2])
series = {s.name: s for s in ui.series.values()}
pts = series["Nick"].pts
check(pts[30] == 12600 and pts[29] == 3600, "samlet: Nicks tal lægges sammen: %s %s" % (pts[29], pts[30]))
check(not series["Frode"].any, "Frode uden målinger har ingen linje")
ui.modeBtns[1].scripts.OnClick(ui.modeBtns[1])
ui.rangeBtns[1].scripts.OnClick(ui.rangeBtns[1])

# Aksen
check(PD.NiceMax(0) == 3600 and PD.NiceMax(3 * 3600) == 5 * 3600 and PD.NiceMax(30 * 3600) == 50 * 3600, "pæne trin på aksen")
check(PD.HoursShort(1800) == "30m" and PD.HoursShort(7200) == "2t" and PD.HoursShort(5400) == "1.5t", "korte timetal")

# ---------- /wc4ever timer ----------
G.PRINTS = lua.table()
G.SlashCmdList["WASTEDCOAST"]("timer")
pr = list(G.PRINTS.values())
check(any("Spilletid de sidste 7 dage" in p for p in pr) and any("Nick" in p for p in pr), "/wc4ever timer: %s" % pr)

# ---------- Demo ----------
G.SlashCmdList["WASTEDCOAST"]("demo")
G.RunTimers()
check(db.playedDayDemo and db.playedDayDemo.Frode and lua.eval("next")(db.playedDayDemo.Frode) is not None, "demo-dage til Frode")
check(not db.playedDayDemo.Nick, "Nick har rigtige tal og får ingen demo")
G.SENT = lua.table()
ns.SendMyExtras(False)
pump()
check(not any(m.startswith("XP;Frode") for m in sent("XP;")), "demo sendes aldrig")
lua.execute("local ns = ...; ns.ShowTab(21)", ns)
check(any(s.any for s in PD.ui.series.values() if s.name == "Frode"), "demo vises i grafen")
G.SlashCmdList["WASTEDCOAST"]("demo slut")
check(not db.playedDayDemo or not db.playedDayDemo.Frode, "demo slut fjerner demo-dagene")

# ---------- Nulstilling ----------
G.SlashCmdList["WASTEDCOAST"]("reset ja")
check(not db.playedDay or not db.playedDay.Nick, "reset sletter dagene")

print("OK,", PASSES, "checks passed", "(forever)" if FOREVER else "")
