local _, ns = ...
local L = ns.L

-- =============================================================================
-- Hån-knappen (v0.24): prut af en ven, der lige er død
--   * Når en ven dør, får dødsannoncen en lille "Prut"-knap. Et klik sender vennen en
--     pruttelyd og en lille besked ("Mathias prutter af dig."). Du hører selv lyden med.
--   * Det samme kan gøres fra bande-baren og nyhedspanelet (klik på dødsfaldet) og med
--     /wc4ever prut [ven] (uden navn: den ven, der døde senest).
--   * Kun op til 15 minutter efter dødsfaldet, kun én prut pr. dødsfald fra hver ven, og
--     højst én prut hvert 20. sekund fra dig. Modtageren tager også højst én prut hvert
--     10. sekund fra samme ven (hvis afsenderens addon er pillet ved).
--   * Står vennen ved siden af dig, laver din karakter også spillets egen /fart på vennen.
--   * Lyden er en af tre pruttere i sounds\ (prut1-3.ogg). Vil du have din egen, skriv
--     haan = { "minlyd.ogg" } i Sounds.lua. Nye lydfiler kræver, at spillet genstartes.
--   * Vil du ikke have prutter, slå "Prutter mod dig" fra i indstillingerne (eller
--     /wc4ever prut fra): så kommer der ingen lyd og ingen popup, kun en linje i chatten.
--   * Alle prutter tælles (flest givet og flest fået), står i nyhederne og i sladderen.
--   * v0.30.1: prut-nægteren. Slår man prutter fra, er man en frygtsom prut-nægter og får i
--     stedet en straffeprut hvert 5. minut, mens man er logget ind (lyd og popup). Vennerne
--     kan se det: en linje i nyhederne, når man bliver prut-nægter, og i bande-barens tooltip.
--
-- Besked:
--   XH;fra;til;dødsfald-id;nonce;tekst;lyd;tid
-- db.haan = { log = { { id, from, to, death, line, snd, t } }, lastSent = GetTime-tid (kun i sessionen) }
-- db.settings.haan = false: ingen lyd eller popup, når nogen prutter af dig (men en straffeprut hvert 5. min)
--   XR;ven;1|0;siden;straffeprutter   (prut-nægter-status, sendes ved skift og ved synk)
-- db.haan.refusers = { ven -> { on = true|nil, since, n } }, db.haan.penalty = { n, last }
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name
local Plain = C.GAME.Plain

local Haan = {}
ns.Haan = Haan

Haan.WINDOW = 15 * 60      -- så længe efter dødsfaldet må man prutte
Haan.COOLDOWN = 20         -- sekunder mellem dine prutter
Haan.RECV_GAP = 10         -- modtageren: højst én prut pr. ven så ofte
Haan.SOUNDS = 3            -- prut1.ogg ... prut3.ogg
Haan.ICON = "Interface\\Icons\\Spell_Nature_Cyclone"
local SOUND_DIR = "Interface\\AddOns\\WastedCoast\\sounds\\"
Haan.PENALTY = 5 * 60      -- prut-nægtere: en straffeprut så ofte
local LOG_MAX = 300
local FRESH = 120          -- kun nye prutter giver lyd, popup og chat

-- {F} er den, der prutter, {T} den døde. Ingen ejefald, så "dig" også passer.
local LINES = ns.LT({
    "{F} prutter af {T}.",
    "{F} sender {T} en varm hilsen bagfra.",
    "{F} sætter sig på gravstenen og prutter efter {T}.",
    "{F} lader en lille en gå i retning af {T}.",
    "{F} hilser {T} med en lang, faldende prut.",
    "{F} prutter en sørgemarch for {T}.",
    "{F} prutter tre gange for {T}. Det er en gammel tradition.",
    "{F} holder et minuts prutten for {T}.",
})
Haan.LINES = LINES

local function DB()
    local db = WastedCoastDB
    db.haan = db.haan or {}
    db.haan.log = db.haan.log or {}
    db.haan.refusers = db.haan.refusers or {}
    return db, db.haan
end

-- Vennens klasse: den karakter med højest level
local function ClassOf(friend)
    local best, lvl
    for _, c in pairs((WastedCoastDB.friends[friend] and WastedCoastDB.friends[friend].chars) or {}) do
        if c.class and (not lvl or (c.level or 0) > lvl) then best, lvl = c.class, c.level or 0 end
    end
    return best
