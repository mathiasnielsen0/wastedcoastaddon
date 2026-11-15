local _, ns = ...
local L = ns.L

-- =============================================================================
-- Ugens pokaler (v0.25)
--   Hver søndag kl. 20 (dansk tid) kåres ugens vindere i en række kategorier: flest
--   dødsfald, den pinligste død, loot-goblin, need-goblin, længst spilletid, flest levels,
--   dueller, rare mobs, stomier, prutter og "Udødelig". Vinderne har pokalen på deres kort og i
--   tooltippen i en uge, der kommer en toast og en chatbesked til alle, en linje i
--   nyhederne, og alle uger gemmes i pokalskabet (Sjov > Ugens pokaler).
--
--   * Ugen går fra søndag kl. 20 til næste søndag kl. 20 i dansk tid (med sommertid),
--     regnet ud fra spillets UTC-ur, så alle får den samme uge, uanset hvor de sidder.
--   * Det hele regnes ud fra data, der allerede synker mellem jer (dødsfald, loot,
--     Need-politiet, dueller, rare mobs, stomi og prutter fra hån-knappen). Samme data giver de samme vindere hos
--     alle: lige stilling afgøres af, hvem der nåede tallet først, og derefter af navnet.
--   * Spilletid og levels i ugen måler hver ven selv og sender med XW-beskeden.
--   * Data, der kommer for sent (en ven, der logger ind om mandagen), tæller med en uge
--     endnu. Derefter er ugen låst i pokalskabet.
--
-- Besked: XW;ven;uge;spilletid i ugen (sek);levels i ugen
-- db.weekly = { hist = { [uge] = { w = { [pokal] = { f, v, ... } }, fz = låst } },
--               rep = { [uge] = { [ven] = { p, l } } }, mine = { [uge] = { c = { karakter -> start }, p, l } },
--               shown = sidste uge, der er vist ved uddelingen }
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name

local Weekly = {}
ns.Weekly = Weekly

local WEEK = 7 * 86400
local ANCHOR = 3 * 86400 + 20 * 3600   -- søndag 4/1-1970 kl. 20 (lokal dansk tid)
local BACKFILL = 26                     -- så mange uger tilbage regnes pokalskabet ud fra
local SETTLE = WEEK                     -- så længe efter uddelingen kan en uge stadig ændre sig
local SETTLE_SESSION = 300              -- og først efter 5 minutter online (så synken er nået frem)
local ANNOUNCE_DELAY = 180              -- uddelingen venter 3 minutter, så vennernes sidste tal er nået frem
local RESEND = 900
local MIN_PLAYED = 3600                 -- Ugens nolifer: mindst en time
local MIN_IMMORTAL = 2 * 3600           -- Udødelig: mindst to timer uden at dø
local MIN_GAP = 3                       -- Pinligste død: mobbet var mindst 3 levels under dig
local KEEP_REP = 30                     -- uger med spilletid/levels, der gemmes

local loadedAt                          -- GetTime(), da du loggede ind
local lastSend = 0
local tickWeek                          -- ugen ved sidste tick (så ugeskiftet opdages)

local function DB()
    local db = WastedCoastDB
    db.weekly = db.weekly or {}
    local w = db.weekly
    w.hist = w.hist or {}
    w.rep = w.rep or {}
    w.mine = w.mine or {}
    return db, w
end

local function IC(name) return "Interface\\Icons\\" .. name end

-- Vennens navn i klassefarve (klassen fra karakteren med højest level)
local function Who(friend)
    local best, lvl
    local info = WastedCoastDB.friends and WastedCoastDB.friends[friend]
    for _, c in pairs((info and info.chars) or {}) do
        if c.class and (not lvl or (c.level or 0) > lvl) then best, lvl = c.class, c.level or 0 end
    end
    return C.ColorName(friend, best)
end

-- =============================================================================
-- Tid: dansk tid ud fra UTC (EU-sommertid: sidste søndag i marts til sidste søndag i
-- oktober, kl. 01 UTC). Kalenderregningen er Howard Hinnants, så den virker uden date().
-- =============================================================================
local floor = math.floor

local function DaysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function CivilFromDays(z)
    z = z + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local d = doy - floor((153 * mp + 2) / 5) + 1
    local m = (mp < 10) and (mp + 3) or (mp - 9)
    if m <= 2 then y = y + 1 end
    return y, m, d
