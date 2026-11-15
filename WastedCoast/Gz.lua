local _, ns = ...
local L = ns.L

-- =============================================================================
-- Gz-knappen (v0.27): sig tillykke til en ven, der lige er steget i level
--   * Det venlige modstykke til prutten (Haan.lua). Når en ven dinger, får level-popuppen en
--     "Gz"-knap, og over level-nyheden på bande-baren bliver tiden til "Gz". Et klik sender
--     vennen en lille hilsen ("Mathias siger tillykke med level 31!") og en ding-lyd.
--   * Også med /wc4ever gz [ven] (uden navn: den ven, der dingede senest).
--   * Kun op til 15 minutter efter levelet, kun ét gz pr. level fra hver ven, og højst ét gz
--     hvert 10. sekund fra dig. Modtageren tager også højst ét hvert 5. sekund fra samme ven.
--   * Vil du ikke have gz-popups, så skriv /wc4ever gz fra: så kommer de kun som en linje i chatten.
--   * Alle gz tælles (givet og fået) og står i nyhederne og i bande-barens tooltip.
--
-- Besked:
--   XG;fra;til;level;nonce;tekst;tid
-- db.gz = { log = { { id, from, to, l, line, t } } }
-- Cooldown for dine egne afsendelser ligger i en lokal variabel (GetTime nulstilles ved genstart af pc'en,
-- så den må aldrig gemmes i db)
-- db.settings.gz = false: ingen lyd eller popup, når nogen siger tillykke til dig
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name

local Gz = {}
ns.Gz = Gz

Gz.WINDOW = 15 * 60       -- så længe efter levelet må man sige tillykke
Gz.COOLDOWN = 10          -- sekunder mellem dine gz
Gz.RECV_GAP = 5           -- modtageren: højst ét gz pr. ven så ofte
Gz.ICON = "Interface\\Icons\\Spell_Holy_SurgeOfLight"
local LOG_MAX = 300
local FRESH = 120         -- kun nye gz giver lyd, popup og chat

-- {F} siger tillykke, {T} er den, der dingede, {L} levelet. Ingen ejefald, så "dig" også passer.
local LINES = ns.LT({
    "{F} siger tillykke til {T} med level {L}!",
    "{F} klapper ad {T}. Level {L}!",
    "{F} rækker {T} en kold en for level {L}.",
    "{F} danser for {T}. Level {L}, sådan!",
    "{F} råber GZ til {T} så hele zonen kan høre det.",
    "{F} giver {T} en high five for level {L}.",
})
-- Max level fortjener lidt mere
local MAX_LINES = ns.LT({
    "{F} siger ENDELIG til {T}. Max level!",
    "{F} bukker for {T}. Max level, nu kan det rigtige spil begynde.",
})
Gz.LINES, Gz.MAX_LINES = LINES, MAX_LINES

local function DB()
    local db = WastedCoastDB
    db.gz = db.gz or {}
    db.gz.log = db.gz.log or {}
    db.gz.lastSent = nil   -- gammel version gemte GetTime-tid i db; den giver timelange ventetider efter genstart
    return db, db.gz
end
local lastSent   -- GetTime() for din seneste afsendelse, kun i denne session

local function ClassOf(friend)
    local best, lvl
    for _, c in pairs((WastedCoastDB.friends[friend] and WastedCoastDB.friends[friend].chars) or {}) do
        if c.class and (not lvl or (c.level or 0) > lvl) then best, lvl = c.class, c.level or 0 end
    end
    return best
end

local function Lines(level)
    return (tonumber(level) or 0) >= C.MAX_LEVEL and MAX_LINES or LINES
end

function Gz.Text(idx, from, to, level)
    local list = Lines(level)
    local line = list[idx] or list[1]
    from, to = from:gsub("%%", "%%%%"), to:gsub("%%", "%%%%")
    return (line:gsub("{F}", from):gsub("{T}", to):gsub("{L}", tostring(level or "?")))
end

-- =============================================================================
-- Hvem kan man sige tillykke til lige nu?
-- =============================================================================
-- Vennens seneste level, hvis vi så det ske (ikke gættet, ikke demo) inden for vinduet
function Gz.FreshDing(friend, now)
    now = now or time()
    local e = WastedCoastDB.levelAt and WastedCoastDB.levelAt[friend]
    if not e or e.g or e.d or not e.l or e.l < 2 or not e.t then return nil end
    if e.t <= now - Gz.WINDOW or e.t > now + 60 then return nil end
    return e
