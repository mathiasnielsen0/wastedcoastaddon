local _, ns = ...
local L = ns.L

-- =============================================================================
-- Spilletid (v0.13): /played for hver karakter, samlet pr. ven og for hele gruppen,
-- og deaths/hr (dødsfald pr. times spilletid).
-- Spillet fortæller kun din egen spilletid (TIME_PLAYED_MSG efter RequestTimePlayed), så
-- hver ven måler sin egen ved login og sender den til de andre. Mens du er online, tæller
-- addonet selv videre og sender den nye værdi hvert kvarter og ved synk.
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
--
-- db.friends[ven].chars[karakter].played = { t = spilletid i alt (sek), l = på nuværende level, at = målt }
-- Besked: PT;ven;karakter;i alt;level;målt
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Name = C.Name

local RESEND = 900            -- sekunder mellem automatiske opdateringer, mens du er online
local MAX_EXTRA = RESEND + 300 -- så længe tæller vi selv videre på en vens online karakter
local MIN_HOURS = 0.5         -- under en halv times spilletid giver deaths/hr ingen mening
local MAX_PLAYED = 20 * 365 * 86400

local session = { char = nil, base = nil, at = nil, quiet = 0, asked = false }

local function DB() return WastedCoastDB end

-- =============================================================================
-- Formatering
-- =============================================================================
function ns.FormatPlayed(s)
    if not s then return "-" end
    s = math.floor(s)
    local d, h, m = math.floor(s / 86400), math.floor((s % 86400) / 3600), math.floor((s % 3600) / 60)
    if d > 0 then return string.format(L("%dd %dt"), d, h) end
    if h > 0 then return string.format(L("%dt %dm"), h, m) end
    return string.format("%dm", m)
end

function ns.FormatDPH(v)
    if not v then return "-" end
    if v >= 10 then return string.format("%.1f", v) end
    return string.format("%.2f", v)
end

-- =============================================================================
-- Beregning
-- =============================================================================
-- Spilletid lige nu for en karakter: den målte værdi, plus tiden siden, hvis den er online
local function PlayedNow(friend, char, c)
    local p = c and c.played
    if not p or not p.t then return nil end
    local now = time()
    local db = DB()
    if friend == db.me then
        if char == session.char and session.base then
            return session.base + math.max(0, GetTime() - session.at)
        end
        return p.t
    end
    if p.at and c.seen and (now - c.seen) < 150 then
        return p.t + math.max(0, math.min(now - p.at, MAX_EXTRA))
    end
    return p.t
end
ns.PlayedNow = PlayedNow

-- Dødsfald pr. karakter, og hvor mange af dem der var PvP
local function DeathsByChar(friend)
    local by, pvp = {}, {}
    for _, ev in ipairs(DB().events or {}) do
        if ev.name and C.EventFriend(ev) == friend then
            by[ev.name] = (by[ev.name] or 0) + 1
            if ev.pvp == true then pvp[ev.name] = (pvp[ev.name] or 0) + 1 end
        end
    end
    return by, pvp
end

local function Rate(deaths, secs)
    if not secs or secs < MIN_HOURS * 3600 then return nil end
    return deaths / (secs / 3600)
end
ns.DeathRate = Rate

