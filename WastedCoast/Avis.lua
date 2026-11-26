local _, ns = ...
local L = ns.L

-- =============================================================================
-- Wasted Coast Tidende: dagens vigtigste begivenheder som en avis
--   * Avisen åbner ved hvert login (ikke ved /reload eller zone-skift) og samler det, der er sket i
--     banden i dag, fra kl. 00.00 i din lokale tid til nu. /wc4ever avis viser den igen,
--     og Sjov > Avisen viser dagens linjer i hovedvinduet.
--   * v0.32: kun det væsentlige. Fire rubrikker med én faktuel linje pr. begivenhed og klokkeslæt:
--     Dødsfald (alle dagens dødsfald), Loot (rare, epic og legendary), Levels og Bedrifter
--     (instanser, max level, maxet profession, Revered/Exalted, rare mobs og trofæer).
--     Højst 4 linjer pr. rubrik i vinduet, nyeste først. Alle fire rubrikker vises altid (v0.32.1),
--     en tom med en kort grå linje, og rubrikkerne fylder mindst SEC_MIN_H, så avisen ikke bliver lille. Forsiden er dagens tungeste begivenhed (se vægtene i Collect) med fire tal
--     ved siden af, og level-løbet står på én linje nederst. Horoskop, annoncer, vejret,
--     Skammens hat og skandalerne er fjernet fra avisen (hatten og drillerierne findes stadig
--     andre steder i addonet).
--   * "Kopiér til Discord" giver avisen som ren tekst, klar til Ctrl+C.
--   * Avisen sender ingen beskeder. Den bygger på det, addonet allerede har og synker: dødsfald,
--     loot, levels, rare mobs, trofæer og sladderens målinger (professions, reputation og instanser).
--   * Det, der ikke har et tidspunkt (levels, professions, instanser ...), sammenlignes med et
--     øjebliksbillede, der tages første gang addonet kører på en ny dato.
--   * Demo-data kommer aldrig i avisen. Daglig sladder (Gossip.lua) popper ikke op, når avisen er slået til.
--
-- db.avis = { day = dato (ÅÅÅÅ-MM-DD) for øjebliksbilledet, n = avisens nummer,
--             base = { lv, nc, chars, hk, bank, seen, st }  øjebliksbilledet fra dagens start,
--             hist = { [dato] = { t, lv = { ven -> level + XP/100 } } }  (de seneste 14 dage) }
--   (on, peak og duo fra v0.30 bruges ikke længere og bliver liggende urørt.)
-- db.settings.avis = false: avisen åbner ikke af sig selv ved login (/wc4ever avis virker stadig)
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name

local A = {}
ns.Avis = A

A.SHOW_DELAY = 30        -- sekunder efter login, så vennernes data er nået frem
A.PER_SECTION = 4        -- linjer pr. rubrik i vinduet
A.PLAIN_PER_SECTION = 10 -- linjer pr. rubrik i Discord-teksten
A.HIST_DAYS = 14

local PROF_MAX = (C.MAX_LEVEL or 60) >= 70 and 375 or 300
local STANDING = { [7] = "Revered", [8] = "Exalted" }

local function DB()
    local db = WastedCoastDB
    db.avis = db.avis or {}
    local a = db.avis
    a.base = a.base or {}
    a.hist = a.hist or {}
    return db, a
end

local function IsDemo(e)
    return e.demo or e.d or (type(e.id) == "string" and e.id:find("^demo%-") ~= nil)
end

local function Today(t) return date("%Y-%m-%d", t or time()) end

-- Kl. 00.00 i dag (lokal tid), regnet ud fra klokken, så det også virker uden time(tabel)
local function Midnight(now)
    now = now or time()
    local t = date("*t", now)
    return now - ((t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0))
end
A.Midnight = Midnight

local function Clock(t) return date(L("%H.%M"), t) end

local function Red(s) return "|cff8a1c12" .. tostring(s) .. "|r" end
local DARK = { [3] = "0a4f9e", [4] = "5e2590", [5] = "a34700" }
local function Item(ev)
    local name = (ns.FixLootName and ns.FixLootName(ev)) or ev.name or "?"
    return "|cff" .. (DARK[ev.quality] or "3a2f22") .. "[" .. tostring(name) .. "]|r"
end
local function EnvOf(ev)
    for k, v in pairs(C.ENV_NAMES) do
        if ev.killer == v or ev.ability == v then return k end
    end
end
local function Where(z) return (type(z) == "string" and z ~= "") and (L(" i ") .. z) or "" end

