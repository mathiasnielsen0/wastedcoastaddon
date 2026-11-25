# Test af videresendelse (Videresend.lua): QV-resuméet ved synk, CV for offline venners karakterer,
# D og L videresendt (nyere end spørgerens, ældste først, med loft), ingen gentagelse af det, der lige er set,
# aldrig online venner, spørgeren selv, demo eller testdata, og ødelagte beskeder.
# Kør: pip install lupa && python3 tests/test_videresend.py WastedCoast [forever]
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
lua.execute('function GetAddOnMetadata(name, field) if field == "Version" then return "0.31.3" end end')
ns = lua.table()
load_addon(lua, ADDON, ns)

TESTS = r'''
local ns = ...
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end PASSES = (PASSES or 0) + 1 end
local function pump() for _, tk in ipairs(TICKERS) do if tk.d == 0.3 then for i = 1, 600 do tk.f() end end end end
local function sentWith(prefix) pump() local out, seen = {}, {} for _, s in ipairs(SENT) do if s.msg:sub(1, #prefix) == prefix and not seen[s.msg] then seen[s.msg] = true out[#out+1] = s.msg end end return out end
local function split(s) local t = {} for p in (s .. ";"):gmatch("(.-);") do t[#t+1] = p end return t end
local function msg(s, char) Fire("CHAT_MSG_ADDON", "WCOAST", s, "GUILD", char or "Someone") end
local function hb(friend, char, level)
    msg(table.concat({ "H", friend, char, "MAGE", level, 100, "Westfall", 10, "", "1" }, ";"), char)
end
local function respond() pump() RunTimers() end

Fire("ADDON_LOADED", "WastedCoast")
local db = WastedCoastDB
db.me = "Mathias"
Fire("PLAYER_LOGIN")
RunTimers()
CLOCK = CLOCK + 1000
local R = ns.Relay
check(R ~= nil and ns.SendSyncDigest ~= nil and ns.HandleRelayMessage ~= nil, "Videresend.lua er indlæst")

-- Base 36
check(R.B36(0) == "0" and R.B36(35) == "z" and R.B36(36) == "10", "base 36")
check(tonumber(R.B36(1795000000), 36) == 1795000000, "base 36 frem og tilbage")

-- -----------------------------------------------------------------------------
-- Mathias kender Nick (offline nu) og Jeppe: karakterer, dødsfald og loot
-- -----------------------------------------------------------------------------
local T0 = NOW
hb("Nick", "Nickchar", 32)
hb("Jeppe", "Jepchar", 26)
for i = 1, 3 do
    msg(table.concat({ "D", "nd" .. i, "Nickchar", "MAGE", "Hogger", "", 30, "Westfall", T0 - 1000 + i * 100, "Nick", 30 }, ";"))
end
msg(table.concat({ "L", "nl1", "Nick", "Nickchar", "MAGE", "item:1234", 3, "need", "dungeon", "Deadmines", T0 - 500, "Blue Sword" }, ";"))
check(#db.events >= 3, "Nicks dødsfald er gemt")
-- Demo og test sendes aldrig videre
table.insert(db.events, { id = "demo-x", name = "Nickchar", friend = "Nick", time = T0, demo = true, killer = "X", level = 1, zone = "Z" })
table.insert(db.events, { id = "test-x", name = "Nickchar", friend = "Nick", time = T0, killer = "X", level = 1, zone = "Z" })
-- Nick og Jeppe logger ud
NOW = NOW + 3600
CLOCK = CLOCK + 3600

-- -----------------------------------------------------------------------------
-- Synk-forespørgslen sender et resumé
-- -----------------------------------------------------------------------------
pump()   -- tøm køen fra login
SENT = {}
ns.core.RequestSync()
local qv = sentWith("QV;")
check(#qv >= 1, "RequestSync sender QV")
local t = split(qv[1])
check(t[2] == "Mathias" and #qv[1] <= 255, "QV: afsender og længde")
check(not qv[1]:find("Mathias=", 1, true), "mig selv er ikke med i resuméet")
local nd, nl, nc = qv[1]:match("Nick=([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)")
check(tonumber(nd, 36) == T0 - 1000 + 300 and tonumber(nl, 36) == T0 - 500, "Nicks nyeste dødsfald og loot (demo/test tæller ikke)")
check(tonumber(nc, 36) and tonumber(nc, 36) >= T0, "Nicks sidst set")
check(qv[1]:find("Rasmus=0.0.0", 1, true), "ukendte venner er 0")

-- -----------------------------------------------------------------------------
-- Søren spørger med gamle data om Nick: Mathias svarer med det nyere
-- -----------------------------------------------------------------------------
SENT = {}
msg("QV;Søren;Nick=" .. R.B36(T0 - 1000 + 100) .. ".0." .. R.B36(T0 - 6 * 86400) .. ",Mathias=0.0.0,Jeppe=0.0.0", "Sorenchar")
respond()
local cv = sentWith("CV;")
local nickCv
for _, m in ipairs(cv) do if m:find(";Nick;Nickchar;", 1, true) then nickCv = split(m) end end
check(nickCv and nickCv[2] == "Mathias" and nickCv[6] == "32", "CV: Nicks karakter med level 32")
check(nickCv and tonumber(nickCv[9]) >= T0, "CV: sidst set")
local d = sentWith("D;")
local ids = {}
for _, m in ipairs(d) do ids[split(m)[2]] = true end
check(not ids.nd1 and ids.nd2 and ids.nd3, "kun dødsfald nyere end Sørens")
check(not ids["demo-x"] and not ids["test-x"], "aldrig demo eller test")
check(#sentWith("L;") == 1, "Nicks loot sendes (Søren havde ingen)")
check(split(d[1])[2] == "nd2", "ældste først")
local mine = 0
for _, m in ipairs(cv) do if split(m)[3] == "Mathias" then mine = mine + 1 end end
check(mine == 0, "mine egne karakterer går ikke som CV")

-- Lige efter: samme spørgsmål giver ikke det hele igen
SENT = {}
msg("QV;Rasmus;Nick=0.0.0", "Rasmuschar")
respond()
do
    local dd = sentWith("D;")
    check(#dd == 1 and split(dd[1])[2] == "nd1" and #sentWith("CV;") == 0 and #sentWith("L;") == 0,
        "det, der lige er sendt, sendes ikke igen (kun nd1, som Søren havde)")
end
-- To minutter senere gør det
CLOCK = CLOCK + 200
SENT = {}
msg("QV;Rasmus;Nick=0.0.0", "Rasmuschar")
respond()
check(#sentWith("D;") == 3, "efter pausen sendes det igen")

-- Har spørgeren det nyeste, sendes intet
CLOCK = CLOCK + 200
SENT = {}
msg("QV;Rasmus;Nick=" .. R.B36(NOW) .. "." .. R.B36(NOW) .. "." .. R.B36(NOW), "Rasmuschar")
respond()
check(#sentWith("D;") == 0 and #sentWith("L;") == 0 and #sentWith("CV;") == 0, "spørgeren har det nyeste: intet")

-- Spørgeren selv får ikke sine egne data videresendt
CLOCK = CLOCK + 200
SENT = {}
msg("QV;Nick;Nick=0.0.0", "Nickchar")
respond()
check(#sentWith("D;") == 0 and #sentWith("CV;") == 0, "intet om spørgeren selv")

-- Online venner svarer selv
CLOCK = CLOCK + 200
hb("Jeppe", "Jepchar", 27)
SENT = {}
msg("QV;Rasmus;Jeppe=0.0.0", "Rasmuschar")
respond()
check(#sentWith("CV;") == 0, "Jeppe er online: ingen CV for ham")

-- Set på kanalen fra en anden: sendes ikke igen
NOW = NOW + 3600
CLOCK = CLOCK + 3600
msg(table.concat({ "D", "nd2", "Nickchar", "MAGE", "Hogger", "", 30, "Westfall", T0 - 1000 + 200, "Nick", 30 }, ";"))
SENT = {}
msg("QV;Rasmus;Nick=0.0.0", "Rasmuschar")
respond()
local again = {}
for _, m in ipairs(sentWith("D;")) do again[split(m)[2]] = true end
check(not again.nd2 and again.nd1 and again.nd3, "et dødsfald, en anden lige har sendt, springes over")

-- Loft pr. ven
for i = 1, 40 do
    table.insert(db.events, { id = "many" .. i, name = "Nickchar", friend = "Nick", class = "MAGE", killer = "Hogger",
        ability = "", level = 30, zone = "Westfall", time = T0 + i * 100 })
end
CLOCK = CLOCK + 200
SENT = {}
msg("QV;Rasmus;Nick=" .. R.B36(T0) .. ".0.0", "Rasmuschar")
respond()
local many = sentWith("D;")
check(#many + #sentWith("L;") == R.PER, "højst " .. R.PER .. " dødsfald + loot pr. ven pr. runde: " .. #many)
check(split(many[1])[2] == "many1", "ældste først, resten kommer næste gang")

-- -----------------------------------------------------------------------------
-- Modtag CV: kun nyere end det, vi har
-- -----------------------------------------------------------------------------
local nick = db.friends.Nick.chars.Nickchar
local had = nick.seen
msg(table.concat({ "CV", "Frode", "Nick", "Nickchar", "MAGE", 20, 5, "Elwynn", had - 100, 0, "" }, ";"), "Frodechar")
check(nick.level == 32, "ældre CV overskriver ikke")
msg(table.concat({ "CV", "Frode", "Nick", "Nickchar", "MAGE", 33, 5000, "Duskwood", had + 100, 45, "" }, ";"), "Frodechar")
check(nick.level == 33 and nick.zone == "Duskwood" and nick.xp == 45 and nick.seen == had + 100, "nyere CV opdaterer")
check(not ns.CharOnline("Nickchar", nick) or (NOW - nick.seen) < 150, "CV gør ikke vennen online")
msg(table.concat({ "CV", "Frode", "Nick", "Nyalt", "PRIEST", 5, 0, "Teldrassil", NOW + 99999, 0, "" }, ";"), "Frodechar")
check(db.friends.Nick.chars.Nyalt and db.friends.Nick.chars.Nyalt.seen <= NOW, "ny karakter, tid i fremtiden rettes")
check(db.chars.Nyalt == "Nick", "karakteren hører til Nick")

-- Ødelagte og ondsindede beskeder
local before = 0 for _ in pairs(db.friends.Nick.chars) do before = before + 1 end
msg("CV;Frode;Nick;Badchar;MAGE;abc;0;Z;" .. (NOW + 10) .. ";0;", "x")
msg("CV;Frode;Ukendt;Char;MAGE;10;0;Z;" .. NOW .. ";0;", "x")
msg("CV;Ukendt;Nick;Char2;MAGE;10;0;Z;" .. NOW .. ";0;", "x")
msg("CV;Frode;Mathias;Minchar;MAGE;10;0;Z;" .. (NOW + 10) .. ";0;", "x")
msg("CV;Frode;Nick;;MAGE;10;0;Z;" .. NOW .. ";0;", "x")
msg("CV;Frode;Nick;Char3;MAGE;10;0;Z;abc;0;", "x")
msg("CV", "x")
local after = 0 for _ in pairs(db.friends.Nick.chars) do after = after + 1 end
check(after == before, "ødelagte CV gemmer intet")
check(not (db.friends.Mathias and db.friends.Mathias.chars and db.friends.Mathias.chars.Minchar), "CV om mig selv ignoreres")
R.want = {}
msg("QV", "x")
msg("QV;Rasmus", "x")
msg("QV;Rasmus;Nick=zzzzzzzzzzzz.0.0", "x")
msg("QV;Rasmus;Nick=-1.0.0,Ukendt=0.0.0", "x")
msg("QV;Mathias;Nick=0.0.0", "x")
msg("QV;Ukendt;Nick=0.0.0", "x")
check(next(R.want) == nil, "ødelagte QV gemmer intet")

-- Lang roster: resuméet deles op ved 255 tegn
SENT = {}
local roster = ns.core.ROSTER
local n0 = #roster
for i = 1, 20 do
    local nm = "Ekstramedlem" .. i
    roster[#roster + 1] = nm
    ns.core.ROSTER_SET[nm] = true
end
ns.SendSyncDigest()
local parts = sentWith("QV;")
check(#parts >= 2, "resuméet deles op: " .. #parts)
for _, p in ipairs(parts) do check(#p <= 255, "hver del højst 255 tegn") end
for i = #roster, n0 + 1, -1 do ns.core.ROSTER_SET[roster[i]] = nil roster[i] = nil end

-- -----------------------------------------------------------------------------
-- v0.31.4: køen. Dubletter, "soon" foran synk-historikken, og fuld kø smider bulk væk
-- -----------------------------------------------------------------------------
pump()
SENT = {}
local Send = ns.core.Send
for i = 1, 5 do Send("S;Mathias;Inst" .. i .. ";0;0;0") end
for i = 1, 5 do Send("S;Mathias;Inst" .. i .. ";0;0;0") end   -- samme svar igen: lægges ikke i kø
Send("CV;Mathias;soon", "soon")
Send("H;prio", true)
pump()
local order = {}
for _, x in ipairs(SENT) do if order[#order] ~= x.msg then order[#order + 1] = x.msg end end
local cnt = 0
for _, m in ipairs(order) do if m:find("^S;Mathias;Inst") then cnt = cnt + 1 end end
check(cnt == 5, "samme besked står kun i køen én gang: " .. cnt)
check(order[1] == "H;prio" and order[2] == "CV;Mathias;soon", "prioritet forrest, så videresendelse, så historik")
-- Efter afsendelse kan den samme besked sendes igen
SENT = {}
Send("S;Mathias;Inst1;0;0;0")
check(#sentWith("S;Mathias;Inst1") == 1, "sendt besked kan sendes igen")
-- Fuld kø: bulk smides væk, ikke videresendelsen
SENT = {}
for i = 1, 520 do Send("S;Mathias;Fyld" .. i .. ";0;0;0") end
Send("CV;Mathias;vigtig", "soon")
for i = 521, 540 do Send("S;Mathias;Fyld" .. i .. ";0;0;0") end
check(#sentWith("CV;Mathias;vigtig") == 1, "videresendelsen overlever en fuld kø")

-- -----------------------------------------------------------------------------
-- v0.31.3: versionen i livstegnet og /wc4ever status
-- -----------------------------------------------------------------------------
check(ns.VERSION == "0.31.3", "egen version læses fra .toc")
SENT = {}
ns.core.SendHeartbeat()
local h = sentWith("H;")
check(#h >= 1 and split(h[#h])[11] == "0.31.3", "H: version i felt 11")
check(R.VersionAtLeast("0.31.10", "0.31.3") and R.VersionAtLeast("0.31.3", "0.31.3")
    and not R.VersionAtLeast("0.31.2", "0.31.3") and not R.VersionAtLeast(nil, "0.31.3"), "versioner sammenlignes tal for tal")
msg(table.concat({ "H", "Nick", "Nickchar", "MAGE", 33, 100, "Westfall", 10, "", "1", "0.31.2" }, ";"), "Nickchar")
check(db.friends.Nick.ver == "0.31.2", "vennens version gemmes")
check(ns.VersionTag("Nick"):find("0.31.2", 1, true) and ns.VersionTag("Nick"):find("ff6060", 1, true), "ældre version vises med rødt")
msg(table.concat({ "H", "Nick", "Nickchar", "MAGE", 33, 100, "Westfall", 10, "", "1", "x;y" }, ";"), "Nickchar")
msg(table.concat({ "H", "Nick", "Nickchar", "MAGE", 33, 100, "Westfall", 10, "", "1", "hej" }, ";"), "Nickchar")
check(db.friends.Nick.ver == "0.31.2", "ugyldig version ignoreres")
msg(table.concat({ "H", "Nick", "Nickchar", "MAGE", 33, 100, "Westfall", 10, "", "1" }, ";"), "Nickchar")
check(db.friends.Nick.ver == "0.31.2", "ældre livstegn uden version sletter den ikke")
check(ns.VersionTag("Rasmus"):find("ukendt", 1, true), "ukendt version")
PRINTS = {}
ns.PrintRoutes()
local all = table.concat(PRINTS, "\n")
check(all:find("v0.31.2", 1, true) and all:find("Videresendelse siden login", 1, true), "status viser versioner og videresendelse")

return PASSES
'''

passes = lua.execute(TESTS, ns)
print("OK,", passes, "checks passed", "(forever)" if FOREVER else "")