-- Karaktererne hos en ven med spilletid og dødsfald, mest spillet først
function ns.PlayedChars(friend)
    local db = DB()
    local info = db.friends[friend]
    local deaths, pvpDeaths = DeathsByChar(friend)
    local list = {}
    for name, c in pairs((info and info.chars) or {}) do
        local secs = PlayedNow(friend, name, c)
        local d, pv = deaths[name] or 0, pvpDeaths[name] or 0
        list[#list + 1] = {
            name = name, full = C.CharFull(friend, name, c.surname), class = c.class, level = c.level or 0,
            secs = secs, levelSecs = c.played and c.played.l, at = c.played and c.played.at,
            deaths = d, pvp = pv, dph = Rate(d, secs), pveDph = Rate(d - pv, secs), pvpDph = Rate(pv, secs), online = c.seen and (time() - c.seen) < 150,
        }
    end
    table.sort(list, function(a, b)
        if (a.secs or -1) ~= (b.secs or -1) then return (a.secs or -1) > (b.secs or -1) end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return list
end

-- Samlet for en ven. dph regnes kun på karakterer med kendt spilletid, så karakterer fra
-- før addonet (eller fra en ældre version uden spilletid) ikke trækker tallet op.
function ns.PlayedTotals(friend)
    local secs, deaths, allDeaths, known, top = 0, 0, 0, 0, nil
    local pvp, allPvp = 0, 0
    for _, ch in ipairs(ns.PlayedChars(friend)) do
        allDeaths = allDeaths + ch.deaths
        allPvp = allPvp + ch.pvp
        if ch.secs then
            secs = secs + ch.secs
            deaths = deaths + ch.deaths
            pvp = pvp + ch.pvp
            known = known + 1
            if not top then top = ch end
        end
    end
    return {
        secs = known > 0 and secs or nil, deaths = allDeaths, rated = deaths,
        pvp = allPvp, ratedPvp = pvp,   -- rated/ratedPvp = kun karakterer med kendt spilletid
        dph = known > 0 and Rate(deaths, secs) or nil, known = known, top = top,
        pveDph = known > 0 and Rate(deaths - pvp, secs) or nil, pvpDph = known > 0 and Rate(pvp, secs) or nil,
    }
end

-- Hele gruppen
function ns.GroupPlayed()
    local secs, deaths, known, topChar, topFriend = 0, 0, 0, nil, nil
    local pvp = 0
    for _, friend in ipairs(ROSTER) do
        local t = ns.PlayedTotals(friend)
        if t.secs then
            secs = secs + t.secs
            deaths = deaths + t.rated
            pvp = pvp + t.ratedPvp
            known = known + 1
            if t.top and (not topChar or t.top.secs > topChar.secs) then topChar, topFriend = t.top, friend end
        end
    end
    return { secs = known > 0 and secs or nil, deaths = deaths, dph = known > 0 and Rate(deaths, secs) or nil,
             pvp = pvp, pveDph = known > 0 and Rate(deaths - pvp, secs) or nil, pvpDph = known > 0 and Rate(pvp, secs) or nil,
             known = known, topChar = topChar, topFriend = topFriend }
end

-- Rangliste over deaths/hr (flest først); bruges også på Død-fanen
function ns.DeathRateRanking()
    local list = {}
    for _, friend in ipairs(ROSTER) do
        local t = ns.PlayedTotals(friend)
        if t.dph then
            list[#list + 1] = { name = friend, dph = t.dph, deaths = t.rated, pvp = t.ratedPvp, secs = t.secs,
                                pveDph = t.pveDph, pvpDph = t.pvpDph }
        end
    end
    table.sort(list, function(a, b)
        if a.dph ~= b.dph then return a.dph > b.dph end
        return a.name < b.name
    end)
    return list
end

-- =============================================================================
-- Måling og netværk
-- =============================================================================
local function MyChar()
    local db = DB()
    if not db.me or not session.char then return nil end
    return C.UpdateChar(db.me, session.char, nil, time())
end

-- Skriv den aktuelle spilletid ned på din karakter
local function StoreMine()
    if not session.base then return nil end
    local c = MyChar()
    if not c then return nil end
    local elapsed = math.max(0, GetTime() - session.at)
    c.played = { t = math.floor(session.base + elapsed), l = math.floor((session.levelBase or 0) + elapsed), at = time() }
    return c
end

local function SendOne(friend, char, c)
    if c and c.played and c.played.t then
        C.Send(string.format("PT;%s;%s;%d;%d;%d", friend, char, c.played.t, c.played.l or 0, c.played.at or 0))
    end
end

-- Ved synk: alle dine karakterers spilletid (den lette synk kun den, du spiller nu)
function ns.SendPlayed(light)
    local db = DB()
    if not db.me then return end
    StoreMine()
    for char, c in pairs((db.friends[db.me] and db.friends[db.me].chars) or {}) do
        if not c.demo and (not light or char == session.char) then SendOne(db.me, char, c) end
    end
end

local function SendMine()
    local c = StoreMine()
    if c then SendOne(DB().me, session.char, c) end
end

function ns.OnPlayedMessage(t)
    local db = DB()
    local friend, char, total, level, at = t[2], t[3], tonumber(t[4]), tonumber(t[5]) or 0, tonumber(t[6]) or 0
    if not ROSTER_SET[friend] or friend == db.me or not char or char == "" or not total then return end
    if total < 0 or total > MAX_PLAYED then return end
    local c = C.UpdateChar(friend, char, nil, 1)
    if not c then return end
    -- Spilletid vokser kun: den største værdi vinder (beskeder kan komme i forkert rækkefølge)
    if c.played and (c.played.t or 0) > total then return end
    c.played = { t = math.floor(total), l = math.floor(level), at = at > 0 and at or time() }
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Spillet svarer på RequestTimePlayed med TIME_PLAYED_MSG. Den, addonet selv beder om,
-- skal ikke skrive "Total time played" i chatten; skriver du selv /played, vises den som altid.
local function QuietChat()
    if session.hooked then return end
    session.hooked = true
    local function wrap(orig)
        return function(...)
            if GetTime() < session.quiet then return end
            return orig(...)
        end
    end
    -- Classic-klienterne bruger den globale funktion; nyere motorer (Forever) ChatFrameUtil
    if type(ChatFrame_DisplayTimePlayed) == "function" then
        ChatFrame_DisplayTimePlayed = wrap(ChatFrame_DisplayTimePlayed)
    end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.DisplayTimePlayed) == "function" then
        ChatFrameUtil.DisplayTimePlayed = wrap(ChatFrameUtil.DisplayTimePlayed)
    end
