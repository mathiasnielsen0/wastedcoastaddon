local _, ns = ...
local L = ns.L

-- =============================================================================
-- Daglig sladder (v0.11)
-- Første gang du logger ind på en ny dato (din lokale dato, pr. konto), får du et lille
-- vindue med højdepunkterne siden
-- sidst: levels, dødsfald (især de pinlige), epic loot, trofæer, dueller, Need-politiet,
-- guld og hvem der er forsvundet. Alt bygges af data, addonet allerede har og synker,
-- så sladderen sender ingen nye beskeder.
-- db.gossip = { out = sidst set online, snap = { ven -> højeste level }, shown = sidst vist,
--              day = datoen (ÅÅÅÅ-MM-DD) hvor sladderen sidst kom af sig selv }
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print = C.Print
local Name = C.Name

local MAX_BACK = 7 * 86400     -- længere tilbage end en uge kigger sladderen ikke
local FIRST_BACK = 86400       -- første gang: det seneste døgn
local SHOW_DELAY = 30          -- sekunder efter login, så vennernes data er nået frem
local MAX_LINES = 8
local GOLD_MIN = 50 * 10000    -- guldændringer under 50g er ikke sladder værd
local MISSING_DAYS = 4         -- ikke set i så mange dage = savnet

local session = { since = nil, snap = nil }

local function DB()
    local db = WastedCoastDB
    db.gossip = db.gossip or {}
    db.gossip.snap = db.gossip.snap or {}
    return db
end