end
Weekly.DaysFromCivil, Weekly.CivilFromDays = DaysFromCivil, CivilFromDays

-- Dagnummeret for den sidste søndag i en måned
local function LastSunday(y, m)
    local last = DaysFromCivil((m == 12) and (y + 1) or y, (m == 12) and 1 or (m + 1), 1) - 1
    return last - (last + 4) % 7   -- (dag + 4) % 7 = 0 er en søndag (1/1-1970 var en torsdag)
end

-- Sekunder, dansk tid ligger foran UTC
function Weekly.Offset(utc)
    local y = CivilFromDays(floor(utc / 86400))
    local s = LastSunday(y, 3) * 86400 + 3600
    local e = LastSunday(y, 10) * 86400 + 3600
    return (utc >= s and utc < e) and 7200 or 3600
end

-- Ugens nummer (et løbenummer): uge n går fra søndag kl. 20 til næste søndag kl. 20
function Weekly.Index(utc)
    utc = utc or time()
    return floor((utc + Weekly.Offset(utc) - ANCHOR) / WEEK)
end

-- Hvornår uge n begynder og slutter (UTC). Søndag kl. 20 ligger aldrig i timen, hvor uret stilles.
function Weekly.Start(n)
    local loc = ANCHOR + n * WEEK
    return loc - Weekly.Offset(loc - 3600)
end
function Weekly.End(n) return Weekly.Start(n + 1) end

-- Ugenummeret i kalenderen (ISO, mandag til søndag) for ugen, der slutter med uddelingen
function Weekly.Number(n)
    local d = floor((ANCHOR + (n + 1) * WEEK) / 86400) - 1   -- lørdagen før uddelingen
    local thu = d - (d + 3) % 7 + 3                            -- torsdagen i samme ISO-uge
    local y = CivilFromDays(thu)
    return floor((thu - DaysFromCivil(y, 1, 1)) / 7) + 1, y
end

-- =============================================================================
-- Pokalerne
-- =============================================================================
local STOMI_ICON = "Interface\\AddOns\\WastedCoast\\media\\stomi"

Weekly.CUPS = ns.LT({
    { id = "dead",     name = "Kirkegårdens stamgæst", desc = "Flest dødsfald i ugen.",
      icon = IC("INV_Misc_Bone_HumanSkull_01"), unit = "%d dødsfald" },
    { id = "shame",    name = "Ugens pinligste død", desc = "Døde til det mob, der lå længst under ens eget level.",
      icon = IC("Spell_Shadow_AnimateDead") },
    { id = "loot",     name = "Loot-goblin", desc = "Fik flest rare (eller bedre) items.",
      icon = IC("INV_Misc_Bag_10"), unit = "%d items" },
    { id = "need",     name = "Need-goblin", desc = "Flest sager hos Need-politiet.",
      icon = IC("INV_Misc_Coin_02"), unit = "%d sager" },
    { id = "played",   name = "Ugens nolifer", desc = "Længst spilletid i ugen (mindst en time).",
      icon = IC("INV_Misc_PocketWatch_01"), time = true },
    { id = "ding",     name = "Ding-maskinen", desc = "Flest levels i ugen.",
      icon = IC("Spell_Holy_SurgeOfLight"), unit = "%d levels" },
    { id = "duel",     name = "Duel-kongen", desc = "Vandt flest dueller.",
      icon = IC("INV_Sword_27"), unit = "%d sejre" },
    { id = "rare",     name = "Rare-jægeren", desc = "Dræbte flest rare mobs.",
      icon = IC("Ability_Hunter_SniperShot"), unit = "%d rares" },
    { id = "stomiG",   name = "Stomi-mesteren", desc = "Gav flest stomier.",
      icon = STOMI_ICON, unit = "%d stomier" },
    { id = "stomiR",   name = "Stomi-patienten", desc = "Fik flest stomier.",
      icon = STOMI_ICON, unit = "%d stomier" },
    { id = "haan",     name = "Prut-kongen", desc = "Pruttede mest af venner, der lige var døde.",
      icon = IC("Spell_Nature_Cyclone"), unit = "%d prutter" },
    { id = "immortal", name = "Udødelig", desc = "Døde ikke én eneste gang og spillede mest (mindst to timer).",
      icon = IC("Spell_Holy_DivineIntervention"), time = true },
})
Weekly.BY_ID = {}
for i, c in ipairs(Weekly.CUPS) do c.order = i Weekly.BY_ID[c.id] = c end