end

-- Den ven (ikke dig), der dingede senest inden for vinduet
function Gz.LatestDing(now)
    local db = WastedCoastDB
    local best, bestE
    for _, name in ipairs(ROSTER) do
        if name ~= db.me then
            local e = Gz.FreshDing(name, now)
            if e and (not bestE or e.t > bestE.t) then best, bestE = name, e end
        end
    end
    return best, bestE
end

local function Given(from, to, level)
    local _, g = DB()
    for _, e in ipairs(g.log) do
        if e.from == from and e.to == to and e.l == level then return true end
    end
    return false
end

-- Kan du sige tillykke til vennen nu? Returnerer ok, levelet, eller nil og en forklaring
function Gz.Can(friend)
    local db, g = DB()
    if not db.me then return nil, nil, L("Opret eller deltag først i en gruppe (|cffffd100/wc4ever gruppe|r).") end
    if not friend or not ROSTER_SET[friend] then return nil, nil, L("Hvem? Skriv fx |cffffd100/wc4ever gz nick|r.") end
    if friend == db.me then return nil, nil, L("Du kan ikke sige tillykke til dig selv. Men godt gået.") end
    local e = Gz.FreshDing(friend)
    if not e then return nil, nil, string.format(L("%s er ikke steget i level for nylig."), Name(friend)) end
    if Given(db.me, friend, e.l) then return nil, e, string.format(L("Du har allerede sagt tillykke til %s."), Name(friend)) end
    local wait = lastSent and (lastSent + Gz.COOLDOWN - GetTime()) or 0
    if wait > 0 then return nil, e, string.format(L("Rolig nu. Du kan sige tillykke igen om %d sek."), math.ceil(wait)) end
    return true, e
end

-- =============================================================================
-- Log og tal
-- =============================================================================
local function Announce(e)
    local db = WastedCoastDB
    if e.to == db.me then
        local text = Gz.Text(e.line, Name(e.from), L("dig"), e.l)
        if db.settings.gz == false then
            Print("|cff66d36a" .. text .. "|r")
            return
        end
        ns.Toast({ kind = "levelup", head = "GZ", title = string.format(L("%s siger tillykke!"), Name(e.from)),
                   text = text, icon = Gz.ICON, class = ClassOf(e.from), friend = e.from, sound = "levelup", dur = 5 })
        Print("|cff66d36a" .. text .. "|r")
    elseif e.from ~= db.me and db.settings.announce then
        Print("|cff66d36a" .. Gz.Text(e.line, Name(e.from), Name(e.to), e.l) .. "|r")
    end
end