end

local function Clean(s)
    return (tostring(s or ""):gsub("[;|]", ","))
end

function Haan.Text(idx, from, to)
    local line = LINES[idx] or LINES[1]
    -- Navnene kan indeholde %, som gsub ellers læser som et mønster
    from, to = from:gsub("%%", "%%%%"), to:gsub("%%", "%%%%")
    return (line:gsub("{F}", from):gsub("{T}", to))
end

-- =============================================================================
-- Hvem kan man prutte af lige nu?
-- =============================================================================
-- Vennens seneste dødsfald, hvis det er inden for vinduet
function Haan.FreshDeath(friend, now)
    now = now or time()
    local best
    for _, ev in ipairs(WastedCoastDB.events or {}) do
        if C.EventFriend(ev) == friend and ev.id and not ev.demo and (ev.time or 0) > now - Haan.WINDOW
            and (ev.time or 0) <= now + 60 and (not best or ev.time > best.time) then
            best = ev
        end
    end
    return best
end

-- Den ven (ikke dig), der døde senest inden for vinduet
function Haan.LatestDead(now)
    local db = WastedCoastDB
    local best, bestEv
    for _, name in ipairs(ROSTER) do
        if name ~= db.me then
            local ev = Haan.FreshDeath(name, now)
            if ev and (not bestEv or ev.time > bestEv.time) then best, bestEv = name, ev end
        end
    end
    return best, bestEv
end

local function Taunted(from, deathId)
    local _, h = DB()
    for _, e in ipairs(h.log) do
        if e.from == from and e.death == deathId then return true end
    end
    return false
end

-- Kan du prutte af vennen nu? Returnerer ok, dødsfaldet, eller nil og en forklaring
function Haan.Can(friend)
    local db, h = DB()
    if not db.me then return nil, nil, L("Opret eller deltag først i en gruppe (|cffffd100/wc4ever gruppe|r).") end
    if not friend or not ROSTER_SET[friend] then return nil, nil, L("Hvem? Skriv fx |cffffd100/wc4ever prut nick|r.") end
    if friend == db.me then return nil, nil, L("Du kan ikke prutte af dig selv. Det er bare at prutte.") end
    local ev = Haan.FreshDeath(friend)
    if not ev then return nil, nil, string.format(L("%s er ikke død for nylig. Prutter er kun til de døde."), Name(friend)) end
    if Taunted(db.me, ev.id) then return nil, ev, string.format(L("Du har allerede pruttet af %s for det dødsfald."), Name(friend)) end
    local wait = h.lastSent and (h.lastSent + Haan.COOLDOWN - GetTime()) or 0
    if wait > 0 then return nil, ev, string.format(L("Rolig nu. Du kan prutte igen om %d sek."), math.ceil(wait)) end
    return true, ev
end

-- =============================================================================
-- Lyd
-- =============================================================================
local warned = false
function Haan.Play(snd, from)
    local db = WastedCoastDB
    if not db.settings.sound then return false end
    -- Egen lyd fra Sounds.lua vinder
    if type(ns.sounds) == "table" and type(ns.sounds.haan) == "table" and #ns.sounds.haan > 0
        or (type(ns.sounds) == "table" and type(ns.sounds.friends) == "table" and from
            and type(ns.sounds.friends[from] or ns.sounds.friends[Name(from)]) == "table"
            and (ns.sounds.friends[from] or ns.sounds.friends[Name(from)]).haan) then
        local ok = C.PlayEventSound("haan", from)
        if ok then return true end
    end
    snd = tonumber(snd)
    if not snd or snd < 1 or snd > Haan.SOUNDS then snd = math.random(Haan.SOUNDS) end
    local ok, willPlay = pcall(PlaySoundFile, SOUND_DIR .. "prut" .. math.floor(snd) .. ".ogg", "Master")
    if ok and willPlay then return true end
    if not warned then
        warned = true
        Print(L("Pruttelyden kunne ikke afspilles. Har du genstartet spillet helt efter opdateringen? /reload er ikke nok til nye lydfiler."))
    end
    return false
end