-- "7 dødsfald", "5t 12m" eller "level 12 Murloc (selv 31)"
function Weekly.ValueText(cupId, r)
    local cup = Weekly.BY_ID[cupId]
    if not cup or not r then return "" end
    if cupId == "shame" then
        return string.format(L("level %d %s (selv %d)"), r.kl or 0, L(r.k or "?"), r.lv or 0)
    end
    if cup.time then return ns.FormatPlayed and ns.FormatPlayed(r.v) or tostring(r.v) end
    return string.format(L(cup.unit or "%d"), r.v or 0)
end

-- =============================================================================
-- Beregning
-- =============================================================================
local function IsDemo(e)
    return e.demo or (type(e.id) == "string" and e.id:find("^demo%-") ~= nil)
end

local function LootOwner(ev)
    if ev.friend and ROSTER_SET[ev.friend] then return ev.friend end
    return C.FriendOfChar(ev.char)
end

-- Rangliste ud fra { ven -> { v, t } }: højest først, lige stilling: den, der nåede tallet
-- først, og så navnet. Samme data giver samme rækkefølge hos alle.
local function Rank(map, min)
    local list = {}
    for f, r in pairs(map or {}) do
        if ROSTER_SET[f] and r.v >= (min or 1) then list[#list + 1] = { f = f, v = r.v, t = r.t or 0, k = r.k, kl = r.kl, lv = r.lv } end
    end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        if a.t ~= b.t then return a.t < b.t end
        return a.f < b.f
    end)
    return list
end

-- Resultatet for uge n: { w = { pokal -> { f, v, ... } }, rank = { pokal -> rangliste } }
function Weekly.Compute(n, withDemo)
    local db, wk = DB()
    local s, e = Weekly.Start(n), Weekly.End(n)
    local function within(t) return type(t) == "number" and t >= s and t < e end
    local function ok(x) return withDemo or not IsDemo(x) end
    local tally = {}
    for _, cup in ipairs(Weekly.CUPS) do tally[cup.id] = {} end
    local function bump(id, f, t, amount)
        if not f or not ROSTER_SET[f] then return end
        local r = tally[id][f]
        if not r then r = { v = 0, t = 0 } tally[id][f] = r end
        r.v = r.v + (amount or 1)
        if t > r.t then r.t = t end   -- hvornår tallet blev nået
    end

    -- Dødsfald og den pinligste død
    local died = {}
    for _, ev in ipairs(db.events or {}) do
        if within(ev.time) and ok(ev) then
            local f = C.EventFriend(ev)
            if f then
                bump("dead", f, ev.time)
                died[f] = true
                local kl, lv = tonumber(ev.klvl), tonumber(ev.level)
                if ev.pvp ~= true and kl and lv and kl > 0 and lv - kl >= MIN_GAP then
                    local gap, cur = lv - kl, tally.shame[f]
                    if not cur or gap > cur.v or (gap == cur.v and ev.time < cur.t) then
                        tally.shame[f] = { v = gap, t = ev.time, k = ev.killer, kl = kl, lv = lv }
                    end
                end
            end
        end
    end

    -- Loot: altid rare eller bedre, så alle tæller det samme (minimumskvaliteten er en lokal indstilling)
    for _, ev in ipairs(db.loot or {}) do
        if within(ev.time) and ok(ev) and (tonumber(ev.quality) or 0) >= 3 then bump("loot", LootOwner(ev), ev.time) end
    end

    for _, x in ipairs(db.needShame or {}) do
        if within(x.time) and ok(x) then bump("need", x.friend, x.time) end
    end

    -- Dueller: hver ven gemmer sine egne, så en sejr tælles én gang
    for f, list in pairs(db.duels or {}) do
        local seen = {}
        for _, d in ipairs(list) do
            local key = d.id or tostring(d.t)
            if d.won and within(d.t) and ok(d) and not seen[key] then
                seen[key] = true
                bump("duel", f, d.t)
            end
        end
    end

    for _, r in ipairs(db.rareLog or {}) do
        if within(r.t) and ok(r) then bump("rare", r.friend, r.t) end
    end

    for _, x in ipairs((db.stomi and db.stomi.log) or {}) do
        if x.r == "y" and within(x.t) and ok(x) and ROSTER_SET[x.from] and ROSTER_SET[x.to] then
            bump("stomiG", x.from, x.t)
            bump("stomiR", x.to, x.t)
        end
    end

    -- Prutter fra hån-knappen
    local farts = {}
    for _, x in ipairs((db.haan and db.haan.log) or {}) do
        if within(x.t) and ok(x) and ROSTER_SET[x.to] and not farts[x.id or ""] then
            if x.id then farts[x.id] = true end
            bump("haan", x.from, x.t)
        end
    end

    -- Spilletid og levels: hver ven har selv målt sin uge
    for f, r in pairs(wk.rep[n] or {}) do
        if ROSTER_SET[f] then
            if (r.p or 0) > 0 then
                tally.played[f] = { v = r.p, t = 0 }
                if not died[f] then tally.immortal[f] = { v = r.p, t = 0 } end
            end
            if (r.l or 0) > 0 then tally.ding[f] = { v = r.l, t = 0 } end
        end
    end

    local res = { w = {}, rank = {} }
    for _, cup in ipairs(Weekly.CUPS) do
        local min = (cup.id == "played" and MIN_PLAYED) or (cup.id == "immortal" and MIN_IMMORTAL) or 1
        local list = Rank(tally[cup.id], min)
        res.rank[cup.id] = list
        local top = list[1]
        if top then res.w[cup.id] = { f = top.f, v = top.v, k = top.k, kl = top.kl, lv = top.lv } end
    end
    return res
