local _, ns = ...
local L = ns.L

-- =============================================================================
-- Hjemmesko-alarmen (v0.28): en ven, der står AFK i en by, falder i søvn i hjemmeskoene
--   * Står du AFK i en by (eller på en kro, alt med "rested"), får vennerne besked. Efter
--     20 minutter får dit ikon på bande-baren et sovende "zZz", og tooltippen fortæller, hvor
--     længe du har sovet, og hvor.
--   * Et klik på en sovende vens ikon (eller /wc4ever væk [ven]) prikker til vennen: vennen får
--     en vækkelyd (ready check-lyden, eller din egen "vaek" fra Sounds.lua), en popup og en
--     linje i chatten, og spillets ikon blinker på proceslinjen. Uden navn: den, der har sovet længst.
--   * Højst én prik hvert 30. sekund fra dig og én pr. minut til samme ven. Modtageren tager
--     også højst én prik hvert 30. sekund fra samme ven.
--   * Vil du ikke vækkes, så slå "Vækkelyd" fra i indstillingerne (eller /wc4ever væk fra):
--     så kommer der ingen lyd, popup eller blink, kun en linje i chatten.
--   * Når du kommer tilbage, får du at vide, hvem der prikkede til dig, mens du sov.
--   * Prikkene tælles og står i nyhederne og i bande-barens tooltip.
--
-- Beskeder:
--   XZ;ven;1;sekunder;zone   du står AFK i en by (sendes ved start og hvert 5. minut)
--   XZ;ven;0                 du er vågen igen
--   XV;fra;til;nonce;tekst;tid   en prik
-- Sekunderne er, hvor længe du har været AFK, så forskellige ure hos vennerne ikke betyder noget.
-- db.hjemmesko = { log = { { id, from, to, nonce, line, t } } }
-- db.settings.hjemmesko = false: ingen lyd, popup eller blink, når nogen prikker til dig
-- AFK-tilstanden (din egen og vennernes) ligger kun i sessionen.
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name
local Plain = C.GAME.Plain

local H = {}
ns.Hjemmesko = H

H.SLEEP = 20 * 60          -- så længe skal man stå AFK i byen, før man sover
H.RESEND = 5 * 60          -- send tilstanden igen så tit, mens man er AFK
H.STALE = 11 * 60          -- en vens AFK-tilstand glemmes, hvis den ikke er sendt igen
H.COOLDOWN = 30            -- sekunder mellem dine prik
H.PER_FRIEND = 60          -- sekunder mellem prik til samme ven
H.RECV_GAP = 30            -- modtageren: højst én prik pr. ven så ofte
H.ICON = "Interface\\Icons\\Spell_Nature_Sleep"
local LOG_MAX = 300
local FRESH = 120          -- kun nye prik giver lyd, popup og chat

-- {F} prikker, {T} sover. Ingen ejefald, så "dig" også passer.
local LINES = ns.LT({
    "{F} prikker {T} på skulderen. VÅGN OP!",
    "{F} hælder koldt vand i hjemmeskoene på {T}.",
    "{F} råber VÆK! lige ind i øret på {T}.",
    "{F} kilder {T} under fødderne.",
    "{F} stiller et vækkeur ved siden af {T} og går.",
    "{F} trækker hjemmeskoene af {T}. Op med dig!",
    "{F} spiller trompet for {T}. Morgenappel!",
})
H.LINES = LINES

-- Din egen tilstand: since = time(), da du blev AFK i byen. Vennernes: afk[ven] = { since, zone, seen }
local mine = { since = nil, zone = nil, sentAt = 0, poked = {} }
local afk = {}
H.mine, H.afk = mine, afk

local function DB()
    local db = WastedCoastDB
    db.hjemmesko = db.hjemmesko or {}
    db.hjemmesko.log = db.hjemmesko.log or {}
    return db, db.hjemmesko
end

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

function H.Text(idx, from, to)
    local line = LINES[idx] or LINES[1]
    from, to = from:gsub("%%", "%%%%"), to:gsub("%%", "%%%%")
    return (line:gsub("{F}", from):gsub("{T}", to))
end

-- =============================================================================
-- Hvem sover?
-- =============================================================================
-- Hvornår vennen blev AFK i byen (og zonen), eller nil
function H.AfkSince(friend, now)
    now = now or time()
    local db = WastedCoastDB
    if friend == db.me then return mine.since, mine.zone end
    local st = afk[friend]
    if not st or now - (st.seen or 0) > H.STALE then return nil end
    if not st.demo and C.IsOnline and not C.IsOnline(friend) then return nil end
    return st.since, st.zone
end

-- Sover vennen i hjemmeskoene? Giver minutter og zone
function H.Asleep(friend, now)
    now = now or time()
    local since, zone = H.AfkSince(friend, now)
    if not since or now - since < H.SLEEP then return nil end
    return math.floor((now - since) / 60), zone
end