-- =============================================================================
-- Log og tal
-- =============================================================================
local function Announce(e)
    local db = WastedCoastDB
    if e.to == db.me then
        local text = Haan.Text(e.line, Name(e.from), L("dig"))
        if db.settings.haan == false then
            Print("|cffb08850" .. text .. "|r " .. L("(prutter er slået fra)"))
            return
        end
        Haan.Play(e.snd, e.from)
        ns.Toast({ kind = "haan", head = L("PRUT"), title = string.format(L("%s prutter af dig!"), Name(e.from)),
                   text = text, icon = Haan.ICON, class = ClassOf(e.from), friend = e.from, dur = 5 })
        Print("|cffd9a05b" .. text .. "|r")
    elseif e.from ~= db.me and db.settings.announce then
        Print("|cffd9a05b" .. Haan.Text(e.line, Name(e.from), Name(e.to)) .. "|r")
    end
end

-- Tilføjer en prut til loggen. Returnerer true, hvis den var ny.
function Haan.Record(e, quiet)
    local _, h = DB()
    if not e or not e.id or not ROSTER_SET[e.from] or not ROSTER_SET[e.to] or e.from == e.to then return false end
    for _, old in ipairs(h.log) do
        if old.id == e.id then return false end
    end
    h.log[#h.log + 1] = e
    table.sort(h.log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #h.log > LOG_MAX do table.remove(h.log, 1) end
    if not quiet and not e.demo and math.abs(time() - (e.t or 0)) < FRESH then Announce(e) end
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Antal prutter givet og fået pr. ven siden et tidspunkt (nil = altid)
function Haan.Counts(since, noDemo)
    local _, h = DB()
    local sent, recv = {}, {}
    for _, e in ipairs(h.log) do
        if (not since or (e.t or 0) >= since) and not (noDemo and e.demo) and ROSTER_SET[e.from] and ROSTER_SET[e.to] then
            sent[e.from] = (sent[e.from] or 0) + 1
            recv[e.to] = (recv[e.to] or 0) + 1
        end
    end
    return sent, recv
end

local function Top(t)
    local best, n
    for name, v in pairs(t) do
        if not n or v > n or (v == n and Name(name) < Name(best)) then best, n = name, v end
    end
    return best, n or 0
end

function Haan.Summary()
    local sent, recv = Haan.Counts()
    local s, sn = Top(sent)
    local r, rn = Top(recv)
    if not s then return L("Ingen prutter endnu. Nogen må dø først.") end
    return string.format(L("Flest prutter givet: %s (%d). Flest fået: %s (%d)."), Name(s), sn, Name(r), rn)
end

local function Serialize(e)
    return table.concat({ "XH", e.from, e.to, Clean(e.death), tostring(e.nonce or ""), tostring(e.line or 1),
                          tostring(e.snd or 1), tostring(e.t or 0) }, ";")
end

-- =============================================================================
-- Send en prut
-- =============================================================================
local function FriendUnit(friend)
    if UnitExists and UnitExists("target") and C.FriendOfChar(Plain(UnitName("target"))) == friend then return "target" end
    local prefix, n = "party", 4
    if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local u = prefix .. i
        if UnitExists and UnitExists(u) and C.FriendOfChar(Plain(UnitName(u))) == friend then return u end
    end
    return nil
end

function ns.HaanSend(friend)
    local ok, ev, why = Haan.Can(friend)
    if not ok then
        if why then Print(why) end
        return false
    end
    local db, h = DB()
    h.lastSent = GetTime()
    local nonce = tostring(math.random(100000, 999999))
    local e = { id = db.me .. "-" .. nonce, from = db.me, to = friend, death = ev.id, nonce = nonce,
                line = math.random(#LINES), snd = math.random(Haan.SOUNDS), t = time() }
    C.Send(Serialize(e), true)
    Haan.Record(e, true)
    Haan.Play(e.snd, db.me)
    -- Spillets egen /fart, hvis vennen står lige ved siden af
    local unit = FriendUnit(friend)
    if unit and DoEmote then pcall(DoEmote, "FART", unit) end
    Print("|cffd9a05b" .. string.format(L("Du pruttede af %s."), Name(friend)) .. "|r")
    return true
end

-- =============================================================================
-- Beskeder og synk
-- =============================================================================
local lastFrom = {}

function ns.HandleHaanMessage(t)
    local db = DB()
    local from, to, death, nonce, line, snd, at = t[2], t[3], t[4], t[5], tonumber(t[6]), tonumber(t[7]), tonumber(t[8])
    if not ROSTER_SET[from] or not ROSTER_SET[to] or from == db.me or from == to then return end
    if not death or death == "" or not nonce or nonce == "" or not at then return end
    if not line or not LINES[line] then line = 1 end
    local e = { id = from .. "-" .. nonce, from = from, to = to, death = death:sub(1, 60), nonce = nonce,
                line = line, snd = snd, t = math.min(at, time()) }
    -- Spam-værn hos modtageren: én prut pr. dødsfald fra samme ven, og ikke for tæt
    local fresh = math.abs(time() - e.t) < FRESH
    if fresh and to == db.me then
        if Taunted(from, e.death) then return end
        if lastFrom[from] and GetTime() - lastFrom[from] < Haan.RECV_GAP then return end
        lastFrom[from] = GetTime()
    end
    Haan.Record(e)
end

-- =============================================================================
-- Prut-nægteren (v0.30.1): slår man prutter fra, får man en straffeprut hvert 5. minut
-- =============================================================================
local PENALTY_LINES = ns.LT({
    "Frygtsomme prut-nægtere får deres prut alligevel. Bare oftere.",
    "Du nægtede at modtage prutter. Universet prutter nu af dig i stedet.",
    "Straffeprut nr. {N}. Slå prutter til igen, så stopper det.",
    "Prut-nægtere prutter selv. Det er loven.",
    "En lille påmindelse om, at du gemmer dig for prutter.",
    "Du kan løbe fra vennernes prutter, men ikke fra dine egne.",
})
Haan.PENALTY_LINES = PENALTY_LINES

function Haan.IsRefuser(friend)
    local db, h = DB()
    if friend == db.me then return db.settings.haan == false end
    local r = h.refusers[friend]
    return (r and r.on) and r or nil
end

local function SendStatus()
    local db, h = DB()
    if not db.me then return end
    local p = h.penalty or {}
    C.Send(table.concat({ "XR", db.me, (db.settings.haan == false) and "1" or "0", tostring(p.since or 0), tostring(p.n or 0) }, ";"))
end
Haan.SendStatus = SendStatus

-- Slår prutter mod dig til (true) eller fra (false)
function ns.HaanSetReceive(on)
    local db, h = DB()
    local was = db.settings.haan ~= false
    if on then db.settings.haan = nil else db.settings.haan = false end
    if was and not on then
        h.penalty = { since = time(), n = 0, last = GetTime() }
        Print("|cffd9a05b" .. L("Prutter mod dig er slået fra. Frygtsomme prut-nægtere får en straffeprut hvert 5. minut i stedet. Velbekomme.") .. "|r")
    elseif on and not was then
        local n = h.penalty and h.penalty.n or 0
        h.penalty = nil
        Print("|cffd9a05b" .. string.format(L("Prutter mod dig er slået til igen. Du slap med %d straffeprutter."), n) .. "|r")
    end
    if was ~= (on and true or false) then SendStatus() end
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
end

-- Kaldes hvert minut: er det tid til en straffeprut?
function Haan.PenaltyTick()
    local db, h = DB()
    if db.settings.haan ~= false or not db.me then return false end
    h.penalty = h.penalty or { since = time(), n = 0 }
    local p = h.penalty
    -- Ved login starter uret forfra (GetTime nulstilles ikke mellem sessioner, men det er ligegyldigt her)
    if not p.last or p.last > GetTime() then p.last = GetTime() return false end
    if GetTime() - p.last < Haan.PENALTY then return false end
    p.last = GetTime()
    p.n = (p.n or 0) + 1
    Haan.Play(math.random(Haan.SOUNDS), db.me)
    local text = PENALTY_LINES[math.random(#PENALTY_LINES)]:gsub("{N}", tostring(p.n))
    ns.Toast({ kind = "haan", head = L("STRAFFEPRUT"), title = L("Frygtsom prut-nægter"), text = text,
               icon = Haan.ICON, dur = 5, force = true })
    Print("|cffd9a05b" .. L("Straffeprut!") .. "|r " .. text)
    -- Tælleren sendes med jævne mellemrum, ikke for hver prut
    if p.n % 3 == 1 then SendStatus() end
    return true
end

local function OnStatus(t)
    local db, h = DB()
    local friend, on, since, n = t[2], t[3], tonumber(t[4]), tonumber(t[5])
    if not ROSTER_SET[friend] or friend == db.me or (on ~= "1" and on ~= "0") then return end
    since = since and math.min(since, time()) or time()
    local r = h.refusers[friend]
    if on == "1" then
        local fresh = not (r and r.on)
        h.refusers[friend] = { on = true, since = (r and r.on and r.since) or since, n = math.max(n or 0, (r and r.on and r.n) or 0) }
        if fresh and db.settings.announce and math.abs(time() - since) < FRESH then
            Print("|cffd9a05b" .. string.format(L("%s har slået prutter fra og er nu en frygtsom prut-nægter. Straffeprut hvert 5. minut."), Name(friend)) .. "|r")
        end
    elseif r then
        h.refusers[friend] = { since = r.since, n = r.n, off = time() }
    end
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    if ns.RefreshUI then ns.RefreshUI() end
end
ns.HandleHaanStatus = OnStatus

-- Ved synk: de seneste prutter, du har givet (dubletter filtreres fra hos modtageren)
function Haan.SendLog()
    local db, h = DB()
    local sent = 0
    for i = #h.log, 1, -1 do
        local e = h.log[i]
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
function Haan.MakeDemo()
    local db = DB()
    local others = {}
    for _, name in ipairs(ROSTER) do if name ~= db.me then others[#others + 1] = name end end
    if #others < 2 then return end
    local now = time()
    Haan.Record({ id = "demo-H-1", from = others[1], to = others[2], death = "demo", line = 2, snd = 1, t = now - 2 * 3600, demo = true })
    Haan.Record({ id = "demo-H-2", from = db.me or others[2], to = others[1], death = "demo", line = 1, snd = 2, t = now - 5 * 3600, demo = true })
end

function Haan.ClearDemo()
    local _, h = DB()
    for i = #h.log, 1, -1 do
        if h.log[i].demo then table.remove(h.log, i) end
    end
    for f, r in pairs(h.refusers) do if r.demo then h.refusers[f] = nil end end
end

function Haan.Reset()
    local _, h = DB()
    wipe(h.log)
    wipe(h.refusers)
    h.lastSent = nil
    h.penalty = nil
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
function ns.HaanSlash(cmd, arg)
    if cmd ~= "prut" and cmd ~= "fart" and cmd ~= "haan" and cmd ~= "hån" and cmd ~= "taunt" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "test" then
        -- Kun hos dig selv: intet sendes
        local snd = math.random(Haan.SOUNDS)
        if not Haan.Play(snd, db.me) and not db.settings.sound then Print(L("Lyden er slået fra (|cffffd100/wc4ever sound|r).")) end
        ns.Toast({ kind = "haan", head = L("PRUT"), title = string.format(L("%s prutter af dig!"), Name(db.me) or "?"),
                   text = Haan.Text(math.random(#LINES), Name(db.me) or "?", L("dig")), icon = Haan.ICON, dur = 5, force = true })
    elseif arg == "fra" or arg == "off" or arg == "til" or arg == "on" then
        ns.HaanSetReceive(arg == "til" or arg == "on")
        Print(L("Prutter mod dig: ") .. ((db.settings.haan ~= false) and L("til") or L("fra")))
    elseif arg == "stats" or arg == "tal" then
        Print(Haan.Summary())
    elseif arg == "" then
        local friend = Haan.LatestDead()
        if friend then
            ns.HaanSend(friend)
        else
            Print(L("Ingen af vennerne er død inden for de sidste 15 minutter. Vent lidt, det sker snart."))
            Print(Haan.Summary())
        end
    else
        local name = FindFriend(arg)
        if name then ns.HaanSend(name) else Print(L("Hvem? Skriv fx |cffffd100/wc4ever prut nick|r.")) end
    end
    return true
end

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if not WastedCoastDB then return end
    local _, h = DB()
    if h.penalty then h.penalty.last = GetTime() end
    C_Timer.NewTicker(60, Haan.PenaltyTick)
end)
