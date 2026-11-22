local _, ns = ...
local L = ns.L

-- =============================================================================
-- Spilletid pr. dag (v0.31): en graf over, hvor meget hver ven har spillet hver dag
--   (Rangliste > Timer pr. dag), lidt ligesom guldgrafen.
--   * Hver ven måler sin egen spilletid: hvert minut lægges tilvæksten i /played for alle
--     dine karakterer (Played.lua's ns.PlayedNow) til dagens tal. Første gang en karakter
--     ses, gemmes dens spilletid kun som udgangspunkt, så målingen starter den dag, du får
--     versionen (ingen spilletid fra før trækkes ind på én dag).
--   * Dagen er dansk tid (Weekly.Offset), så alle har samme dagsskifte.
--   * En tilvækst, der er større end tiden siden sidste måling (fx spillet uden addonet på en
--     anden pc), tæller kun med op til den tid. En dag kan højst have 24 timer.
--   * Tallene sendes med XP-beskeden ved synk og hvert kvarter. Tal for en dag vokser kun,
--     så den største værdi vinder.
--   * Grafen viser enten timer pr. dag eller den samlede spilletid i perioden (akkumuleret).
--     Hold musen over en dag for at se alle vennernes tal den dag.
--
-- Besked: XP;ven;dag=sek,dag=sek,...   (dag = dagnummer siden 1/1-1970 i dansk tid, højst 255 tegn)
-- db.playedDay[ven][dag] = sekunder spillet den dag (også dine egne)
-- db.playedDayLast[ven][karakter] = { s = spilletid ved sidste måling, at = tid } (kun dine egne)
-- db.playedDaySince = tidspunktet, målingen begyndte hos dig
-- db.playedDayDemo[ven][dag] = demo-tal (/wc4ever demo), sendes aldrig
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Name = C.Name
local floor = math.floor

local PD = {}
ns.PlayedDays = PD

PD.DAY = 86400
PD.KEEP = 400          -- så mange dage gemmes
PD.TICK = 60           -- sekunder mellem målingerne
PD.RESEND = 900        -- sekunder mellem automatiske udsendelser, mens du er online
PD.SYNC_DAYS = 30      -- dage, der sendes ved den fulde synk
PD.SLACK = 120         -- så meget må en tilvækst overstige uret (GetTime og time() går lidt skævt)

local lastSent = {}    -- dag -> sekunder, som vi sidst sendte

local function DB()
    local db = WastedCoastDB
    db.playedDay = db.playedDay or {}
    db.playedDayLast = db.playedDayLast or {}
    db.playedDayDemo = db.playedDayDemo or {}
    return db
end

-- =============================================================================
-- Dage i dansk tid
-- =============================================================================
local function Offset(utc)
    if ns.Weekly and ns.Weekly.Offset then return ns.Weekly.Offset(utc) end
    return 3600
end

function PD.Day(utc)
    utc = utc or time()
    return floor((utc + Offset(utc)) / PD.DAY)
end

-- Hvornår dag d begynder (UTC)
function PD.DayStart(d)
    local loc = d * PD.DAY
    return loc - Offset(loc - 3600)
end

local WEEKDAYS = ns.LT({ "man", "tir", "ons", "tor", "fre", "lør", "søn" })
function PD.DayLabel(d, long)
    local _, m, dd = 1970, 1, 1
    if ns.Weekly and ns.Weekly.CivilFromDays then _, m, dd = ns.Weekly.CivilFromDays(d) end
    if long then
        return string.format("%s %d/%d", WEEKDAYS[(d + 3) % 7 + 1], dd, m)   -- 1/1-1970 var en torsdag
    end
    return string.format("%d/%d", dd, m)
end

-- =============================================================================
-- Måling
-- =============================================================================
function PD.Track(now)
    local db = DB()
    local me = db.me
    if not me or not ROSTER_SET[me] or not ns.PlayedNow then return end
    now = now or time()
    local info = db.friends and db.friends[me]
    if not info or not info.chars then return end
    if not db.playedDaySince then db.playedDaySince = now end
    local last = db.playedDayLast[me] or {}
    db.playedDayLast[me] = last
    local add = 0
    for char, c in pairs(info.chars) do
        if not c.demo then
            local secs = ns.PlayedNow(me, char, c)
            if secs then
                local prev = last[char]
                if type(prev) ~= "table" or not prev.s or secs < prev.s then
                    -- Første måling (eller en spilletid, der er gået baglæns): kun udgangspunktet
                    last[char] = { s = floor(secs), at = now }
                else
                    local d = floor(secs - prev.s)
                    if d > 0 then
                        add = add + math.min(d, math.max(0, now - (prev.at or now)) + PD.SLACK)
                        last[char] = { s = prev.s + d, at = now }
                    else
                        prev.at = now
                    end
                end
            end
        end
    end
    if add > 0 then
        local day = PD.Day(now)
        local r = db.playedDay[me] or {}
        db.playedDay[me] = r
        r[day] = math.min(PD.DAY, (r[day] or 0) + add)
    end
end

-- Gamle dage ud
function PD.Trim(now)
    local db = DB()
    local oldest = PD.Day(now or time()) - PD.KEEP
    for friend, days in pairs(db.playedDay) do
        for d in pairs(days) do
            if type(d) ~= "number" or d < oldest then days[d] = nil end
        end
        if not next(days) then db.playedDay[friend] = nil end
    end
end

-- =============================================================================
-- Netværk
-- =============================================================================
-- Sender dine dage fra og med "fromDay". onlyChanged: kun dage, der har ændret sig siden sidst
local function SendDays(fromDay, onlyChanged)
    local db = DB()
    local me = db.me
    if not me or not ROSTER_SET[me] then return end
    local r = db.playedDay[me]
    if not r then return end
    local days = {}
    for d, s in pairs(r) do
        if type(d) == "number" and d >= fromDay and s > 0 and (not onlyChanged or lastSent[d] ~= floor(s)) then
            days[#days + 1] = d
        end
    end
    table.sort(days)
    local head = "XP;" .. me .. ";"
    local parts = {}
    local function flush()
        if #parts > 0 then C.Send(head .. table.concat(parts, ",")) end
        parts = {}
    end
    local len = #head
    for _, d in ipairs(days) do
        local s = floor(r[d])
        local item = d .. "=" .. s
        if #parts > 0 and len + 1 + #item > 250 then
            flush()
            len = #head
        end
        len = len + (#parts > 0 and 1 or 0) + #item
        parts[#parts + 1] = item
        lastSent[d] = s
    end
    flush()
end

-- Ved synk: de seneste 30 dage (den lette synk kun i går og i dag)
function PD.Send(light)
    PD.Track()
    local today = PD.Day()
    SendDays(today - (light and 1 or (PD.SYNC_DAYS - 1)), false)
end
ns.SendPlayedDays = PD.Send

function ns.HandlePlayedDaysMessage(t)
    local db = DB()
    local friend, list = t[2], t[3]
    if not ROSTER_SET[friend] or friend == db.me or type(list) ~= "string" then return end
    local today = PD.Day()
    local changed = false
    for ds, ss in list:gmatch("(%d+)=(%d+)") do
        local d, s = tonumber(ds), tonumber(ss)
        if d and s and d <= today + 1 and d >= today - PD.KEEP and s >= 0 and s <= PD.DAY then
            local r = db.playedDay[friend] or {}
            db.playedDay[friend] = r
            if s > (r[d] or 0) then
                r[d] = s
                changed = true
            end
        end
    end
    if changed and ns.RefreshUI then ns.RefreshUI() end
end

-- =============================================================================
-- Data til grafen
-- =============================================================================
-- Dagene for en ven (demo-tal kun for en ven, der ikke har rigtige)
function PD.Days(friend)
    local db = DB()
    local r = db.playedDay[friend]
    if r and next(r) then return r end
    return db.playedDayDemo[friend]
end

-- Første dag med tal hos nogen (eller i dag)
function PD.FirstDay()
    local first = PD.Day()
    for _, name in ipairs(ROSTER) do
        for d in pairs(PD.Days(name) or {}) do
            if type(d) == "number" and d < first then first = d end
        end
    end
    return first
end

-- Statistik for en ven i dagene [from, to]
function PD.Stats(friend, from, to)
    local days = PD.Days(friend) or {}
    local total, best, bestDay, first, active = 0, 0, nil, nil, 0
    for d = from, to do
        local s = days[d]
        if s then
            first = first or d
            total = total + s
            if s > 0 then active = active + 1 end
            if s > best then best, bestDay = s, d end
        end
    end
    local n = first and (to - first + 1) or 0
    return { total = total, best = best, bestDay = bestDay, first = first, active = active,
             avg = n > 0 and total / n or 0, today = days[PD.Day()] or 0 }
end

-- =============================================================================
-- Demo, nulstilling og kommando
-- =============================================================================
function PD.MakeDemo()
    local db = DB()
    local today = PD.Day()
    for _, name in ipairs(ROSTER) do
        if name ~= db.me and not (db.playedDay[name] and next(db.playedDay[name])) then
            local days = {}
            local nolife = math.random(1, 5)
            for d = today - 29, today do
                if math.random() < 0.65 then
                    days[d] = math.random(600, 3600 * nolife)
                end
            end
            db.playedDayDemo[name] = days
        end
    end
end

function PD.ClearDemo()
    local db = WastedCoastDB
    if db then db.playedDayDemo = nil end
end

function PD.Reset()
    local db = WastedCoastDB
    if not db then return end
    db.playedDay, db.playedDayLast, db.playedDayDemo = nil, nil, nil
    db.playedDaySince = time()
    wipe(lastSent)
end

function ns.PlayedDaysSlash(cmd)
    if cmd ~= "timer" and cmd ~= "hours" then return false end
    PD.Track()
    local today = PD.Day()
    local from = today - 6
    C.Print(L("|cffffd100Spilletid de sidste 7 dage|r:"))
    local list = {}
    for _, name in ipairs(ROSTER) do
        local st = PD.Stats(name, from, today)
        if st.first then list[#list + 1] = { name = name, st = st } end
    end
    table.sort(list, function(a, b)
        if a.st.total ~= b.st.total then return a.st.total > b.st.total end
        return a.name < b.name
    end)
    for i, x in ipairs(list) do
        print(string.format(L("  %d. %s: %s  (i dag %s)"), i, Name(x.name), ns.FormatPlayed(x.st.total), ns.FormatPlayed(x.st.today)))
    end
    if #list == 0 then print(L("  Ingen målinger endnu. Spilletiden pr. dag måles fra i dag.")) end
    return true
end

-- =============================================================================
-- UI: side 21 - timer pr. dag (under Rangliste)
-- =============================================================================
local Txt, MakeBox, MakeButton = C.Txt, C.MakeBox, C.MakeButton
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN, COL_SELECT = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN, C.COL_SELECT
local RANGES = ns.LT({ { label = "7 dage", days = 7 }, { label = "14 dage", days = 14 },
                       { label = "30 dage", days = 30 }, { label = "90 dage", days = 90 } })
local MODES = ns.LT({ { label = "Pr. dag" }, { label = "Samlet" } })
local GRAPH_L, GRAPH_R, GRAPH_T, GRAPH_B = 50, 12, 12, 24
local MAX_DOT_DAYS = 45   -- flere dage end det: kun linjer (ellers tusindvis af prikker)
local ui = { range = 1, mode = 1, hidden = {} }
PD.ui = ui

local function Colors()
    return ns.FRIEND_COLORS or { { 1, 0.82, 0.2 } }
end

-- Kort timetal til aksen
local function HoursShort(s)
    local h = (s or 0) / 3600
    if h > 0 and h < 1 then return string.format("%dm", floor(s / 60 + 0.5)) end
    if h >= 100 then return string.format(L("%dt"), floor(h + 0.5)) end
    if h == floor(h) then return string.format(L("%dt"), h) end
    return string.format(L("%.1ft"), h)
end
PD.HoursShort = HoursShort

-- Rundt tal over max (i sekunder), så akserne får pæne trin
local function NiceMax(s)
    local h = math.max(1, (s or 0) / 3600)
    if h ~= h or h > 1e6 then return 1e6 * 3600 end
    local step = 1
    while step * 10 <= h do step = step * 10 end
    for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
        if step * m >= h then return step * m * 3600 end
    end
    return step * 10 * 3600
end
PD.NiceMax = NiceMax

-- Hvilke dage grafen viser: fra den første måling, højst så mange dage som perioden
function PD.Window(rangeIdx, now)
    local today = PD.Day(now)
    local days = RANGES[rangeIdx or 1].days
    local from = math.max(today - days + 1, PD.FirstDay())
    return from, today
end

-- Serier: { name, col, pts = { [i] = sek eller nil } } for dagene from..to
function PD.Series(from, to, cumulative)
    local list = {}
    local cols = Colors()
    for i, name in ipairs(ROSTER) do
        local days = PD.Days(name) or {}
        local pts, started, sum = {}, false, 0
        for d = from, to do
            if days[d] or started then
                started = true
                local s = days[d] or 0
                sum = sum + s
                pts[d - from + 1] = cumulative and sum or s
            end
        end
        list[#list + 1] = { name = name, col = cols[(i - 1) % #cols + 1], pts = pts, any = started }
    end
    return list
end

local function GraphLine(g, i)
    local l = g.lines[i]
    if l == nil then
        l = g.CreateLine and g:CreateLine(nil, "ARTWORK") or false
        if l then l:SetThickness(2) end
        g.lines[i] = l
    end
    return l
end

local function GraphDot(g, i)
    local d = g.dots[i]
    if not d then
        d = g:CreateTexture(nil, "OVERLAY")
        d:SetSize(5, 5)
        g.dots[i] = d
    end
    return d
end

-- Tooltip for én dag: alle viste venner, mest først
local function ShowDayTooltip(col)
    local d = col.day
    if not d then return end
    GameTooltip:SetOwner(col, "ANCHOR_RIGHT")
    GameTooltip:AddLine(PD.DayLabel(d, true) .. (d == PD.Day() and L(" (i dag)") or ""), 1, 1, 1)
    local rows, total = {}, 0
    for _, s in ipairs(ui.series or {}) do
        if not ui.hidden[s.name] and s.any then
            local v = (PD.Days(s.name) or {})[d] or 0
            rows[#rows + 1] = { s = s, v = v }
            total = total + v
        end
    end
    table.sort(rows, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        return a.s.name < b.s.name
    end)
    for _, r in ipairs(rows) do
        GameTooltip:AddDoubleLine(Name(r.s.name), r.v > 0 and ns.FormatPlayed(r.v) or "-",
            r.s.col[1], r.s.col[2], r.s.col[3], 1, 1, 1)
    end
    if #rows == 0 then
        GameTooltip:AddLine(L("Ingen målinger den dag"), 0.6, 0.6, 0.66)
    else
        GameTooltip:AddDoubleLine(L("I alt"), ns.FormatPlayed(total), 0.8, 0.8, 0.8, 1, 0.82, 0.2)
    end
    GameTooltip:Show()
end

local function DayColumn(g, i)
    local c = g.cols[i]
    if not c then
        c = CreateFrame("Frame", nil, g)
        c:EnableMouse(true)
        c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 2)
        c.hl:SetAllPoints(c)
        c.hl:SetColorTexture(1, 1, 1, 0.05)
        c.hl:Hide()
        c:SetScript("OnEnter", function(self) self.hl:Show(); ShowDayTooltip(self) end)
        c:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        g.cols[i] = c
    end
    return c
end

local function BuildPage(page)
    ui.rangeBtns = {}
    for i, rg in ipairs(RANGES) do
        local b = MakeButton(page, 70, 24, rg.label, function()
            ui.range = i
            ns.RefreshUI()
        end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 74, 0)
        ui.rangeBtns[i] = b
    end
    ui.modeBtns = {}
    for i, md in ipairs(MODES) do
        local b = MakeButton(page, 70, 24, md.label, function()
            ui.mode = i
            ns.RefreshUI()
        end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", #RANGES * 74 + 12 + (i - 1) * 74, 0)
        ui.modeBtns[i] = b
    end
    ui.info = Txt(page, "GameFontHighlightSmall")
    ui.info:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -6)
    ui.info:SetJustifyH("RIGHT")
    ui.info:SetWidth(170)
    ui.info:SetTextColor(0.6, 0.6, 0.66)

    ui.friendBtns = {}
    for i = 1, ns.MAX_MEMBERS do
        local b
        b = MakeButton(page, 70, 22, "", function()
            if not b.who then return end
            ui.hidden[b.who] = not ui.hidden[b.who] or nil
            ns.RefreshUI()
        end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 73, -30)
        b.text:SetWidth(64)
        b.text:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local st = self.stats
            if not st then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(Name(self.who), 1, 1, 1)
            if not st.first then
                GameTooltip:AddLine(L("Ingen målinger i perioden"), 0.6, 0.6, 0.66)
                GameTooltip:AddLine(L("Kommer, når vennen logger ind med v0.31 eller nyere."), 0.6, 0.6, 0.66, true)
            else
                GameTooltip:AddDoubleLine(L("I dag"), ns.FormatPlayed(st.today), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L("I perioden"), ns.FormatPlayed(st.total), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L("Snit pr. dag"), ns.FormatPlayed(st.avg), 0.8, 0.8, 0.8, 1, 1, 1)
                if st.bestDay then
                    GameTooltip:AddDoubleLine(L("Mest på én dag"), ns.FormatPlayed(st.best) .. "  (" .. PD.DayLabel(st.bestDay, true) .. ")",
                        0.8, 0.8, 0.8, 1, 0.82, 0.2)
                end
                GameTooltip:AddDoubleLine(L("Dage med spil"), tostring(st.active), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            GameTooltip:AddLine(L("Klik for at skjule/vise"), 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.friendBtns[i] = b
    end

    local g = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    g:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -60)
    g:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    g.lines, g.dots, g.grid, g.ylab, g.xlab, g.cols = {}, {}, {}, {}, {}, {}
    for i = 1, 5 do
        local t = g:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetColorTexture(1, 1, 1, i == 1 and 0.18 or 0.06)
        t:SetHeight(1)
        g.grid[i] = t
        local fs = Txt(g, "GameFontHighlightSmall")
        fs:SetJustifyH("RIGHT")
        fs:SetWidth(GRAPH_L - 8)
        fs:SetTextColor(0.55, 0.55, 0.6)
        g.ylab[i] = fs
    end
    for i = 1, 8 do
        local fs = Txt(g, "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        fs:SetWidth(60)
        fs:SetTextColor(0.55, 0.55, 0.6)
        g.xlab[i] = fs
    end
    g.empty = Txt(g, "GameFontHighlight")
    g.empty:SetPoint("CENTER", g, "CENTER", 0, 0)
    g.empty:SetJustifyH("CENTER")
    g.empty:SetWidth(560)
    g.empty:SetTextColor(0.6, 0.6, 0.66)
    ui.graph = g
end

local function RefreshPage()
    PD.Track()
    for i, b in ipairs(ui.rangeBtns) do
        local c = (i == ui.range) and COL_SELECT or COL_BTN
        b:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    for i, b in ipairs(ui.modeBtns) do
        local c = (i == ui.mode) and COL_SELECT or COL_BTN
        b:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    local g = ui.graph
    local from, to = PD.Window(ui.range)
    local n = to - from + 1
    local cumulative = ui.mode == 2
    local series = PD.Series(from, to, cumulative)
    ui.series = series

    local maxS, any, total, top = 0, false, 0, nil
    ns.ShowFirst(ui.friendBtns, #ROSTER)
    for i, s in ipairs(series) do
        local b = ui.friendBtns[i]
        b.who = s.name
        b.stats = PD.Stats(s.name, from, to)
        b.text:SetText(Name(s.name))
        if ui.hidden[s.name] then
            b.text:SetTextColor(0.4, 0.4, 0.45)
            b:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        else
            b.text:SetTextColor(s.col[1], s.col[2], s.col[3])
            b:SetBackdropColor(s.col[1] * 0.18, s.col[2] * 0.18, s.col[3] * 0.18, 1)
            if s.any then
                any = true
                for k = 1, n do
                    local v = s.pts[k]
                    if v and v > maxS then maxS = v end
                end
                total = total + b.stats.total
                if not top or b.stats.total > top.v then top = { name = s.name, v = b.stats.total } end
            end
        end
    end

    local w = (g:GetWidth() or 732) - GRAPH_L - GRAPH_R
    local h = (g:GetHeight() or 340) - GRAPH_T - GRAPH_B
    if w <= 0 then w = 732 - GRAPH_L - GRAPH_R end
    if h <= 0 then h = 340 - GRAPH_T - GRAPH_B end
    local topS = NiceMax(maxS)

    for i = 1, 5 do
        local frac = (i - 1) / 4
        local y = GRAPH_B + h * frac
        g.grid[i]:ClearAllPoints()
        g.grid[i]:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GRAPH_L, y)
        g.grid[i]:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -GRAPH_R, y)
        g.ylab[i]:ClearAllPoints()
        g.ylab[i]:SetPoint("RIGHT", g, "BOTTOMLEFT", GRAPH_L - 6, y)
        g.ylab[i]:SetText(HoursShort(topS * frac))
    end

    local colW = w / n
    local function X(k) return GRAPH_L + colW * (k - 0.5) end
    local function Y(v) return GRAPH_B + h * (v / topS) end

    -- Datoer under aksen: højst 8, jævnt fordelt, altid med i dag
    local labels = math.min(8, n)
    for i = 1, #g.xlab do
        local fs = g.xlab[i]
        if i <= labels then
            local k = (labels == 1) and n or (1 + floor((n - 1) * (i - 1) / (labels - 1) + 0.5))
            fs:ClearAllPoints()
            fs:SetPoint("TOP", g, "BOTTOMLEFT", X(k), GRAPH_B - 4)
            fs:SetText((from + k - 1 == to) and L("i dag") or PD.DayLabel(from + k - 1))
            fs:Show()
        else
            fs:Hide()
        end
    end

    -- Usynlige kolonner til musen
    for k = 1, n do
        local c = DayColumn(g, k)
        c.day = from + k - 1
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GRAPH_L + colW * (k - 1), GRAPH_B)
        c:SetSize(math.max(1, colW), math.max(1, h))
        c:Show()
    end
    for k = n + 1, #g.cols do g.cols[k]:Hide() end

    local nl, nd = 0, 0
    local dots = n <= MAX_DOT_DAYS or not g.CreateLine
    for _, s in ipairs(series) do
        if not ui.hidden[s.name] and s.any then
            local prev
            for k = 1, n do
                local v = s.pts[k]
                if v then
                    local x, y = X(k), Y(v)
                    if dots then
                        nd = nd + 1
                        local d = GraphDot(g, nd)
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", g, "BOTTOMLEFT", x, y)
                        d:SetColorTexture(s.col[1], s.col[2], s.col[3], 1)
                        d:Show()
                    end
                    if prev then
                        nl = nl + 1
                        local l = GraphLine(g, nl)
                        if l then
                            l:SetStartPoint("BOTTOMLEFT", g, prev[1], prev[2])
                            l:SetEndPoint("BOTTOMLEFT", g, x, y)
                            l:SetColorTexture(s.col[1], s.col[2], s.col[3], 0.9)
                            l:Show()
                        end
                    end
                    prev = { x, y }
                end
            end
        end
    end
    for i = nl + 1, #g.lines do if g.lines[i] then g.lines[i]:Hide() end end
    for i = nd + 1, #g.dots do g.dots[i]:Hide() end

    g.empty:SetText(any and "" or L("Ingen spilletid pr. dag endnu. Den måles fra den dag, I får den nye version, mens I spiller."))
    if any then
        local txt = L("I perioden: ") .. ns.FormatPlayed(total)
        if top and top.v > 0 then txt = txt .. "\n" .. L("Mest: ") .. Name(top.name) end
        ui.info:SetText(txt)
    else
        ui.info:SetText("")
    end
end

C.EXTRA_PAGES[21] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        pcall(PD.Trim)
        C_Timer.NewTicker(PD.TICK, function() pcall(PD.Track) end)
        C_Timer.NewTicker(PD.RESEND, function()
            if not WastedCoastDB.me then return end
            PD.Track()
            SendDays(PD.Day() - 1, true)
        end)
    elseif event == "PLAYER_LOGOUT" then
        pcall(PD.Track)
    end
end)