end

function ns.AskPlayed()
    if not RequestTimePlayed then return end
    QuietChat()
    session.quiet = GetTime() + 5
    session.asked = true
    pcall(RequestTimePlayed)
end

function ns.OnTimePlayed(total, level)
    total, level = tonumber(C.GAME.Plain(total)), tonumber(C.GAME.Plain(level))
    if not total then return end
    session.quiet = 0
    session.char = UnitName("player")
    session.base, session.levelBase, session.at = total, level or 0, GetTime()
    local db = DB()
    if db.me then
        SendMine()
        if ns.RefreshUI then ns.RefreshUI() end
    end
end

-- Demo: spilletid til demo-karakterer (kaldes fra /wc4ever demo)
function ns.DemoPlayed(c)
    local lvl = c.level or 1
    local t = math.floor(lvl * lvl * (60 + math.random(0, 90)) + math.random(0, 3600))
    c.played = { t = t, l = math.random(300, 20000), at = time() - math.random(60, 86400) }
end

-- =============================================================================
-- UI: side 17 - spilletid og deaths/hr (under Rangliste)
-- =============================================================================
local Txt, MakeBox, Field = C.Txt, C.MakeBox, C.Field
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN, COL_SELECT = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN, C.COL_SELECT
local ui = {}
ns.playedUI = ui
local CHAR_ROWS = 10

local function Header(box, text, sub)
    local h = Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(text)
    h:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    local s = Txt(box, "GameFontHighlightSmall")
    s:SetPoint("LEFT", h, "RIGHT", 8, -1)
    s:SetTextColor(0.5, 0.5, 0.56)
    s:SetText(sub or "")
    return h, s
end

local function Heads(box, cols)
    for _, c in ipairs(cols) do
        local fs = Txt(box, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + c.x, -38)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.j)
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(c.label)
    end
end

local LEFT_COLS = ns.LT({
    { x = 4,   w = 18, j = "CENTER", label = "#" },
    { x = 24,  w = 96, j = "LEFT",   label = "Ven" },
    { x = 122, w = 76, j = "CENTER", label = "Spilletid" },
    { x = 200, w = 40, j = "CENTER", label = "Døde" },
    { x = 242, w = 52, j = "CENTER", label = "Deaths/hr" },
    { x = 296, w = 42, j = "CENTER", label = "Kar." },
})
local RIGHT_COLS = ns.LT({
    { x = 4,   w = 150, j = "LEFT",   label = "Karakter" },
    { x = 156, w = 30,  j = "CENTER", label = "Lvl" },
    { x = 188, w = 70,  j = "CENTER", label = "Spilletid" },
    { x = 260, w = 34,  j = "CENTER", label = "Døde" },
    { x = 294, w = 46,  j = "CENTER", label = "Deaths/hr" },
})