-- Den ven (ikke dig), der har sovet længst
function H.Sleepiest(now)
    local db = WastedCoastDB
    local best, bestMin
    for _, name in ipairs(ROSTER) do
        if name ~= db.me then
            local m = H.Asleep(name, now)
            if m and (not bestMin or m > bestMin) then best, bestMin = name, m end
        end
    end
    return best, bestMin
end

local lastTo = {}

-- Kan du prikke til vennen nu? Returnerer ok eller nil og en forklaring
function H.Can(friend)
    local db, h = DB()
    if not db.me then return nil, L("Opret eller deltag først i en gruppe (|cffffd100/wc4ever gruppe|r).") end
    if not friend or not ROSTER_SET[friend] then return nil, L("Hvem? Skriv fx |cffffd100/wc4ever væk nick|r.") end
    if friend == db.me then return nil, L("Du kan ikke vække dig selv. Prøv med en kop kaffe.") end
    if not H.Asleep(friend) then return nil, string.format(L("%s sover ikke. Kun venner, der har stået AFK i en by i over 20 minutter, kan vækkes."), Name(friend)) end
    local wait = h.lastSent and (h.lastSent + H.COOLDOWN - GetTime()) or 0
    if lastTo[friend] then wait = math.max(wait, lastTo[friend] + H.PER_FRIEND - GetTime()) end
    if wait > 0 then return nil, string.format(L("Rolig nu. Du kan prikke igen om %d sek."), math.ceil(wait)) end
    return true
end

-- =============================================================================
-- Din egen AFK: tjekkes hvert 10. sekund og når dine flag skifter
-- =============================================================================
local function IsAfkInTown()
    local ok, isAfk = pcall(function() return UnitIsAFK and Plain(UnitIsAFK("player")) end)
    if not ok or not isAfk then return false end
    local okR, resting = pcall(function() return IsResting and Plain(IsResting()) end)
    if not okR or not resting then return false end
    local okI, inInst = pcall(function() return IsInInstance and Plain(IsInInstance()) end)
    if okI and inInst then return false end
    return true
end

local function ZoneNow()
    local ok, z = pcall(function() return GetZoneText and Plain(GetZoneText()) end)
    return (ok and type(z) == "string") and Clean(z):sub(1, 40) or ""
end

local function SendState()
    local db = WastedCoastDB
    if not db or not db.me then return end
    if mine.since then
        C.Send(table.concat({ "XZ", db.me, "1", tostring(math.max(0, time() - mine.since)), mine.zone or "" }, ";"))
    else
        C.Send(table.concat({ "XZ", db.me, "0" }, ";"))
    end
    mine.sentAt = time()
end
H.SendState = SendState