local function Pick(list)
    return list[math.random(#list)]
end

local function ClassOf(friend)
    local best, bestLevel
    for _, c in pairs((WastedCoastDB.friends[friend] and WastedCoastDB.friends[friend].chars) or {}) do
        if not bestLevel or (c.level or 0) > bestLevel then best, bestLevel = c.class, c.level or 0 end
    end
    return best
end

-- "Du" om dig selv, ellers vennens navn i klassefarve
local function Who(friend)
    if friend == WastedCoastDB.me then return L("Du") end
    return C.ColorName(Name(friend), ClassOf(friend))
end

local function MaxLevels()
    local out = {}
    for _, name in ipairs(ROSTER) do
        local best = 0
        for _, c in pairs((WastedCoastDB.friends[name] and WastedCoastDB.friends[name].chars) or {}) do
            if not c.demo and (c.level or 0) > best then best = c.level end
        end
        if best > 0 then out[name] = best end
    end
    return out
end

-- Gem, hvor langt alle var, og hvornår du sidst var her (kaldes jævnligt og ved logout)
local function SaveSnapshot()
    local db = DB()
    if not db.me then return end
    db.gossip.out = time()
    for name, lvl in pairs(MaxLevels()) do
        if lvl > (db.gossip.snap[name] or 0) then db.gossip.snap[name] = lvl end
    end
end

local function Duration(secs)
    if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. L(" min") end
    if secs < 86400 then return math.floor(secs / 3600) .. L(" timer") end
    local d = math.floor(secs / 86400)
    return d .. (d == 1 and L(" dag") or L(" dage"))
end

local EPIC_TAILS = ns.LT({
    "Misundelse er en grim ting. Vi er alle misundelige.",
    "Ingen siger det højt, men alle tænker det: hvorfor ikke mig?",
    "Lootgoblin-alarm!",
    "RNG-guderne har en favorit, og det er ikke resten af os.",
})

local function IsEnvDeath(ev)
    for _, v in pairs(C.ENV_NAMES) do
        if ev.killer == v or ev.ability == v then return v end
    end
end

-- =============================================================================
-- Sladderen: en liste af { score, text }. Højest score vises først.
-- =============================================================================
local function Collect(since, snapOverride)
    local db = WastedCoastDB
    local lines = {}
    local function add(score, text) lines[#lines + 1] = { score = score, text = text } end

    -- Levels: sammenlign med sidst, du var her (eller levelAt, hvis vi ikke har et øjebliksbillede)
    local snap = snapOverride or session.snap or {}
    local gains = {}
    for name, lvl in pairs(MaxLevels()) do
        local before = snap[name]
        if not before and db.levelAt and db.levelAt[name] and not db.levelAt[name].g
            and (db.levelAt[name].t or 0) > since and db.levelAt[name].l == lvl then
            before = lvl - 1
        end
        if before and lvl > before then gains[#gains + 1] = { name = name, from = before, to = lvl } end
    end
    table.sort(gains, function(a, b) return (a.to - a.from) > (b.to - b.from) end)
    for i, g in ipairs(gains) do
        local n = g.to - g.from
        if g.to >= C.MAX_LEVEL then
            add(100, string.format(L("%s ramte |cffffd100MAX LEVEL %d|r! Nu begynder det rigtige spil."), Who(g.name), g.to))
        elseif n >= 3 and i == 1 then
            add(70, string.format(L("%s %s |cffffd100%d levels|r (%d til %d). %s"), Who(g.name),
                Pick({ L("grindede sig"), L("pløjede sig"), L("tæskede sig") }) .. L(" gennem"), n, g.from, g.to,
                Pick({ L("Har personen overhovedet sovet?"), L("Græsset blev ikke slået i dag."), L("Respekt. Og lidt bekymring.") })))
        elseif n >= 2 then
            add(50 + n, string.format(L("%s tog %d levels og er nu level %d."), Who(g.name), n, g.to))
        else
            add(40, string.format(L("%s nåede level %d."), Who(g.name), g.to))
        end
    end

    -- Dødsfald
    local deaths, killers, total = {}, {}, 0
    local ganked, gankers = {}, {}   -- v0.15: PvP-dødsfald pr. ven, og hvem der stod bag
    local worst, worstGap
    for _, ev in ipairs(db.events) do
        if (ev.time or 0) > since then
            local f = C.EventFriend(ev)
            if f then
                total = total + 1
                deaths[f] = (deaths[f] or 0) + 1
                if ev.pvp == true then
                    ganked[f] = (ganked[f] or 0) + 1
                    gankers[f] = gankers[f] or {}
                    if ev.killer and ev.killer ~= "" then gankers[f][ev.killer] = (gankers[f][ev.killer] or 0) + 1 end
                end
                killers[f] = killers[f] or {}
                if ev.killer and ev.killer ~= "" and ev.killer ~= "Ukendt" then
                    killers[f][ev.killer] = (killers[f][ev.killer] or 0) + 1
                end
                -- Pinligst: miljøet eller en mob langt under ens eget level
                local env = IsEnvDeath(ev)
                local kl = tonumber(ev.klvl)
                local gap = env and 12 or ((kl and kl > 0) and ((ev.level or 0) - kl) or -99)
                if gap >= 5 and (not worstGap or gap > worstGap) then worst, worstGap = { ev = ev, f = f, env = env }, gap end
            end
        end
    end
    local topF, topN = nil, 0
    for f, n in pairs(deaths) do
        if n > topN or (n == topN and f < topF) then topF, topN = f, n end
    end
    if topF and topN >= 2 then
        local killer, kn = nil, 0
        for k, n in pairs(killers[topF]) do if n > kn then killer, kn = k, n end end
        local tail = (killer and kn >= 2) and string.format(L(" %d af dem til %s."), kn, L(killer)) or ""
        add(45 + topN, string.format(L("%s døde |cffff5050%d gange|r.%s %s"), Who(topF), topN, tail,
            Pick({ L("Spirit healeren kender navnet nu."), L("Repair-regningen er ikke for sarte sjæle."), L("Kirkegården overvejer at give stamkundekort.") })))
    end
    -- PvP: hvem blev ganket mest?
    local gF, gN = nil, 0
    for f, n in pairs(ganked) do
        if n > gN or (n == gN and f < gF) then gF, gN = f, n end
    end
    if gF then
        local who, wn = nil, 0
        for k, n in pairs(gankers[gF]) do if n > wn or (n == wn and k < who) then who, wn = k, n end end
        local by = who and string.format(L(" %s stod bag %s."), who, wn == gN and (gN == 1 and L("det") or L("dem alle")) or (wn .. L(" af dem"))) or ""
        add(33 + math.min(10, gN), string.format(L("%s blev ganket af andre spillere |cff80b0ff%s|r.%s %s"), Who(gF),
            gN == 1 and L("én gang") or (gN .. L(" gange")), by,
            Pick({ L("Hævnen er sød."), L("Måske på tide at kigge sig over skulderen."), L("Den anden faction siger tak for kampen.") })))
    end
    if worst then
        local ev, w = worst.ev, Who(worst.f)
        local text
        if worst.env == C.ENV_NAMES.Falling then
            text = string.format(L("%s faldt ned og døde i %s. Tyngdekraften: 1, %s: 0."), w, ev.zone or "?", worst.f == db.me and L("dig") or Name(worst.f))
        elseif worst.env then
            text = string.format(L("%s døde af %s i %s. Ingen mob, bare naturen."), w, L(worst.env):lower(), ev.zone or "?")
        else
            text = string.format(L("%s (level %d) blev slået ihjel af en level %d %s i %s. Pinligt."), w, ev.level or 0, tonumber(ev.klvl) or 0, L(ev.killer) or "?", ev.zone or "?")
        end
        add(55, text)
    end
    if total == 0 and #db.events > 0 then
        add(10, L("Ingen døde. Ikke én. Hvem er I, og hvad har I gjort ved Wasted Coast?"))
    elseif total >= 5 and not (topF and topN == total) then
        add(25, string.format(L("I alt %d dødsfald i gruppen. Spirit healerne har haft travlt."), total))
    end

    -- Loot: epic og bedre nævnes én for én, ellers en optælling
    local epics, rares = {}, {}
    for _, ev in ipairs(db.loot) do
        if (ev.time or 0) > since then
            local f = C.EventFriend({ friend = ev.friend, name = ev.char })
            if f then
                if (ev.quality or 0) >= 4 then epics[#epics + 1] = { ev = ev, f = f }
                else rares[f] = (rares[f] or 0) + 1 end
            end
        end
    end
    table.sort(epics, function(a, b) return (a.ev.quality or 0) > (b.ev.quality or 0) or ((a.ev.quality == b.ev.quality) and (a.ev.time or 0) > (b.ev.time or 0)) end)
    local epicStart = math.random(#EPIC_TAILS)
    for i, e in ipairs(epics) do
        if i > 3 then break end
        add(60 - i, string.format(L("%s fik %s%s. %s"), Who(e.f), C.LootLink(e.ev),
            (e.ev.zone and e.ev.zone ~= "") and (L(" i ") .. e.ev.zone) or "",
            EPIC_TAILS[(epicStart + i) % #EPIC_TAILS + 1]))
    end
    local rf, rn = nil, 0
    for f, n in pairs(rares) do if n > rn then rf, rn = f, n end end
    if rf and rn >= 3 then
        add(30, string.format(L("%s samlede %d rare items op. Tasken er snart fuld."), Who(rf), rn))
    end

    -- Trofæer
    local achs = {}
    for _, name in ipairs(ROSTER) do
        for id, t in pairs(db.ach[name] or {}) do
            local a = C.ACH_BY_ID and C.ACH_BY_ID[id]
            if a and t > since and not (db.demoAch and db.demoAch[name] and db.demoAch[name][id]) then
                achs[#achs + 1] = { f = name, a = a }
            end
        end
    end
    table.sort(achs, function(x, y) return (x.a.pts or 0) > (y.a.pts or 0) end)
    for i, x in ipairs(achs) do
        if i > 2 then break end
        add(38 + math.min(10, (x.a.pts or 0) / 5), string.format(L("%s låste trofæet |cffffd100%s|r op: %s"), Who(x.f), x.a.name, x.a.desc or ""))
    end
    if #achs > 2 then add(20, string.format(L("Og %d trofæer mere. Se dem under Sjov > Trofæer."), #achs - 2)) end

    -- Dueller: hvem vandt flest
    local duelW, duelL = {}, {}
    for name, list in pairs(db.duels or {}) do
        if ROSTER_SET[name] then
            for _, d in ipairs(list) do
                if (d.t or 0) > since and not d.demo then
                    if d.won then duelW[name] = (duelW[name] or 0) + 1 else duelL[name] = (duelL[name] or 0) + 1 end
                end
            end
        end
    end
    local dk, dn = nil, 0
    for f, n in pairs(duelW) do if n > dn then dk, dn = f, n end end
    if dk then
        add(35, string.format(L("%s vandt %d %s og tabte %d. %s"), Who(dk), dn, dn == 1 and L("duel") or L("dueller"), duelL[dk] or 0,
            Pick({ L("Nogen skulle lære at holde kæft."), L("Kongen af Goldshire."), L("Der blev ikke givet hånd bagefter.") })))
    end

    -- Need-politiet
    local cops = {}
    for _, e in ipairs(db.needShame or {}) do
        if (e.time or 0) > since and not e.demo and ROSTER_SET[e.friend] then cops[#cops + 1] = e end
    end
    if #cops > 0 then
        local e = cops[#cops]
        local link = C.LootLink({ quality = e.quality, item = e.item, name = e.name or "?" })
        add(42, string.format(L("Need-politiet har anholdt %s for %s, der %s.%s"), Who(e.friend), link,
            e.why == "gone" and L("blev solgt uden at være brugt") or L("aldrig er blevet taget på"),
            #cops > 1 and string.format(L(" Og der er %s mere."), C.Plural(#cops - 1, L("sag"), L("sager"))) or ""))
    end

    -- Guld: største op- og nedtur (efter logout-målingerne)
    local up, upN, down, downN = nil, 0, nil, 0
    for name, h in pairs(db.goldHist or {}) do
        if ROSTER_SET[name] then
            local base, last
            for _, smp in ipairs(h) do
                if not smp.d then
                    if smp[1] <= since then base = smp elseif base then last = smp end
                end
            end
            if base and last then
                local diff = last[2] - base[2]
                if diff > upN then up, upN = name, diff end
                if -diff > downN then down, downN = name, -diff end
            end
        end
    end
    if up and upN >= GOLD_MIN then
        add(32, string.format(L("%s tjente |cffffd100%s|r. %s"), Who(up), C.FormatGold(upN),
            Pick({ L("Hvem skal give en omgang?"), L("Auktionshuset græder."), L("Lån ud til en flyvende mount?") })))
    end
    if down and downN >= GOLD_MIN then
        add(31, string.format(L("%s brugte |cffffd100%s|r. Det må have været noget vigtigt. Eller repairs."), Who(down), C.FormatGold(downN)))
    end

    -- Skammens hat
    local hat = ns.HatHolder and ns.HatHolder()
    if hat and deaths[hat] then
        add(18, string.format(L("%s bærer nu Skammens hat."), Who(hat)))
    end

    -- Savnede venner (kun dem, vi har set før)
    for _, name in ipairs(ROSTER) do
        if name ~= db.me then
            local seen = C.LastSeen(name)
            if seen and time() - seen > MISSING_DAYS * 86400 and time() - seen < 60 * 86400 then
                add(12, string.format(L("Har nogen hørt fra %s? Ikke set i %s."), Who(name), Duration(time() - seen)))
                break
            end
        end
    end

    table.sort(lines, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(MAX_LINES, #lines) do out[i] = lines[i].text end
    -- Kun "ingen døde" er ikke nok til en hel sladder
    if #out == 1 and lines[1].score <= 12 then return {} end
    return out
end

ns.GossipLines = Collect   -- til tests

-- =============================================================================
-- Vinduet
-- =============================================================================
local ui = {}

local function BuildWindow()
    local COL_BG, COL_GOLD = C.COL_BG, C.COL_GOLD
    local p = C.MakeBox("Frame", UIParent, COL_BG, COL_GOLD, "WastedCoastGossip")
    p:SetSize(480, 200)
    p:SetPoint("TOP", UIParent, "TOP", 0, -160)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if C.AddShadow then C.AddShadow(p, 8) end
    table.insert(UISpecialFrames, "WastedCoastGossip")

    local close = C.MakeCloseButton(p, 24, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)

    local icon = p:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\Icons\\INV_Letter_15")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    ui.title = C.Txt(p, "GameFontNormalLarge")
    ui.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    ui.title:SetText(L("Dagens sladder fra Wasted Coast"))
    ui.title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    ui.sub = C.Txt(p, "GameFontHighlightSmall")
    ui.sub:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -3)
    ui.sub:SetTextColor(0.6, 0.6, 0.66)

    ui.lines = {}
    for i = 1, MAX_LINES do
        local fs = C.Txt(p, "GameFontHighlight")
        fs:SetWidth(436)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if i == 1 then
            fs:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -58)
        else
            fs:SetPoint("TOPLEFT", ui.lines[i - 1], "BOTTOMLEFT", 0, -7)
        end
        ui.lines[i] = fs
    end

    local open = C.MakeButton(p, 130, 22, L("Åbn WC4ever"), function()
        p:Hide()
        if ns.frame then ns.frame:Show() end
    end)
    open:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 10)
    local ok = C.MakeButton(p, 90, 22, L("Fedt"), function() p:Hide() end)
    ok:SetPoint("RIGHT", open, "LEFT", -6, 0)
    ui.hint = C.Txt(p, "GameFontHighlightSmall")
    ui.hint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 14)
    ui.hint:SetTextColor(0.45, 0.45, 0.5)
    ui.hint:SetText(L("/wc4ever sladder viser den igen"))

    ui.frame = p
    return p
end

local function Bullet(i)
    return (i == 1) and "|cffffd100»|r " or "|cff9aa0a6»|r "
end

function ns.ShowGossip(lines, since)
    local p = ui.frame or BuildWindow()
    ui.sub:SetText(L("Siden du sidst var her, for ") .. Duration(math.max(60, time() - since)) .. L(" siden"))
    local h = 58
    for i, fs in ipairs(ui.lines) do
        if lines[i] then
            fs:SetText(Bullet(i) .. lines[i])
            fs:Show()
            h = h + (fs:GetStringHeight() or 14) + 7
        else
            fs:SetText("")
            fs:Hide()
        end
    end
    p:SetHeight(math.max(140, h + 44))
    p:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
end

local function Today() return date("%Y-%m-%d", time()) end

-- Byg og vis sladderen. auto = første login på dagen (vinduet kommer altid, også uden nyt)
function ns.Gossip(auto)
    local db = DB()
    if not db.me then return end
    local since = session.since or (time() - FIRST_BACK)
    local lines = Collect(since)
    if #lines == 0 and auto and since > time() - FIRST_BACK then
        -- var du her lige før midnat, så kig på hele det seneste døgn
        since = time() - FIRST_BACK
        lines = Collect(since)
    end
    ns.lastGossip = lines
    if #lines == 0 then
        local none = L("Ingen sladder siden sidst. Gå ud og dø lidt, så der er noget at snakke om.")
        if not auto then Print(none) return end
        lines = { none }
    end
    db.gossip.shown = time()
    ns.ShowGossip(lines, since)
    if db.settings.announce then
        Print(L("|cffffd100Dagens sladder:|r"))
        for _, l in ipairs(lines) do print("  " .. l) end
    end
end

function ns.GossipSlash(cmd, arg)
    if cmd ~= "sladder" and cmd ~= "gossip" then return false end
    local db = DB()
    if arg == "fra" or arg == "off" then
        db.settings.gossip = false
        Print(L("Sladder ved login: fra. |cffffd100/wc4ever sladder|r virker stadig."))
    elseif arg == "til" or arg == "on" then
        db.settings.gossip = true
        Print(L("Sladder ved login: til."))
    else
        ns.Gossip(false)
    end
    return true
end

-- =============================================================================
-- Events: husk "sidst her" ved login, vis sladderen lidt efter, gem ved logout
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if not WastedCoastDB then return end
    local db = DB()
    if event == "PLAYER_LOGIN" then
        local now = time()
        local out = db.gossip.out
        session.since = math.max(out or (now - FIRST_BACK), now - MAX_BACK)
        session.snap = {}
        for k, v in pairs(db.gossip.snap) do session.snap[k] = v end
        C_Timer.After(SHOW_DELAY, function()
            -- første login på en ny dato (pr. konto, så et alt-skifte samme dag ikke viser den igen)
            if db.me and db.settings.gossip ~= false and db.gossip.day ~= Today() then
                db.gossip.day = Today()
                ns.Gossip(true)
            end
            SaveSnapshot()
        end)
        C_Timer.NewTicker(60, SaveSnapshot)
    elseif event == "PLAYER_LOGOUT" then
        SaveSnapshot()
    end
end)