local function DphColor(v)
    if not v then return 0.6, 0.6, 0.66 end
    if v >= 1 then return 1, 0.4, 0.4 end
    if v >= 0.3 then return 1, 0.75, 0.4 end
    return 0.45, 0.9, 0.5
end

local function BuildPage(page)
    local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(362)
    Header(left, L("Spilletid"), L("/played for hele gruppen"))
    Heads(left, LEFT_COLS)
    ui.rows = {}
    for i = 1, ns.MAX_MEMBERS do
        local row = MakeBox("Button", left, COL_BTN, COL_BORDER)
        row:SetSize(342, 24)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -(54 + (i - 1) * 27))
        row.f = {}
        for k, c in ipairs(LEFT_COLS) do
            row.f[k] = Field(row, c.x, c.w, c.j, k == 2 and "GameFontNormal" or "GameFontHighlight")
        end
        row:SetScript("OnClick", function(self)
            if self.data then ui.sel = self.data.name; ns.RefreshUI() end
        end)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Name(d.name), 1, 1, 1)
            local t = d.t
            if not t.secs then
                GameTooltip:AddLine(L("Ingen spilletid endnu"), 0.6, 0.6, 0.66)
                GameTooltip:AddLine(L("Kommer, når ") .. Name(d.name) .. L(" logger ind med v0.13 eller nyere."), 0.6, 0.6, 0.66, true)
            else
                GameTooltip:AddDoubleLine(L("Spilletid i alt"), ns.FormatPlayed(t.secs), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L("Timer"), string.format("%.1f", t.secs / 3600), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L("Dødsfald"), string.format("%d  (%d PvE, %d PvP)", t.rated, t.rated - t.ratedPvp, t.ratedPvp),
                    0.8, 0.8, 0.8, 1, 0.5, 0.5)
                GameTooltip:AddDoubleLine("Deaths/hr", ns.FormatDPH(t.dph), 0.8, 0.8, 0.8, DphColor(t.dph))
                GameTooltip:AddDoubleLine(L("  PvE pr. time"), ns.FormatDPH(t.pveDph), 0.6, 0.6, 0.66, DphColor(t.pveDph))
                GameTooltip:AddDoubleLine(L("  PvP pr. time"), ns.FormatDPH(t.pvpDph), 0.6, 0.6, 0.66, 0.5, 0.7, 1)
                if t.top then
                    GameTooltip:AddDoubleLine(L("Mest spillet"), t.top.full or t.top.name, 0.8, 0.8, 0.8, C.ClassColor(t.top.class))
                end
            end
            GameTooltip:AddLine(L("Klik for at se karaktererne"), 0.5, 0.5, 0.56)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.rows[i] = row
    end
    ui.total = Txt(left, "GameFontHighlight")
    ui.total:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -(54 + ns.MAX_MEMBERS * 27 + 6))
    ui.total:SetWidth(338)
    ui.total:SetSpacing(3)
    ui.note = Txt(left, "GameFontHighlightSmall")
    ui.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 10)
    ui.note:SetWidth(338)
    ui.note:SetTextColor(0.5, 0.5, 0.56)
    ui.note:SetText(L("Deaths/hr = dødsfald pr. times spilletid (kun karakterer med kendt spilletid og mindst en halv time)."))

    local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(362)
    ui.rightHead, ui.rightSub = Header(right, L("Karakterer"), "")
    Heads(right, RIGHT_COLS)
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, delta)
        ui.offset = (ui.offset or 0) - delta
        ns.RefreshUI()
    end)
    ui.charRows = {}
    for i = 1, CHAR_ROWS do
        local row = MakeBox("Button", right, COL_BTN, COL_BORDER)
        row:SetSize(342, 24)
        row:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -(54 + (i - 1) * 27))
        row.f = {}
        for k, c in ipairs(RIGHT_COLS) do
            row.f[k] = Field(row, c.x, c.w, c.j, k == 1 and "GameFontNormal" or "GameFontHighlight")
        end
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.full or d.name, C.ClassColor(d.class))
            if d.level > 0 then GameTooltip:AddLine("Level " .. d.level, 0.8, 0.8, 0.8) end
            if d.secs then
                GameTooltip:AddDoubleLine(L("Spilletid i alt"), ns.FormatPlayed(d.secs), 0.8, 0.8, 0.8, 1, 1, 1)
                if d.levelSecs and d.levelSecs > 0 then
                    GameTooltip:AddDoubleLine(L("På dette level"), ns.FormatPlayed(d.levelSecs), 0.8, 0.8, 0.8, 1, 1, 1)
                end
                GameTooltip:AddDoubleLine(L("Dødsfald"), string.format("%d  (%d PvE, %d PvP)", d.deaths, d.deaths - d.pvp, d.pvp),
                    0.8, 0.8, 0.8, 1, 0.5, 0.5)
                GameTooltip:AddDoubleLine("Deaths/hr", ns.FormatDPH(d.dph), 0.8, 0.8, 0.8, DphColor(d.dph))
                GameTooltip:AddDoubleLine(L("  PvE pr. time"), ns.FormatDPH(d.pveDph), 0.6, 0.6, 0.66, DphColor(d.pveDph))
                GameTooltip:AddDoubleLine(L("  PvP pr. time"), ns.FormatDPH(d.pvpDph), 0.6, 0.6, 0.66, 0.5, 0.7, 1)
                if d.online then
                    GameTooltip:AddLine(L("Online nu: tæller med"), 0.25, 0.88, 0.38)
                elseif d.at then
                    GameTooltip:AddLine(L("Målt ") .. C.FormatAgo(d.at), 0.6, 0.6, 0.66)
                end
            else
                GameTooltip:AddLine(L("Spilletid ikke kendt endnu"), 0.6, 0.6, 0.66)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.charRows[i] = row
    end
    ui.more = Txt(right, "GameFontHighlightSmall")
    ui.more:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 10)
    ui.more:SetWidth(338)
    ui.more:SetTextColor(0.5, 0.5, 0.56)