-- Alle venner med karakterer (uden demo): højeste level med XP, klasse, zone, karakterer og honor kills
local function Friends()
    local out = {}
    for _, name in ipairs(ROSTER) do
        local info = WastedCoastDB.friends[name]
        local e = { lvl = 0, ls = 0, nc = 0, hk = 0, chars = {} }
        local seenBest
        for cn, c in pairs((info and info.chars) or {}) do
            if type(c) == "table" and not c.demo then
                e.nc = e.nc + 1
                e.chars[cn] = true
                local lv = tonumber(c.level) or 0
                local xp = ns.XPPct and ns.XPPct(lv, c.xp)
                local ls = lv + (xp or 0) / 100
                if ls > e.ls then e.ls, e.lvl, e.xp, e.cls = ls, lv, xp, c.class end
                if not seenBest or (c.seen or 0) > seenBest then seenBest, e.zone, e.cls2 = c.seen or 0, c.zone, c.class end
                if type(c.honor) == "table" and tonumber(c.honor.k) then e.hk = e.hk + tonumber(c.honor.k) end
            end
        end
        e.cls = e.cls or e.cls2
        if e.nc > 0 then out[name] = e end
    end
    return out
end
A.Friends = Friends

local function Snapshot()
    local db = WastedCoastDB
    local s = { lv = {}, nc = {}, chars = {}, hk = {}, bank = {}, seen = {}, st = (ns.GossipStats and ns.GossipStats()) or {} }
    for name, e in pairs(Friends()) do
        s.lv[name], s.nc[name], s.chars[name], s.hk[name] = e.ls, e.nc, e.chars, e.hk
    end
    for _, name in ipairs(ROSTER) do
        local b = db.bank and db.bank[name]
        if type(b) == "table" then
            s.bank[name] = { rep = b.rep or 0, wg = b.wg or 0, di = b.di or 0, grep = b.grep or 0 }
        end
        s.seen[name] = C.LastSeen(name)
    end
    return s
end

-- Første gang på en ny dato: tag et øjebliksbillede, som dagens tal sammenlignes med
function A.EnsureDay()
    local db, a = DB()
    local today = Today()
    if a.day == today then return false end
    a.day = today
    a.base = Snapshot()
    a.hist[today] = { t = Midnight(), lv = a.base.lv }
    local keys = {}
    for k in pairs(a.hist) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys - A.HIST_DAYS do a.hist[keys[i]] = nil end
    a.n = (a.n or 0) + 1
    return true
end

-- Hvert minut: ny dag? Og en ven, der ikke var med i øjebliksbilledet (ny i gruppen eller
-- ingen data endnu), får sit nu, så hele vennens level ikke tæller som "i dag"
function A.Track()
    local db, a = DB()
    if not db.me then return end
    A.EnsureDay()
    local base = a.base
    if base and base.lv then
        for name, e in pairs(Friends()) do
            if not base.lv[name] then
                base.lv[name] = e.ls
                if base.chars then base.chars[name] = e.chars end
                if base.hk then base.hk[name] = e.hk end
                if base.nc then base.nc[name] = e.nc end
            end
        end
    end
end

-- =============================================================================
-- Rubrikkerne
-- =============================================================================
A.SECTIONS = { "dod", "loot", "lvl", "bed" }
local SEC_NAME = ns.LT({ dod = "Dødsfald", loot = "Loot", lvl = "Levels", bed = "Bedrifter" })
local STAT_NAME = ns.LT({ dod = "dødsfald", loot = "loot", lvl = "levels", bed = "bedrifter" })
local SEC_EMPTY = ns.LT({ dod = "Ingen dødsfald i dag.", loot = "Ingen rare eller epic loot i dag.",
                          lvl = "Ingen levels i dag.", bed = "Ingen bedrifter i dag." })
A.SEC_NAME = SEC_NAME

local WEEKDAYS = ns.LT({ "søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag" })
local MONTHS = ns.LT({ "januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september", "oktober", "november", "december" })