end

-- Pokalskabet: regner de seneste uger ud. En uge låses, når den er mere end en uge gammel,
-- og du har været online i 5 minutter (så vennernes data er nået frem).
function Weekly.Update(now)
    now = now or time()
    local _, wk = DB()
    local cur = Weekly.Index(now)
    local settled = loadedAt and GetTime and (GetTime() - loadedAt >= SETTLE_SESSION)
    for n = cur - BACKFILL, cur - 1 do
        local h = wk.hist[n]
        if not h or not h.fz then
            local res = Weekly.Compute(n, false)
            wk.hist[n] = { w = res.w, fz = (settled and now >= Weekly.End(n) + SETTLE) or nil }
        end
    end
    for n in pairs(wk.hist) do
        if n >= cur then wk.hist[n] = nil end   -- uret er gået baglæns: en uge, der ikke er slut
    end
    for _, t in ipairs({ wk.rep, wk.mine }) do
        for n in pairs(t) do if n < cur - KEEP_REP then t[n] = nil end end
    end
    Weekly.updated = cur
end

local function Ensure(now)
    local cur = Weekly.Index(now or time())
    if Weekly.updated ~= cur then Weekly.Update(now) end
    return cur
end

-- Vinderne i uge n (fra pokalskabet): { pokal -> { f, v, ... } }
function Weekly.Winners(n)
    local _, wk = DB()
    local h = wk.hist[n]
    return (h and h.w) or {}
end