end

local function RefreshPage()
    local db = DB()
    local classOf = {}
    for _, s in ipairs(C.BuildStats()) do classOf[s.name] = s.class end
    if not ROSTER_SET[ui.sel or ""] then ui.sel = (db.me and ROSTER_SET[db.me]) and db.me or ROSTER[1] end

    local list = {}
    for _, name in ipairs(ROSTER) do list[#list + 1] = { name = name, t = ns.PlayedTotals(name) } end
    table.sort(list, function(a, b)
        local sa, sb = a.t.secs or -1, b.t.secs or -1
        if sa ~= sb then return sa > sb end
        return a.name < b.name
    end)
    ns.ShowFirst(ui.rows, #list)
    for i, d in ipairs(list) do
        local row, t = ui.rows[i], d.t
        row.data = d
        row.f[1]:SetText(t.secs and tostring(i) or "-")
        row.f[2]:SetText(Name(d.name) .. (d.name == db.me and L(" (dig)") or ""))
        row.f[2]:SetTextColor(C.ClassColor(classOf[d.name]))
        row.f[3]:SetText(ns.FormatPlayed(t.secs))
        row.f[4]:SetText(t.secs and (t.ratedPvp > 0 and ((t.rated - t.ratedPvp) .. "|cff80b0ff+" .. t.ratedPvp .. "|r") or tostring(t.rated)) or "-")
        row.f[5]:SetText(ns.FormatDPH(t.dph))
        row.f[5]:SetTextColor(DphColor(t.dph))
        row.f[6]:SetText(t.known > 0 and tostring(t.known) or "-")
        if d.name == ui.sel then
            row:SetBackdropColor(COL_SELECT[1], COL_SELECT[2], COL_SELECT[3], 1)
        elseif i == 1 and t.secs then
            row:SetBackdropColor(0.20, 0.17, 0.06, 1)
        else
            row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end

    local g = ns.GroupPlayed()
    local lines = {}
    if g.secs then
        lines[1] = string.format(L("|cffffd100Hele gruppen:|r %s  |cff888888(%s timer)|r"),
            ns.FormatPlayed(g.secs), math.floor(g.secs / 3600 + 0.5))
        lines[2] = string.format("|cffffd100Deaths/hr:|r %s  |cff888888(PvE %s, |r|cff80b0ffPvP %s|r|cff888888)|r", ns.FormatDPH(g.dph),
            ns.FormatDPH(g.pveDph), ns.FormatDPH(g.pvpDph))
        if g.topChar then
            local r, gg, b = C.ClassColor(g.topChar.class)
            lines[3] = string.format(L("|cffffd100Mest spillede karakter:|r |cff%02x%02x%02x%s|r  |cff888888(%s, %s)|r"),
                math.floor(r * 255), math.floor(gg * 255), math.floor(b * 255), g.topChar.full or g.topChar.name,
                Name(g.topFriend), ns.FormatPlayed(g.topChar.secs))
        end
        local rank = ns.DeathRateRanking()
        if #rank > 0 then
            lines[#lines + 1] = string.format(L("|cffffd100Flest deaths/hr:|r %s  |cffff8080%s|r"),
                Name(rank[1].name), ns.FormatDPH(rank[1].dph))
        end
    else
        lines[1] = L("|cff888888Ingen spilletid endnu. Den kommer, når I logger ind med den nye version.|r")
    end
    ui.total:SetText(table.concat(lines, "\n"))

    -- Højre: den valgte vens karakterer
    local sel = ui.sel
    local chars = sel and ns.PlayedChars(sel) or {}
    local st = sel and ns.PlayedTotals(sel)
    ui.rightHead:SetText(sel and Name(sel) or L("Karakterer"))
    ui.rightHead:SetTextColor(C.ClassColor(classOf[sel]))
    ui.rightSub:SetText(st and st.secs and (ns.FormatPlayed(st.secs) .. L(" i alt  -  ") .. ns.FormatDPH(st.dph) .. " deaths/hr") or "")
    local maxOffset = math.max(0, #chars - CHAR_ROWS)
    local offset = math.max(0, math.min(ui.offset or 0, maxOffset))
    ui.offset = offset
    for i, row in ipairs(ui.charRows) do
        local d = chars[offset + i]
        row.data = d
        if d then
            row.f[1]:SetText(d.full or d.name)
            row.f[1]:SetTextColor(C.ClassColor(d.class))
            row.f[2]:SetText(d.level > 0 and tostring(d.level) or "-")
            row.f[3]:SetText((d.online and d.secs) and ("|cff40e060" .. ns.FormatPlayed(d.secs) .. "|r") or ns.FormatPlayed(d.secs))
            row.f[4]:SetText(d.pvp > 0 and ((d.deaths - d.pvp) .. "|cff80b0ff+" .. d.pvp .. "|r") or tostring(d.deaths))
            row.f[5]:SetText(ns.FormatDPH(d.dph))
            row.f[5]:SetTextColor(DphColor(d.dph))
            row:Show()
        else
            row:Hide()
        end
    end
    if #chars == 0 then
        ui.more:SetText(sel and (Name(sel) .. L(" har ingen karakterer endnu.")) or "")
    elseif #chars > CHAR_ROWS then
        ui.more:SetText(string.format(L("Viser %d-%d af %d  -  rul med musehjulet"), offset + 1,
            math.min(offset + CHAR_ROWS, #chars), #chars))
    else
        ui.more:SetText(L("Grøn spilletid = online nu. Hold musen over en karakter for detaljer."))
    end
end

C.EXTRA_PAGES[17] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
pcall(frame.RegisterEvent, frame, "TIME_PLAYED_MSG")
pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, ...)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        -- Efter de andre login-ting (identitet og synk kommer efter 6 sekunder)
        C_Timer.After(8, ns.AskPlayed)
        C_Timer.NewTicker(RESEND, function()
            if session.base and DB().me then SendMine() end
        end)
    elseif event == "TIME_PLAYED_MSG" then
        ns.OnTimePlayed(...)
    elseif event == "PLAYER_LOGOUT" then
        StoreMine()
    end
end)