-- =============================================================================
-- Dagens avis: én linje pr. begivenhed. Hver linje har en vægt; den tungeste bliver forsiden.
--   { sec, w, f = ven, h = overskrift (til forsiden), t = linjen, at = tidspunkt (kan mangle) }
-- =============================================================================
function A.Collect()
    local db, a = DB()
    A.EnsureDay()
    local now, since = time(), Midnight()
    local base = a.base or {}
    local P = { since = since, now = now, sec = {}, stats = {}, extra = {} }
    for _, k in ipairs(A.SECTIONS) do P.sec[k] = {} end
    local function add(sec, w, f, h, t, at)
        local e = { sec = sec, w = w, f = f, h = h, t = t, at = at }
        table.insert(P.sec[sec], e)
        return e
    end
    local fr = Friends()
    local function N(f) return Name(f) end

    -- ---------------------------------------------------------------- Dødsfald (alle)
    local byF = {}
    for _, ev in ipairs(db.events or {}) do
        if type(ev) == "table" and not IsDemo(ev) then
            local f = C.EventFriend(ev)
            local t = tonumber(ev.time)
            if f and t and t >= since and t <= now + 60 then
                -- Tal og tekst efterprøves, så et ødelagt dødsfald ikke vælter avisen
                local zone = type(ev.zone) == "string" and ev.zone or nil
                local killer = type(ev.killer) == "string" and ev.killer ~= "" and ev.killer ~= "Ukendt" and ev.killer or nil
                local klvl, lvl = tonumber(ev.klvl), tonumber(ev.level)
                local env = EnvOf(ev)
                local text
                if env then
                    text = string.format(L("%s døde af %s"), N(f), L(C.ENV_NAMES[env]):lower())
                elseif killer and ev.pvp == true then
                    text = string.format(L("%s blev dræbt af %s"), N(f), killer)
                elseif killer then
                    text = string.format(L("%s døde til %s"), N(f), L(killer)) .. ((klvl and klvl > 0) and (" (" .. klvl .. ")") or "")
                else
                    text = string.format(L("%s døde"), N(f))
                end
                text = text .. Where(zone) .. "."
                byF[f] = (byF[f] or 0) + 1
                local w = (lvl and lvl >= C.MAX_LEVEL) and 70 or 30
                add("dod", w, f, string.format(L("%s døde"), N(f)) .. Where(zone), text, t)
            end
        end
    end
    -- Mange dødsfald til samme ven kan blive forsiden
    for f, n in pairs(byF) do
        if n >= 3 then
            local last
            for _, e in ipairs(P.sec.dod) do if e.f == f and (not last or e.at > last.at) then last = e end end
            P.extra[#P.extra + 1] = { sec = "dod", w = 50 + n, f = f, h = string.format(L("%s døde %d gange i dag"), N(f), n),
                                      t = string.format(L("Sidste gang: %s"), last.t), at = last.at }
        end
    end

    -- ---------------------------------------------------------------- Loot (rare og bedre)
    for _, ev in ipairs(db.loot or {}) do
        local t = type(ev) == "table" and tonumber(ev.time)
        local q = type(ev) == "table" and tonumber(ev.quality) or 0
        if t and t >= since and q >= 3 and not IsDemo(ev) then
            local f = C.EventFriend({ friend = ev.friend, name = ev.char })
            if f then
                local text = string.format(L("%s fik %s"), N(f), Item(ev)) .. Where(ev.zone) .. "."
                if q >= 5 then
                    add("loot", 100, f, string.format(L("Legendarisk til %s"), N(f)), text, t).q = q
                elseif q == 4 then
                    local first = true
                    for _, o in ipairs(db.loot) do
                        if type(o) == "table" and o ~= ev and not IsDemo(o) and (tonumber(o.quality) or 0) >= 4 and (tonumber(o.time) or 0) < t
                            and C.EventFriend({ friend = o.friend, name = o.char }) == f then first = false break end
                    end
                    if first then
                        add("loot", 74, f, string.format(L("Første epic til %s"), N(f)), text, t).q = q
                    else
                        add("loot", 66, f, string.format(L("%s i lilla"), N(f)), text, t).q = q
                    end
                else
                    add("loot", 25, f, string.format(L("Blåt held til %s"), N(f)), text, t).q = q
                end
            end
        end
    end

    -- ---------------------------------------------------------------- Levels
    local gained = 0
    for _, f in ipairs(ROSTER) do
        local e, b = fr[f], base.lv and base.lv[f]
        if e and b then
            local g = e.lvl - math.floor(b)
            if g > 0 then
                gained = gained + g
                local la = db.levelAt and db.levelAt[f]
                local at = (la and not la.g and tonumber(la.l) == e.lvl and (tonumber(la.t) or 0) >= since) and la.t or nil
                local text = g == 1 and string.format(L("%s nåede level %d."), N(f), e.lvl)
                    or string.format(L("%s gik fra level %d til %d."), N(f), e.lvl - g, e.lvl)
                local h = g == 1 and string.format(L("%s nåede level %d"), N(f), e.lvl)
                    or string.format(L("%s tog %d levels"), N(f), g)
                add("lvl", g >= 3 and 73 or (g == 2 and 52 or 40), f, h, text, at)
                if e.lvl >= C.MAX_LEVEL then
                    add("bed", 100, f, string.format(L("%s er i mål"), N(f)), string.format(L("%s ramte max level %d."), N(f), e.lvl), at)
                end
            end
        end
    end

    -- ---------------------------------------------------------------- Bedrifter
    -- Instanser, professions og reputation (sammenlignet med dagens start)
    local cur = (ns.GossipStats and ns.GossipStats()) or {}
    local bst = base.st or {}
    for _, f in ipairs(ROSTER) do
        local b, n = bst[f], cur[f]
        if type(b) == "table" and type(n) == "table" then
            for inst, r in pairs(n.runs or {}) do
                local o = (b.runs and b.runs[inst]) or { c = 0, b = 0 }
                local dc = (tonumber(r.c) or 0) - (tonumber(o.c) or 0)
                if dc > 0 then
                    local bosses = math.max(0, (tonumber(r.b) or 0) - (tonumber(o.b) or 0))
                    local h = string.format(L("%s ryddede %s"), N(f), L(inst))
                    local tail = ""
                    if dc >= 2 then tail = string.format(L(" %d gange"), dc) end
                    if bosses >= 2 then tail = tail .. string.format(L(" (%d bosser)"), bosses) end
                    add("bed", 60 + math.min(10, bosses), f, h, h .. tail .. ".")
                end
            end
            for pn, rank in pairs(n.prof or {}) do
                local old = b.prof and b.prof[pn]
                if old and rank >= PROF_MAX and old < PROF_MAX then
                    add("bed", 58, f, string.format(L("%s er mester i %s"), N(f), L(pn)), string.format(L("%s maxede %s (%d)."), N(f), L(pn), rank))
                end
            end
            local hadRep = b.rep and next(b.rep) ~= nil
            for fac, sd in pairs(n.rep or {}) do
                local old = (b.rep and b.rep[fac]) or (hadRep and 4) or nil
                if old and STANDING[sd] and sd > old then
                    local text = string.format(L("%s er nu %s med %s."), N(f), STANDING[sd], fac)
                    add("bed", sd >= 8 and 62 or 44, f, string.format(L("%s er %s"), N(f), STANDING[sd]), text)
                end
            end
        end
    end
    -- Rare mobs
    for _, r in ipairs(db.rareLog or {}) do
        local t = type(r) == "table" and tonumber(r.t)
        if t and t >= since and ROSTER_SET[r.friend] and not r.demo then
            local mob = type(r.mob) == "string" and r.mob or "?"
            add("bed", 41, r.friend, string.format(L("%s nedlagde %s"), N(r.friend), mob),
                string.format(L("%s nedlagde %s"), N(r.friend), mob) .. Where(r.zone) .. ".", t)
        end
    end
    -- Trofæer
    for _, f in ipairs(ROSTER) do
        for id, t in pairs((db.ach and db.ach[f]) or {}) do
            local ac = C.ACH_BY_ID and C.ACH_BY_ID[id]
            if ac and type(t) == "number" and t >= since and not (db.demoAch and db.demoAch[f] and db.demoAch[f][id]) then
                add("bed", 38 + math.min(10, (ac.pts or 0) / 5), f, string.format(L("Trofæ til %s"), N(f)),
                    string.format(L("%s fik trofæet %s."), N(f), ac.name or "?"), t)
            end
        end
    end

    -- ---------------------------------------------------------------- Sortering: nyeste først
    -- Loot: legendary og epic før rare. Linjer uden tidspunkt kommer sidst, tungeste først.
    for _, k in ipairs(A.SECTIONS) do
        table.sort(P.sec[k], function(x, y)
            if (x.q or 0) ~= (y.q or 0) then return (x.q or 0) > (y.q or 0) end
            if (x.at ~= nil) ~= (y.at ~= nil) then return x.at ~= nil end
            if x.at and y.at and x.at ~= y.at then return x.at > y.at end
            if x.w ~= y.w then return x.w > y.w end
            return (x.t or "") < (y.t or "")
        end)
    end

    -- ---------------------------------------------------------------- Forsiden og tallene
    local lead
    local function consider(e)
        if not lead or e.w > lead.w or (e.w == lead.w and (e.at or 0) > (lead.at or 0)) then lead = e end
    end
    for _, k in ipairs(A.SECTIONS) do for _, e in ipairs(P.sec[k]) do consider(e) end end
    for _, e in ipairs(P.extra) do consider(e) end
    P.lead = lead or { sec = "lvl", w = 0, h = L("Stille dag i Wasted Coast"),
                       t = L("Ingen døde, ingen loot og ingen levels endnu i dag.") }
    P.stats = { dod = #P.sec.dod, loot = #P.sec.loot, lvl = gained, bed = #P.sec.bed }
    P.count = #P.sec.dod + #P.sec.loot + #P.sec.lvl + #P.sec.bed

    -- ---------------------------------------------------------------- Level-løbet
    local race = {}
    for f, e in pairs(fr) do
        if e.lvl > 0 then race[#race + 1] = { f = f, lvl = e.lvl, xp = e.xp, ls = e.ls, gain = (base.lv and base.lv[f]) and (e.lvl - math.floor(base.lv[f])) or 0 } end
    end
    table.sort(race, function(x, y) if x.ls ~= y.ls then return x.ls > y.ls end return x.f < y.f end)
    P.race = race

    -- Forsidens tekst: linjen (hvis den siger mere end overskriften), klokkeslæt og pladsen i level-løbet
    if lead then
        local parts = {}
        if lead.t ~= lead.h .. "." then parts[#parts + 1] = lead.t end
        if lead.at then parts[#parts + 1] = string.format(L("Kl. %s."), Clock(lead.at)) end
        for i, x in ipairs(race) do
            if x.f == lead.f then
                parts[#parts + 1] = string.format(L("%s ligger nummer %d i level-løbet."), Name(x.f), i)
                break
            end
        end
        P.lead = { sec = lead.sec, w = lead.w, f = lead.f, h = lead.h, at = lead.at, t = table.concat(parts, " ") }
    end
    return P
end

function A.DateLine(t)
    local d = date("*t", t or time())
    return string.format(L("%s d. %d. %s"), WEEKDAYS[d.wday] or "", d.day, MONTHS[d.month] or "")
end

-- Level-løbet på én linje: "1. Mathias 47 · 2. Frode 37 (+1) · ..."
function A.RaceLine(P, color)
    local parts = {}
    for i, x in ipairs(P.race or {}) do
        local s = i .. ". " .. Name(x.f) .. " " .. x.lvl
        if x.gain > 0 then s = s .. " " .. (color and Red("(+" .. x.gain .. ")") or ("(+" .. x.gain .. ")")) end
        parts[#parts + 1] = s
    end
    return table.concat(parts, " · ")
end

-- Ren tekst til Discord (uden farvekoder og links)
local function Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return s
end
A.Plain = Plain

function A.PlainText(P)
    local out = {}
    local function w(s) out[#out + 1] = Plain(s) end
    w("**" .. L("Wasted Coast Tidende") .. "** - " .. A.DateLine(P.now))
    w("")
    w("**" .. P.lead.h .. "**")
    w(P.lead.t)
    for _, k in ipairs(A.SECTIONS) do
        local list = P.sec[k]
        if #list > 0 then
            w("")
            w("__" .. SEC_NAME[k] .. "__ (" .. #list .. ")")
            for i, e in ipairs(list) do
                if i > A.PLAIN_PER_SECTION then
                    w("- " .. string.format(L("... og %d mere"), #list - A.PLAIN_PER_SECTION))
                    break
                end
                w("- " .. e.t .. (e.at and (" (" .. Clock(e.at) .. ")") or ""))
            end
        end
    end
    if #P.race > 0 then
        w("")
        w("__" .. L("Stillingen i level-løbet") .. "__")
        w(A.RaceLine(P, false))
    end
    return table.concat(out, "\n")
end

-- =============================================================================
-- Vinduet: avisen i spillet. Højden følger indholdet: tomme rubrikker vises ikke.
-- =============================================================================
local ui = {}
A.ui = ui
local PAPER = { 0.93, 0.88, 0.76, 1 }
local INK = { 0.16, 0.12, 0.08 }
local GREY = { 0.35, 0.29, 0.21 }
local RED = { 0.54, 0.11, 0.07 }
local HEAD_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local WIN_W = 1000
local PAD = 28
local W = WIN_W - 28 - 2 * PAD          -- avisens indre bredde
local COL_GAP = 28
local COL_W = math.floor((W - 3 * COL_GAP) / 4)
local TIME_W = 38
local LEAD_W = 600
local SEC_MIN_H = 220     -- rubrikkerne fylder altid mindst så meget, så avisen ikke bliver lille

local function Ink(parent, size, font, col, justify)
    local fs = C.Txt(parent, "GameFontHighlight")
    pcall(fs.SetFont, fs, font or BODY_FONT, size or 11, "")
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    local c = col or INK
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    fs:SetWordWrap(true)
    return fs
end

local function Rule(parent, h)
    local t = parent:CreateTexture(nil, "ARTWORK")
    C.BarFill(t, INK[1], INK[2], INK[3], 1)
    t:SetSize(W, h or 1)
    return t
end

local function Height(fs)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return (type(h) == "number" and h > 0) and h or 14
end

-- En rubrik: titel og antal, streg og op til PER_SECTION linjer med klokkeslæt til højre
local function Section(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(COL_W, 40)
    box.title = Ink(box, 19, HEAD_FONT, INK)
    box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    box.title:SetWidth(COL_W - 30)
    box.count = Ink(box, 11, BODY_FONT, GREY, "RIGHT")
    box.count:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -5)
    box.count:SetWidth(30)
    local r = box:CreateTexture(nil, "ARTWORK")
    C.BarFill(r, INK[1], INK[2], INK[3], 1)
    r:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -26)
    r:SetSize(COL_W, 2)
    box.rows = {}
    for i = 1, A.PER_SECTION do
        local row = { t = Ink(box, 12), c = Ink(box, 11, BODY_FONT, GREY, "RIGHT") }
        row.t:SetWidth(COL_W - TIME_W - 6)
        row.c:SetWidth(TIME_W)
        box.rows[i] = row
    end
    return box
end

-- Fylder rubrikken og giver dens højde. En tom rubrik får en kort grå linje.
local function Fill(box, title, list, empty)
    box.title:SetText(title)
    box.count:SetText(tostring(#list))
    local blank = #list == 0
    if blank then list = { { t = empty } } end
    local y = -38
    for i, row in ipairs(box.rows) do
        local e = list[i]
        if e and i == A.PER_SECTION and #list > A.PER_SECTION then
            e = { t = string.format(L("... og %d mere"), #list - A.PER_SECTION + 1) }
        end
        row.t:ClearAllPoints()
        row.c:ClearAllPoints()
        if e then
            row.t:SetText(e.t)
            local c = blank and GREY or INK
            row.t:SetTextColor(c[1], c[2], c[3])
            row.c:SetText(e.at and Clock(e.at) or "")
            row.t:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
            row.c:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, y - 1)
            row.t:Show()
            row.c:Show()
            y = y - Height(row.t) - 12
        else
            row.t:Hide()
            row.c:Hide()
        end
    end
    box:SetHeight(-y)
    return -y
end

local function BuildWindow()
    local p = C.MakeBox("Frame", UIParent, C.COL_BG, C.COL_GOLD, "WastedCoastAvis")
    p:SetSize(WIN_W, 560)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    if p.SetClampedToScreen then p:SetClampedToScreen(true) end
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if C.AddShadow then C.AddShadow(p, 8) end
    table.insert(UISpecialFrames, "WastedCoastAvis")

    local logo = p:CreateTexture(nil, "OVERLAY")
    logo:SetSize(52, 52)
    logo:SetPoint("TOPLEFT", p, "TOPLEFT", -14, 14)
    logo:SetTexture(ns.LOGO)
    local title = C.Txt(p, "GameFontNormal")
    title:SetPoint("TOP", p, "TOP", 0, -12)
    title:SetText(L("Wasted Coast Forever"))
    local close = C.MakeCloseButton(p, 24, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -6)

    local paper = C.MakeBox("Frame", p, PAPER, { 0.45, 0.36, 0.2, 1 })
    paper:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -36)
    paper:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 48)
    ui.paper = paper

    local function at(fs, x, y, w) fs:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + x, y) if w then fs:SetWidth(w) end end
    ui.dateL = Ink(paper, 11) at(ui.dateL, 0, -16, 400)
    ui.dateR = Ink(paper, 11, nil, nil, "RIGHT") at(ui.dateR, W - 200, -16, 200)
    ui.mast = Ink(paper, 46, HEAD_FONT, INK, "CENTER") at(ui.mast, 0, -32, W)
    ui.mast:SetText(L("Wasted Coast Tidende"))
    Rule(paper, 2):SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, -92)
    Rule(paper, 1):SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, -96)

    -- Forsiden: overskrift til venstre, dagens fire tal til højre
    ui.kick = Ink(paper, 11, BODY_FONT, RED) at(ui.kick, 0, -116, LEAD_W)
    ui.kick:SetText(L("DAGENS STORE BEGIVENHED"))
    ui.head = Ink(paper, 34, HEAD_FONT, INK) at(ui.head, 0, -134, LEAD_W)
    ui.body = Ink(paper, 14, BODY_FONT, INK)
    ui.body:SetPoint("TOPLEFT", ui.head, "BOTTOMLEFT", 0, -10)
    ui.body:SetWidth(LEAD_W)
    local vr = paper:CreateTexture(nil, "ARTWORK")
    C.BarFill(vr, INK[1], INK[2], INK[3], 1)
    vr:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + LEAD_W + 24, -118)
    vr:SetSize(1, 70)
    local sx = LEAD_W + 48
    local sw = math.floor((W - sx) / 4)
    ui.statN, ui.statL = {}, {}
    for i, k in ipairs(A.SECTIONS) do
        ui.statN[i] = Ink(paper, 30, HEAD_FONT, INK) at(ui.statN[i], sx + (i - 1) * sw, -120, sw)
        ui.statL[i] = Ink(paper, 11, BODY_FONT, GREY) at(ui.statL[i], sx + (i - 1) * sw, -160, sw)
        ui.statL[i]:SetText(STAT_NAME[k])
    end
    ui.midRule = Rule(paper, 1)

    -- Rubrikkerne: altid alle fire, side om side
    ui.box = {}
    for _, k in ipairs(A.SECTIONS) do ui.box[k] = Section(paper) end

    -- Level-løbet på én linje
    ui.raceRule1 = Rule(paper, 2)
    ui.raceRule2 = Rule(paper, 1)
    ui.raceKick = Ink(paper, 11, BODY_FONT, RED)
    ui.raceKick:SetWidth(W)
    ui.raceKick:SetText(L("STILLINGEN I LEVEL-LØBET"))
    ui.race = Ink(paper, 13, BODY_FONT, INK)
    ui.race:SetWidth(W)

    -- Knapper
    local discord = C.MakeButton(p, 150, 26, L("Kopiér til Discord"), function() A.ShowCopy() end)
    discord:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 12)
    local open = C.MakeButton(p, 130, 26, L("Åbn WC4ever"), function()
        p:Hide()
        if ns.frame then ns.frame:Show() if ns.ShowTab then ns.ShowTab(20) end end
    end)
    open:SetPoint("LEFT", discord, "RIGHT", 6, 0)
    local done = C.MakeButton(p, 100, 26, L("Luk avisen"), function() p:Hide() end)
    done:SetPoint("LEFT", open, "RIGHT", 6, 0)
    local hint = C.Txt(p, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 19)
    hint:SetTextColor(0.6, 0.58, 0.52)
    hint:SetText(L("Avisen kommer ved hvert login. /wc4ever avis fra slår det fra."))

    ui.frame = p
    return p
end

local function Render(P)
    local p = ui.frame or BuildWindow()
    local _, a = DB()
    local paper = ui.paper
    ui.P = P
    local d = A.DateLine(P.now)
    ui.dateL:SetText(d:sub(1, 1):upper() .. d:sub(2) .. " · " .. string.format(L("kl. %s"), Clock(P.now)))
    ui.dateR:SetText(string.format(L("Nr. %d"), a.n or 1))
    ui.head:SetText(P.lead.h)
    ui.body:SetText(P.lead.t)
    for i, k in ipairs(A.SECTIONS) do ui.statN[i]:SetText(tostring(P.stats[k] or 0)) end

    -- Under forsiden: lige under overskrift og tekst, men mindst under tallene
    local bodyH = (P.lead.t ~= "" and (10 + Height(ui.body))) or 0
    local y = -math.max(206, 134 + Height(ui.head) + bodyH + 24)
    ui.midRule:ClearAllPoints()
    ui.midRule:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, y)
    y = y - 22

    -- Rubrikkerne: alle fire, også de tomme
    local tallest = SEC_MIN_H
    for i, k in ipairs(A.SECTIONS) do
        local box = ui.box[k]
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + (i - 1) * (COL_W + COL_GAP), y)
        tallest = math.max(tallest, Fill(box, SEC_NAME[k], P.sec[k], SEC_EMPTY[k]))
        box:Show()
    end
    y = y - tallest - 16

    -- Level-løbet
    local raceShown = #P.race > 0
    for _, o in ipairs({ ui.raceRule1, ui.raceRule2, ui.raceKick, ui.race }) do
        o:ClearAllPoints()
        if raceShown then o:Show() else o:Hide() end
    end
    if raceShown then
        ui.raceRule1:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, y)
        ui.raceRule2:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, y - 4)
        ui.raceKick:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, y - 18)
        ui.race:SetText(A.RaceLine(P, true))
        ui.race:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, y - 36)
        y = y - 36 - Height(ui.race)
    end
    ui.height = 36 + (-y + 24) + 48
    p:SetHeight(ui.height)
    return p