local function WakeUpReport()
    if #mine.poked == 0 then return end
    local names, seen = {}, {}
    for _, f in ipairs(mine.poked) do
        if not seen[f] then seen[f] = true names[#names + 1] = Name(f) end
    end
    Print("|cff8fb8ff" .. string.format(L("Godmorgen! Mens du sov, prikkede %s til dig."), table.concat(names, ", ")) .. "|r")
    wipe(mine.poked)
end

function H.Check()
    local db = WastedCoastDB
    if not db or not db.me then return end
    local now = time()
    if IsAfkInTown() then
        if not mine.since then
            mine.since, mine.zone = now, ZoneNow()
            wipe(mine.poked)
            SendState()
            if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
        elseif now - (mine.sentAt or 0) >= H.RESEND then
            SendState()
        end
    elseif mine.since then
        mine.since, mine.zone = nil, nil
        SendState()
        WakeUpReport()
        if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    end
end

-- Ved synk: kun hvis du står AFK lige nu (vågen er standard)
function H.SendSync()
    if mine.since then SendState() end
end

-- =============================================================================
-- Log og tal
-- =============================================================================
local function Announce(e)
    local db = WastedCoastDB
    if e.to == db.me then
        local text = H.Text(e.line, Name(e.from), L("dig"))
        if mine.since then mine.poked[#mine.poked + 1] = e.from end
        if db.settings.hjemmesko == false then
            Print("|cff8fb8ff" .. text .. "|r " .. L("(vækkelyden er slået fra)"))
            return
        end
        C.PlayEventSound("vaek", e.from)
        if FlashClientIcon then pcall(FlashClientIcon) end
        ns.Toast({ kind = "hjemmesko", head = L("VÅGN OP"), title = string.format(L("%s prikker til dig!"), Name(e.from)),
                   text = text, icon = H.ICON, class = ClassOf(e.from), friend = e.from, dur = 6 })
        Print("|cff8fb8ff" .. text .. "|r")
    elseif e.from ~= db.me and db.settings.announce then
        Print("|cff8fb8ff" .. H.Text(e.line, Name(e.from), Name(e.to)) .. "|r")
    end
end

-- Tilføjer en prik til loggen. Returnerer true, hvis den var ny.
function H.Record(e, quiet)
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

-- Antal prik givet og fået pr. ven siden et tidspunkt (nil = altid)
function H.Counts(since, noDemo)
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

local function Serialize(e)
    return table.concat({ "XV", e.from, e.to, tostring(e.nonce or ""), tostring(e.line or 1), tostring(e.t or 0) }, ";")
end

-- =============================================================================
-- Prik til en ven
-- =============================================================================
function ns.HjemmeskoWake(friend)
    local ok, why = H.Can(friend)
    if not ok then
        if why then Print(why) end
        return false
    end
    local db, h = DB()
    h.lastSent = GetTime()
    lastTo[friend] = GetTime()
    local nonce = tostring(math.random(100000, 999999))
    local e = { id = db.me .. "-" .. nonce, from = db.me, to = friend, nonce = nonce, line = math.random(#LINES), t = time() }
    C.Send(Serialize(e), true)
    H.Record(e, true)
    Print("|cff8fb8ff" .. string.format(L("Du prikkede til %s. Forhåbentlig vågner vennen."), Name(friend)) .. "|r")
    return true
end

-- =============================================================================
-- Beskeder
-- =============================================================================
local lastFrom = {}

function ns.HandleHjemmeskoMessage(kind, t)
    local db = DB()
    if kind == "XZ" then
        local friend, state = t[2], t[3]
        if not ROSTER_SET[friend] or friend == db.me then return end
        if state == "0" then
            if afk[friend] then
                afk[friend] = nil
                if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
            end
        elseif state == "1" then
            local secs = tonumber(t[4])
            if not secs or secs < 0 or secs > 7 * 86400 then return end
            local now = time()
            afk[friend] = { since = now - math.floor(secs), zone = Clean(t[5] or ""):sub(1, 40), seen = now }
            if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
        end
        return
    end
    -- XV: en prik
    local from, to, nonce, line, at = t[2], t[3], t[4], tonumber(t[5]), tonumber(t[6])
    if not ROSTER_SET[from] or not ROSTER_SET[to] or from == db.me or from == to then return end
    if not nonce or nonce == "" or not nonce:match("^%d+$") or #nonce > 12 or not at then return end
    if not line or not LINES[line] then line = 1 end
    local e = { id = from .. "-" .. nonce, from = from, to = to, nonce = nonce, line = line, t = math.min(at, time()) }
    -- Spam-værn hos modtageren: ikke for tæt fra samme ven
    if to == db.me and math.abs(time() - e.t) < FRESH then
        if lastFrom[from] and GetTime() - lastFrom[from] < H.RECV_GAP then return end
        lastFrom[from] = GetTime()
    end
    H.Record(e)
end

-- Ved synk: de seneste prik, du har givet (dubletter filtreres fra hos modtageren)
function H.SendLog()
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
function H.MakeDemo()
    local db = DB()
    local others = {}
    for _, name in ipairs(ROSTER) do if name ~= db.me then others[#others + 1] = name end end
    if #others < 2 then return end
    local now = time()
    afk[others[1]] = { since = now - 34 * 60, zone = "Stormwind City", seen = now + 86400, demo = true }
    H.Record({ id = "demo-V-1", from = others[2], to = others[1], line = 2, t = now - 90 * 60, demo = true })
end

function H.ClearDemo()
    local _, h = DB()
    for i = #h.log, 1, -1 do
        if h.log[i].demo then table.remove(h.log, i) end
    end
    for f, st in pairs(afk) do
        if st.demo then afk[f] = nil end
    end
end

function H.Reset()
    local _, h = DB()
    wipe(h.log)
    h.lastSent = nil
    wipe(lastTo)
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
function ns.HjemmeskoSlash(cmd, arg)
    if cmd ~= "væk" and cmd ~= "vaek" and cmd ~= "wake" and cmd ~= "hjemmesko" and cmd ~= "zzz" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "fra" or arg == "off" or arg == "til" or arg == "on" then
        if arg == "til" or arg == "on" then db.settings.hjemmesko = nil else db.settings.hjemmesko = false end
        Print(L("Vækkelyd: ") .. ((db.settings.hjemmesko ~= false) and L("til") or L("fra")))
    elseif arg == "test" then
        -- Kun hos dig selv: intet sendes
        if not C.PlayEventSound("vaek", db.me) and not db.settings.sound then Print(L("Lyden er slået fra (|cffffd100/wc4ever sound|r).")) end
        ns.Toast({ kind = "hjemmesko", head = L("VÅGN OP"), title = string.format(L("%s prikker til dig!"), Name(db.me) or "?"),
                   text = H.Text(math.random(#LINES), Name(db.me) or "?", L("dig")), icon = H.ICON, dur = 6, force = true })
    elseif arg == "" then
        local friend = H.Sleepiest()
        if friend then
            ns.HjemmeskoWake(friend)
        else
            Print(L("Ingen af vennerne sover i hjemmeskoene lige nu."))
        end
    else
        local name = FindFriend(arg)
        if name then ns.HjemmeskoWake(name) else Print(L("Hvem? Skriv fx |cffffd100/wc4ever væk nick|r.")) end
    end
    return true
end

-- =============================================================================
-- Events
-- =============================================================================
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_FLAGS_CHANGED")
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:SetScript("OnEvent", function() H.Check() end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(10, H.Check) end
end