-- De pokaler, vennen vandt i den seneste afsluttede uge (dem, der står på kortet), i fast rækkefølge
function Weekly.Won(friend, now)
    local cur = Ensure(now)
    local out = {}
    for _, cup in ipairs(Weekly.CUPS) do
        local r = Weekly.Winners(cur - 1)[cup.id]
        if r and r.f == friend then out[#out + 1] = { cup = cup, r = r } end
    end
    return out, cur - 1
end

-- Alle pokaler pr. ven i pokalskabet: { ven -> { n = i alt, by = { pokal -> antal } } }
function Weekly.Cabinet(now)
    local cur = Ensure(now)
    local _, wk = DB()
    local out = {}
    for n, h in pairs(wk.hist) do
        if n < cur then
            for id, r in pairs(h.w or {}) do
                if ROSTER_SET[r.f] and Weekly.BY_ID[id] then
                    local e = out[r.f] or { n = 0, by = {} }
                    out[r.f] = e
                    e.n = e.n + 1
                    e.by[id] = (e.by[id] or 0) + 1
                end
            end
        end
    end
    return out
end

-- Hvem har flest pokaler i uge n: { { f, n }, ... }
local function Tally(winners)
    local count = {}
    for _, cup in ipairs(Weekly.CUPS) do
        local r = winners[cup.id]
        if r and ROSTER_SET[r.f] then count[r.f] = (count[r.f] or 0) + 1 end
    end
    local list = {}
    for f, k in pairs(count) do list[#list + 1] = { f = f, n = k } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.f < b.f
    end)
    return list
end
Weekly.Tally = Tally

-- =============================================================================
-- Din egen spilletid og dine levels i ugen
-- =============================================================================
local function Mine(n)
    local _, wk = DB()
    local m = wk.mine[n]
    if not m then m = { c = {}, p = 0, l = 0 } wk.mine[n] = m end
    m.c = m.c or {}
    return m
end

local function StoreReport(n, friend, p, l)
    local _, wk = DB()
    wk.rep[n] = wk.rep[n] or {}
    local r = wk.rep[n][friend] or {}
    wk.rep[n][friend] = r
    -- Tallene vokser kun i løbet af en uge: den største værdi vinder
    r.p = math.max(r.p or 0, p or 0)
    r.l = math.max(r.l or 0, l or 0)
end

-- Måler din spilletid i den nuværende uge: for hver karakter tiden siden ugens første måling
function Weekly.Track(now)
    local db = DB()
    if not db.me or not ROSTER_SET[db.me] then return end
    now = now or time()
    local n = Weekly.Index(now)
    local m = Mine(n)
    local total = 0
    local info = db.friends[db.me]
    for char, c in pairs((info and info.chars) or {}) do
        if not c.demo then
            local secs = ns.PlayedNow and ns.PlayedNow(db.me, char, c)
            if secs then
                if not m.c[char] or secs < m.c[char] then m.c[char] = secs end
                total = total + (secs - m.c[char])
            end
        end
    end
    m.p = math.min(WEEK, floor(total))
    StoreReport(n, db.me, m.p, m.l)
    return m
end

function Weekly.OnLevelUp(now)
    local db = DB()
    if not db.me then return end
    local n = Weekly.Index(now or time())
    local m = Mine(n)
    m.l = (m.l or 0) + 1
    StoreReport(n, db.me, m.p, m.l)
    Weekly.Send()
end

-- Sender dine tal for denne og sidste uge
function Weekly.Send()
    local db, wk = DB()
    if not db.me or not ROSTER_SET[db.me] then return end
    Weekly.Track()
    lastSend = GetTime and GetTime() or 0
    local cur = Weekly.Index(time())
    for n = cur - 1, cur do
        local m = wk.mine[n]
        if m and ((m.p or 0) > 0 or (m.l or 0) > 0) then
            C.Send(string.format("XW;%s;%d;%d;%d", db.me, n, m.p or 0, m.l or 0))
        end
    end
end
ns.SendWeekly = Weekly.Send

function ns.HandleWeeklyMessage(t)
    local db = DB()
    local friend, n, p, l = t[2], tonumber(t[3]), tonumber(t[4]), tonumber(t[5])
    if not ROSTER_SET[friend] or friend == db.me or not n or not p or not l then return end
    local cur = Weekly.Index(time())
    if n > cur or n < cur - BACKFILL or p < 0 or p > WEEK or l < 0 or l > 100 then return end
    StoreReport(floor(n), friend, floor(p), floor(l))
end

-- =============================================================================
-- Uddelingen: toast og chatbesked til alle, første gang de ser den afsluttede uge
-- =============================================================================
local function CupList(list, max)
    local parts = {}
    for i = 1, math.min(#list, max or #list) do parts[i] = list[i].cup.name end
    local s = table.concat(parts, ", ")
    if max and #list > max then s = s .. string.format(L(" +%d mere"), #list - max) end
    return s
end

function Weekly.CeremonyLines(n)
    local winners = Weekly.Winners(n)
    local lines = {}
    for _, cup in ipairs(Weekly.CUPS) do
        local r = winners[cup.id]
        if r then
            lines[#lines + 1] = string.format(L("  |cffffd100%s|r: %s (%s)"), cup.name, Who(r.f), Weekly.ValueText(cup.id, r))
        end
    end
    return lines
end

function Weekly.Ceremony(now)
    local db, wk = DB()
    if not db.me then return end
    now = now or time()
    local cur = Ensure(now)
    local last = cur - 1
    if (wk.shown or -1) >= last then return end
    if now < Weekly.End(last) + ANNOUNCE_DELAY then return end
    if now >= Weekly.End(last) + WEEK then wk.shown = last return end
    -- Sidste chance for at få de nyeste tal med
    local h = wk.hist[last]
    if h and not h.fz then h.w = Weekly.Compute(last, false).w end
    wk.shown = last
    local winners = Weekly.Winners(last)
    local lines = Weekly.CeremonyLines(last)
    if #lines == 0 then return end
    local week = Weekly.Number(last)
    if db.settings.announce ~= false then
        Print(string.format(L("|cffffd100Ugens pokaler (uge %d)|r er uddelt:"), week))
        for _, line in ipairs(lines) do print(line) end
    end
    local mine = Weekly.Won(db.me, now)
    local top = Tally(winners)[1]
    local title, icon
    if #mine > 0 then
        title = (#mine == 1) and L("Du vandt en pokal!") or string.format(L("Du vandt %d pokaler!"), #mine)
        icon = mine[1].cup.icon
    else
        local theirs = Weekly.Won(top.f, now)
        title = (top.n == 1) and string.format(L("%s vandt en pokal"), Name(top.f))
            or string.format(L("%s vandt %d pokaler"), Name(top.f), top.n)
        icon = theirs[1] and theirs[1].cup.icon
    end
    local parts = {}
    for _, x in ipairs(Tally(winners)) do
        parts[#parts + 1] = Name(x.f) .. " " .. x.n
        if #parts >= 4 then break end
    end
    ns.Toast({ kind = "trophy", head = string.format(L("UGENS POKALER - UGE %d"), week), title = title,
               text = (#mine > 0) and CupList(mine, 3) or table.concat(parts, ", "),
               icon = icon, sound = "achievement", friend = top.f, dur = 8 })
end

-- Nyhederne: én linje pr. uddeling
function Weekly.NewsItems(now)
    local cur = Ensure(now)
    local out = {}
    local _, wk = DB()
    for n, h in pairs(wk.hist) do
        if n < cur and h.w and next(h.w) then
            local parts = {}
            for _, x in ipairs(Tally(h.w)) do
                parts[#parts + 1] = Who(x.f) .. " " .. x.n
                if #parts >= 4 then break end
            end
            out[#out + 1] = { t = Weekly.End(n), key = "w" .. n,
                              text = string.format(L("|cffffd100Ugens pokaler|r (uge %d) er uddelt: %s"), Weekly.Number(n), table.concat(parts, ", ")) }
        end
    end
    return out
end

-- =============================================================================
-- Kort og tooltips
-- =============================================================================
-- Tooltip-linjer om vennens pokaler (tom liste, hvis vennen ingen har)
function Weekly.TooltipLines(friend, now)
    local won, n = Weekly.Won(friend, now)
    local lines = {}
    local cab = Weekly.Cabinet(now)[friend]
    if #won == 0 and not cab then return lines end
    if #won > 0 then
        lines[#lines + 1] = string.format(L("Ugens pokaler (uge %d)"), Weekly.Number(n))
        for _, x in ipairs(won) do
            lines[#lines + 1] = string.format("  |T%s:12:12:0:0|t %s (%s)", x.cup.icon, x.cup.name, Weekly.ValueText(x.cup.id, x.r))
        end
    end
    if cab then lines[#lines + 1] = string.format(L("Pokalskabet: %d i alt"), cab.n) end
    return lines
end

-- Lille pokal på vennens kort (det første, vennen vandt sidste uge) og et tal, hvis der er flere
function ns.WeeklyCard(card, friend, mini)
    if not card then return end
    if not rawget(card, "cup") then
        local size = mini and 14 or 18
        card.cup = card:CreateTexture(nil, "OVERLAY")
        card.cup:SetSize(size, size)
        if mini then
            card.cup:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 5)
        else
            card.cup:SetPoint("TOPRIGHT", card, "TOPRIGHT", -22, -7)
        end
        card.cup:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        card.cupN = C.Txt(card, "GameFontNormalSmall")
        card.cupN:SetPoint("RIGHT", card.cup, "LEFT", -2, 0)
        card.cupN:SetJustifyH("RIGHT")
    end
    local won = friend and Weekly.Won(friend) or {}
    if #won == 0 then
        card.cup:Hide()
        card.cupN:SetText("")
        return
    end
    card.cup:SetTexture(won[1].cup.icon)
    card.cup:Show()
    card.cupN:SetText(#won > 1 and ("|cffffd100" .. #won .. "x|r") or "")
end

-- =============================================================================
-- Side 18: Sjov > Ugens pokaler
-- =============================================================================
local Txt, MakeBox = C.Txt, C.MakeBox
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN
local ui = {}
Weekly.ui = ui

local function Header(box, text)
    local h = Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(text)
    h:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    local s = Txt(box, "GameFontHighlightSmall")
    s:SetPoint("LEFT", h, "RIGHT", 8, -1)
    s:SetTextColor(0.5, 0.5, 0.56)
    return h, s
end

local function ShowRanking(owner, cup, rank, title)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(cup.name, 1, 0.82, 0.2)
    GameTooltip:AddLine(cup.desc, 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(title, 0.6, 0.6, 0.66)
    if not rank or #rank == 0 then
        GameTooltip:AddLine(L("Ingen kandidater endnu"), 0.5, 0.5, 0.56)
    else
        for i = 1, math.min(5, #rank) do
            local x = rank[i]
            GameTooltip:AddDoubleLine(i .. ". " .. Name(x.f), Weekly.ValueText(cup.id, x), 1, 1, 1, 1, 0.82, 0.2)
        end
    end
    GameTooltip:Show()
end

local function MakeRow(parent, y, h, iconSize, onEnter)
    local row = MakeBox("Button", parent, COL_BTN, COL_BORDER)
    row:SetSize(342, h)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = Txt(row, "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(160)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.who = Txt(row, "GameFontHighlight")
    row.who:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.who:SetWidth(150)
    row.who:SetJustifyH("RIGHT")
    row.who:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        onEnter(self)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
        GameTooltip:Hide()
    end)
    return row
end

local function BuildPage(page)
    -- Venstre: sidste uges vindere
    local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(362)
    local _, sub = Header(left, L("Sidste uges pokaler"))
    ui.lastSub = sub
    ui.last = {}
    for i, cup in ipairs(Weekly.CUPS) do
        local row = MakeRow(left, -(38 + (i - 1) * 31), 28, 22, function(self)
            local n = Weekly.Index(time()) - 1
            ShowRanking(self, self.cup, Weekly.Compute(n, false).rank[self.cup.id],
                string.format(L("Uge %d"), Weekly.Number(n)))
        end)
        row.cup = cup
        row.icon:SetTexture(cup.icon)
        row.name:SetText(cup.name)
        ui.last[i] = row
    end
    ui.note = Txt(left, "GameFontHighlightSmall")
    ui.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 10)
    ui.note:SetWidth(338)
    ui.note:SetTextColor(0.5, 0.5, 0.56)
    ui.note:SetText(L("Pokalerne uddeles hver søndag kl. 20. Vinderne har pokalen på kortet i en uge. Hold musen over en pokal for at se top 5."))

    -- Højre: denne uge indtil videre og pokalskabet
    local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(362)
    local _, sub2 = Header(right, L("Denne uge"))
    ui.nowSub = sub2
    ui.now = {}
    for i, cup in ipairs(Weekly.CUPS) do
        local row = MakeRow(right, -(38 + (i - 1) * 21), 20, 14, function(self)
            ShowRanking(self, self.cup, ui.live and ui.live.rank[self.cup.id], L("Indtil videre"))
        end)
        row.cup = cup
        row.icon:SetTexture(cup.icon)
        row.name:SetText(cup.name)
        row.name:SetFontObject("GameFontHighlightSmall")
        row.who:SetFontObject("GameFontHighlightSmall")
        ui.now[i] = row
    end
    local ch = Txt(right, "GameFontNormal")
    ch:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -(38 + #Weekly.CUPS * 21 + 10))
    ch:SetText(L("Pokalskabet"))
    ch:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    ui.cabinet = Txt(right, "GameFontHighlightSmall")
    ui.cabinet:SetPoint("TOPLEFT", ch, "BOTTOMLEFT", 0, -6)
    ui.cabinet:SetWidth(338)
    ui.cabinet:SetJustifyH("LEFT")
    ui.cabinet:SetSpacing(3)
end

local function RefreshPage()
    local now = time()
    local cur = Ensure(now)
    local winners = Weekly.Winners(cur - 1)
    ui.lastSub:SetText(string.format(L("uge %d"), Weekly.Number(cur - 1)))
    for _, row in ipairs(ui.last) do
        local r = winners[row.cup.id]
        if r then
            row.who:SetText(Who(r.f) .. " |cff9a9aa6" .. Weekly.ValueText(row.cup.id, r) .. "|r")
            row:SetBackdropColor(0.20, 0.17, 0.06, 1)
        else
            row.who:SetText("|cff666666" .. L("ingen") .. "|r")
            row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end

    ui.live = Weekly.Compute(cur, true)
    ui.nowSub:SetText(string.format(L("uddeles om %s"), ns.FormatPlayed and ns.FormatPlayed(math.max(60, Weekly.End(cur) - now)) or ""))
    for _, row in ipairs(ui.now) do
        local top = ui.live.rank[row.cup.id][1]
        if top then
            row.who:SetText(Who(top.f) .. " |cff9a9aa6" .. Weekly.ValueText(row.cup.id, top) .. "|r")
        else
            row.who:SetText("|cff666666-|r")
        end
    end

    local cab = Weekly.Cabinet(now)
    local list = {}
    for f, e in pairs(cab) do list[#list + 1] = { f = f, n = e.n, by = e.by } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.f < b.f
    end)
    local lines = {}
    for i = 1, math.min(8, #list) do
        local x = list[i]
        local fav, favN
        for _, cup in ipairs(Weekly.CUPS) do
            local k = x.by[cup.id]
            if k and (not favN or k > favN) then fav, favN = cup, k end
        end
        lines[#lines + 1] = string.format(L("%d. %s  |cffffd100%d|r  |cff888888(mest: %s %dx)|r"), i, Who(x.f), x.n, fav.name, favN)
    end
    if #lines == 0 then lines[1] = L("|cff888888Tomt endnu. Første uddeling er søndag kl. 20.|r") end
    ui.cabinet:SetText(table.concat(lines, "\n"))
end

C.EXTRA_PAGES[18] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Kommando, nulstilling og events
-- =============================================================================
function ns.WeeklySlash(cmd)
    if cmd ~= "pokaler" and cmd ~= "pokal" and cmd ~= "cups" and cmd ~= "weekly" then return false end
    local cur = Ensure()
    local lines = Weekly.CeremonyLines(cur - 1)
    Print(string.format(L("|cffffd100Ugens pokaler (uge %d)|r:"), Weekly.Number(cur - 1)))
    if #lines == 0 then print(L("  Ingen vindere.")) end
    for _, line in ipairs(lines) do print(line) end
    local live = Weekly.Compute(cur, false)
    local now = {}
    for _, cup in ipairs(Weekly.CUPS) do
        local r = live.w[cup.id]
        if r then now[#now + 1] = cup.name .. ": " .. Name(r.f) end
    end
    print(string.format(L("Denne uge indtil videre: %s"), #now > 0 and table.concat(now, ", ") or L("ingen")))
    return true
end

function ns.ResetWeekly()
    local db = WastedCoastDB
    if db then db.weekly = nil end
    Weekly.updated = nil
end

local function Tick()
    if not WastedCoastDB or not WastedCoastDB.me then return end
    local now = time()
    local n = Weekly.Index(now)
    local rolled = tickWeek ~= nil and tickWeek ~= n
    tickWeek = n
    Weekly.Track(now)
    -- Send ved ugeskifte (så den afsluttede uges sidste tal kommer med) og hvert kvarter
    if rolled or (GetTime() - lastSend >= RESEND) then Weekly.Send() end
    Weekly.Update(now)
    Weekly.Ceremony(now)
end
Weekly.Tick = Tick

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(_, event)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        loadedAt = GetTime()
        lastSend = GetTime()
        C_Timer.After(40, function() pcall(Tick) end)
        C_Timer.NewTicker(60, function() pcall(Tick) end)
    elseif event == "PLAYER_LEVEL_UP" then
        Weekly.OnLevelUp()
    end
end)