end

function A.Show(auto)
    local db = DB()
    if not db.me then
        if not auto then Print(L("Du er ikke med i en gruppe endnu. Avisen skriver kun om banden.")) end
        return
    end
    local P = A.Collect()
    A.last = P
    local p = Render(P)
    p:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
    if db.settings.announce and auto then
        Print("|cffffd100" .. L("Wasted Coast Tidende") .. ":|r " .. P.lead.h .. ". " .. P.lead.t)
    end
end
ns.ShowAvis = A.Show

-- Kopi-boksen: avisen som ren tekst, markeret, så Ctrl+C kopierer den
function A.ShowCopy()
    local P = ui.P or A.last or A.Collect()
    local text = A.PlainText(P)
    if not ui.copy then
        local box = C.MakeBox("Frame", UIParent, C.COL_BG, C.COL_GOLD, "WastedCoastAvisCopy")
        box:SetSize(560, 360)
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:EnableMouse(true)
        table.insert(UISpecialFrames, "WastedCoastAvisCopy")
        local t = C.Txt(box, "GameFontNormal")
        t:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        t:SetText(L("Tryk Ctrl+C for at kopiere, og sæt det ind i Discord"))
        local close = C.MakeCloseButton(box, 22, function() box:Hide() end)
        close:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
        local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -30, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        if ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
        eb:SetWidth(510)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() box:Hide() end)
        sf:SetScrollChild(eb)
        ui.copy, ui.copyEdit = box, eb
    end
    ui.copyEdit:SetText(text)
    ui.copy:Show()
    ui.copyEdit:SetFocus()
    ui.copyEdit:HighlightText()
    A.lastPlain = text