-- Tilføjer et gz til loggen. Returnerer true, hvis det var nyt.
function Gz.Record(e, quiet)
    local _, g = DB()
    if not e or not e.id or not ROSTER_SET[e.from] or not ROSTER_SET[e.to] or e.from == e.to then return false end
    for _, old in ipairs(g.log) do
        if old.id == e.id then return false end
    end
    g.log[#g.log + 1] = e
    table.sort(g.log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #g.log > LOG_MAX do table.remove(g.log, 1) end
    if not quiet and not e.demo and math.abs(time() - (e.t or 0)) < FRESH then Announce(e) end
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Antal gz givet og fået pr. ven siden et tidspunkt (nil = altid)
function Gz.Counts(since, noDemo)
    local _, g = DB()
    local sent, recv = {}, {}
    for _, e in ipairs(g.log) do
        if (not since or (e.t or 0) >= since) and not (noDemo and e.demo) and ROSTER_SET[e.from] and ROSTER_SET[e.to] then
            sent[e.from] = (sent[e.from] or 0) + 1
            recv[e.to] = (recv[e.to] or 0) + 1
        end
    end
    return sent, recv
end

local function Serialize(e)
    return table.concat({ "XG", e.from, e.to, tostring(e.l), tostring(e.nonce or ""), tostring(e.line or 1),
                          tostring(e.t or 0) }, ";")
end

-- =============================================================================
-- Send et gz
-- =============================================================================
function ns.GzSend(friend)
    local ok, ding, why = Gz.Can(friend)
    if not ok then
        if why then Print(why) end
        return false
    end
    local db, g = DB()
    lastSent = GetTime()
    local nonce = tostring(math.random(100000, 999999))
    local e = { id = db.me .. "-" .. nonce, from = db.me, to = friend, l = ding.l, nonce = nonce,
                line = math.random(#Lines(ding.l)), t = time() }
    C.Send(Serialize(e), true)
    Gz.Record(e, true)
    Print("|cff66d36a" .. string.format(L("Du sagde tillykke til %s."), Name(friend)) .. "|r")
    return true
end

-- Knappen til level-popuppen (nil, hvis det er dig selv)
function ns.GzAction(friend)
    local db = WastedCoastDB
    if not friend or friend == db.me then return nil end
    return { label = "Gz", done = "Gz!", tip = string.format(L("Sig tillykke til %s."), Name(friend)),
             onClick = function() return ns.GzSend(friend) end }
end

-- =============================================================================
-- Beskeder og synk
-- =============================================================================
local lastFrom = {}

function ns.HandleGzMessage(t)
    local db = DB()
    local from, to, level, nonce, line, at = t[2], t[3], tonumber(t[4]), t[5], tonumber(t[6]), tonumber(t[7])
    if not ROSTER_SET[from] or not ROSTER_SET[to] or from == db.me or from == to then return end
    if not level or level < 2 or level > 200 or not nonce or nonce == "" or not at then return end
    level = math.floor(level)
    if not line or not Lines(level)[line] then line = 1 end
    local e = { id = from .. "-" .. nonce, from = from, to = to, l = level, nonce = nonce, line = line,
                t = math.min(at, time()) }
    -- Spam-værn hos modtageren: ét gz pr. level fra samme ven, og ikke for tæt
    local fresh = math.abs(time() - e.t) < FRESH
    if fresh and to == db.me then
        if Given(from, to, level) then return end
        if lastFrom[from] and GetTime() - lastFrom[from] < Gz.RECV_GAP then return end
        lastFrom[from] = GetTime()
    end
    Gz.Record(e)
end

-- Ved synk: de seneste gz, du har givet (dubletter filtreres fra hos modtageren)
function Gz.SendLog()
    local db, g = DB()
    local sent = 0
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if not e.demo and e.nonce and e.from == db.me and time() - (e.t or 0) < 14 * 86400 then
            C.Send(Serialize(e))
            sent = sent + 1
            if sent >= 15 then break end
        end
    end
end

-- =============================================================================
-- Demo, nulstilling og kommandoer
-- =============================================================================
function Gz.MakeDemo()
    local db = DB()
    local others = {}
    for _, name in ipairs(ROSTER) do if name ~= db.me then others[#others + 1] = name end end
    if #others < 2 then return end
    local now = time()
    Gz.Record({ id = "demo-G-1", from = others[2], to = others[1], l = 30, line = 1, t = now - 3 * 3600, demo = true })
end

function Gz.ClearDemo()
    local _, g = DB()
    for i = #g.log, 1, -1 do
        if g.log[i].demo then table.remove(g.log, i) end
    end
end

function Gz.Reset()
    local _, g = DB()
    wipe(g.log)
    lastSent = nil
end

local function FindFriend(arg)
    arg = (arg or ""):lower()
    if arg == "" then return nil end
    for _, name in ipairs(ROSTER) do
        if Name(name):lower() == arg then return name end
    end
    for _, name in ipairs(ROSTER) do
        if Name(name):lower():sub(1, #arg) == arg then return name end
    end
end

-- Returnerer true, hvis kommandoen blev klaret her
function ns.GzSlash(cmd, arg)
    if cmd ~= "gz" and cmd ~= "grats" and cmd ~= "tillykke" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "fra" or arg == "off" or arg == "til" or arg == "on" then
        if arg == "til" or arg == "on" then db.settings.gz = nil else db.settings.gz = false end
        Print(L("Gz-popups: ") .. ((db.settings.gz ~= false) and L("til") or L("fra")))
    elseif arg == "test" then
        -- Kun hos dig selv: intet sendes
        ns.Toast({ kind = "levelup", head = "GZ", title = string.format(L("%s siger tillykke!"), Name(db.me) or "?"),
                   text = Gz.Text(math.random(#LINES), Name(db.me) or "?", L("dig"), 31), icon = Gz.ICON,
                   sound = "levelup", dur = 5, force = true })
    elseif arg == "" then
        local friend = Gz.LatestDing()
        if friend then
            ns.GzSend(friend)
        else
            Print(L("Ingen af vennerne er steget i level inden for de sidste 15 minutter."))
        end
    else
        local name = FindFriend(arg)
        if name then ns.GzSend(name) else Print(L("Hvem? Skriv fx |cffffd100/wc4ever gz nick|r.")) end
    end
    return true
end