end

-- =============================================================================
-- Side 20: Sjov > Avisen (dagens linjer)
-- =============================================================================
local page = {}
local function BuildPage(pg)
    local box = C.MakeBox("Frame", pg, C.COL_PANEL, C.COL_BORDER)
    box:SetAllPoints(pg)
    local h = C.Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(L("Wasted Coast Tidende"))
    h:SetTextColor(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3])
    page.sub = C.Txt(box, "GameFontHighlightSmall")
    page.sub:SetPoint("LEFT", h, "RIGHT", 8, -1)
    page.sub:SetTextColor(0.6, 0.6, 0.66)
    local btn = C.MakeButton(box, 140, 24, L("Åbn dagens avis"), function() A.Show(false) end)
    btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -8)
    page.list = C.Txt(box, "GameFontHighlight")
    page.list:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -44)
    page.list:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    page.list:SetJustifyH("LEFT")
    if page.list.SetJustifyV then page.list:SetJustifyV("TOP") end
    page.list:SetSpacing(5)
    local note = C.Txt(box, "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
    note:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    note:SetTextColor(0.5, 0.5, 0.56)
    note:SetText(L("Avisen samler dagens dødsfald, loot, levels og bedrifter. Den åbner ved hvert login (/wc4ever avis fra slår det fra)."))
end

local function RefreshPage()
    if not page.list or not WastedCoastDB.me then return end
    local P = A.Collect()
    page.sub:SetText(A.DateLine(P.now) .. " · " .. C.Plural(P.count, L("begivenhed"), L("begivenheder")))
    local lines = { "|cffffd100" .. P.lead.h .. "|r  " .. P.lead.t }
    for _, k in ipairs(A.SECTIONS) do
        for _, e in ipairs(P.sec[k]) do
            if #lines < 16 then
                lines[#lines + 1] = "|cff9aa0a6" .. SEC_NAME[k] .. ":|r " .. e.t .. (e.at and (" |cff9aa0a6" .. Clock(e.at) .. "|r") or "")
            end
        end
    end
    page.list:SetText(table.concat(lines, "\n"))
end
C.EXTRA_PAGES[20] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Kommando og events
-- =============================================================================
function ns.AvisSlash(cmd, arg)
    if cmd ~= "avis" and cmd ~= "avisen" and cmd ~= "news" and cmd ~= "paper" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "fra" or arg == "off" then
        db.settings.avis = false
        Print(L("Avisen ved login: fra. |cffffd100/wc4ever avis|r virker stadig."))
    elseif arg == "til" or arg == "on" then
        db.settings.avis = nil
        Print(L("Avisen ved login: til."))
    elseif arg == "discord" then
        A.Show(false)
        A.ShowCopy()
    else
        A.Show(false)
    end
    return true
end

local shownThisSession = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, isInitial, isReload)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        -- Lidt efter, så gruppen og vennerne er indlæst, før dagens øjebliksbillede tages
        C_Timer.After(1, function() if WastedCoastDB.me then pcall(A.EnsureDay) end end)
        C_Timer.NewTicker(60, function() pcall(A.Track) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Kun ved et rigtigt login: ikke ved /reload eller når man skifter zone
        if shownThisSession or isInitial == false or isReload == true then return end
        shownThisSession = true
        C_Timer.After(A.SHOW_DELAY, function()
            local db = WastedCoastDB
            if db and db.me and db.settings.avis ~= false then pcall(A.Show, true) end
        end)
    end
end)
