local _, ns = ...
local L = ns.L

-- =============================================================================
-- Bande-baren (v0.20): en lille bjælke, der altid er på skærmen.
--   * Ét ikon pr. ven i klassefarve: lyser, når vennen er online, og er gråt, når vennen er
--     offline. Level står i hjørnet, og en tynd ring rundt om ikonet fyldes med XP'en i det
--     nuværende level (fuld og guld på max level).
--   * Hold musen over et ikon: karakter, level, zone, hvad vennen laver (dungeon, død for
--     nylig, ny loot ...) og dagens dødsfald. Klik åbner vennens karakterer i hovedvinduet.
--   * v0.21.1: kun venner, der er online, har et ikon. Den, der bærer Skammens hat, har en lille hat.
--   * Under ikonerne står de 5 seneste nyheder (levels, dødsfald, loot, trofæer, rare mobs og
--     dueller), det nyeste øverst. Musen over loot viser itemets tooltip.
--   * Træk for at flytte (med mindre den er låst), højreklik åbner indstillingerne.
-- Bygger kun på data, addonet allerede har og synker, så baren sender ingen beskeder.
-- db.settings.bar (false = skjult), barLocked, barTicker (false = uden ticker),
-- barPos = { point, relPoint, x, y }
-- =============================================================================

local C = ns.core
local GAME, Name = C.GAME, C.Name

local ICON, GAP, PAD = 24, 4, 4      -- ikonstørrelse, afstand og kant
local RING = 2                       -- XP-ringens tykkelse
local TICK_H = 14
local ROWS = 5                       -- v0.21.1: de seneste 5 nyheder står fast under ikonerne
local MIN_W = 300                    -- baren er mindst så bred, når nyhederne er med
local MAX_ITEMS = 12
local MAX_AGE = 86400                -- ticker: kun det seneste døgn
local ACTIVE_AGE = 1800              -- tooltip: "laver lige nu" = sidste halve time

local bar
local Bar = {}
ns.Bar = Bar

local function DB() return WastedCoastDB end
local function S() return DB().settings end

local function Ago(t)
    return C.FormatAgoShort and C.FormatAgoShort(t) or ""
end

-- Sat sammen, så teksten kun oversættes én gang
local function F(fmt, ...) return string.format(L(fmt), ...) end

-- Vennens klasse: den karakter med højest level
local function ClassOf(friend)
    local best, lvl
    for _, c in pairs((DB().friends[friend] and DB().friends[friend].chars) or {}) do
        if c.class and (not lvl or (c.level or 0) > lvl) then best, lvl = c.class, c.level or 0 end
    end
    return best
end

local function Who(friend, class)
    return C.ColorName(friend, class or ClassOf(friend))
end

-- =============================================================================
-- Ticker: det seneste nye fra de data, vi har. Hver linje = { t, key, text }
-- =============================================================================
function Bar.Items(now)
    local db = DB()
    now = now or time()
    local since = now - MAX_AGE
    local out = {}
    local function add(t, key, text, link)
        if t and t > since and t <= now + 60 and text then out[#out + 1] = { t = t, key = key, text = text, link = link } end
    end

    -- Dødsfald
    for _, ev in ipairs(db.events or {}) do
        local f = C.EventFriend(ev)
        if f and (ev.time or 0) > since then
            local killer = (ev.killer and ev.killer ~= "") and L(ev.killer) or L("Ukendt")
            local kl, lv = tonumber(ev.klvl), tonumber(ev.level)
            local text
            if ev.pvp == true then
                text = F("%s blev ganket af %s", Who(f, ev.class), killer)
            elseif kl and lv and kl > 0 and lv - kl >= 5 then
                text = F("%s døde til en level %d %s. Pinligt.", Who(f, ev.class), kl, killer)
            else
                text = F("%s døde til %s", Who(f, ev.class), killer)
            end
            add(ev.time, "d" .. tostring(ev.id or ev.time), text)
        end
    end

    -- Levels (kun dem, vi så ske, ikke gæt)
    for f, e in pairs(db.levelAt or {}) do
        if C.ROSTER_SET[f] and not e.g and e.l and e.l > 1 then
            local class
            for _, c in pairs((db.friends[f] and db.friends[f].chars) or {}) do
                if c.level == e.l then class = c.class end
            end
            local text = (e.l >= C.MAX_LEVEL) and F("%s ramte MAX LEVEL %d!", Who(f, class), e.l)
                or F("%s dingede %d", Who(f, class), e.l)
            add(e.t, "l" .. f .. e.l, text)
        end
    end

    -- Loot
    for _, ev in ipairs(db.loot or {}) do
        local f = (ev.friend and C.ROSTER_SET[ev.friend] and ev.friend) or C.FriendOfChar(ev.char)
        if f and (ev.time or 0) > since and ev.item and ev.name then
            -- v0.21: vundet på need/greed/disenchant står efter itemet
            local how = (ev.how == "need" or ev.how == "greed" or ev.how == "de") and C.HOW_LABEL and C.HOW_LABEL[ev.how]
            local tail = how and (" |cff9aa0a6(" .. how .. ")|r") or ""
            -- v0.21.1: itemets ikon foran linket, og musen over viser itemets tooltip
            local id = tonumber(ev.item:match("^item:(%d+)"))
            local icon = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
            local item = (icon and ("|T" .. tostring(icon) .. ":12:12:0:0|t ") or "") .. C.LootLink(ev)
            add(ev.time, "o" .. tostring(ev.id or ev.time), F("%s fik %s", Who(f, ev.class), item) .. tail, ev.item)
        end
    end

    -- Trofæer
    for f, list in pairs(db.ach or {}) do
        if C.ROSTER_SET[f] then
            for id, t in pairs(list) do
                local a = C.ACH_BY_ID[id]
                if a and type(t) == "number" then
                    add(t, "a" .. f .. id, F("%s låste |cffffd100%s|r op", Who(f), a.name))
                end
            end
        end
    end

    -- Rare mobs
    for _, r in ipairs(db.rareLog or {}) do
        if C.ROSTER_SET[r.friend] then
            add(r.t, "r" .. r.friend .. tostring(r.mob) .. tostring(r.t),
                F("%s dræbte rare mob %s", Who(r.friend), tostring(r.mob)))
        end
    end

    -- Dueller: hver duel kun én gang (begge venner kan have den)
    local duels = {}
    for f, list in pairs(db.duels or {}) do
        if C.ROSTER_SET[f] then
            for _, d in ipairs(list) do
                local key = "u" .. tostring(d.id or (f .. tostring(d.t)))
                if not duels[key] and d.t then
                    local text
                    if d.won then
                        text = F("%s vandt en duel mod %s", Who(f), d.of and Name(d.of) or tostring(d.opp or "?"))
                    elseif not d.of then
                        text = F("%s tabte en duel til %s", Who(f), tostring(d.opp or "?"))
                    end
                    if text then duels[key] = true add(d.t, key, text) end
                end
            end
        end
    end

    -- v0.22: stomi
    for _, e in ipairs((db.stomi and db.stomi.log) or {}) do
        if e.r == "y" and C.ROSTER_SET[e.to] and C.ROSTER_SET[e.from] then
            add(e.t, "s" .. tostring(e.id), F("%s fik |cffd9b38cstomi|r af %s", Who(e.to), Who(e.from)))
        end
    end

    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.key < b.key
    end)
    while #out > MAX_ITEMS do table.remove(out) end
    return out
end

-- Nyhedslinjerne: { text, item } pr. linje (højst ROWS). En stille dag giver én pladsholder.
function Bar.NewsLines(items)
    if #items == 0 then
        return { { text = "|cff888888" .. L("Stille på kysten. Nogen må gøre noget dumt snart.") .. "|r" } }
    end
    local out = {}
    for i = 1, math.min(ROWS, #items) do
        local it = items[i]
        out[i] = { text = it.text .. " |cff7a7a86(" .. Ago(it.t) .. ")|r", item = it }
    end
    return out
end

-- =============================================================================
-- Tooltip: hvad laver vennen?
-- =============================================================================
local function Latest(friend, now)
    local db = DB()
    local best
    local function seen(t, text) if t and now - t < ACTIVE_AGE and (not best or t > best.t) then best = { t = t, text = text } end end
    for _, ev in ipairs(db.events or {}) do
        if C.EventFriend(ev) == friend then
            seen(ev.time, F("Døde til %s", (ev.killer and ev.killer ~= "") and L(ev.killer) or L("Ukendt")))
        end
    end
    for _, ev in ipairs(db.loot or {}) do
        local f = (ev.friend and C.ROSTER_SET[ev.friend] and ev.friend) or C.FriendOfChar(ev.char)
        if f == friend and ev.item and ev.name then seen(ev.time, F("Fik %s", C.LootLink(ev))) end
    end
    local e = db.levelAt and db.levelAt[friend]
    if e and not e.g then seen(e.t, F("Dingede %d", e.l or 0)) end
    for _, r in ipairs(db.rareLog or {}) do
        if r.friend == friend then seen(r.t, F("Dræbte rare mob %s", tostring(r.mob))) end
    end
    return best
end

local function DeathsToday(friend, now)
    local start = now - ((tonumber(date("%H", now)) or 0) * 3600 + (tonumber(date("%M", now)) or 0) * 60 + (tonumber(date("%S", now)) or 0))
    local n = 0
    for _, ev in ipairs(DB().events or {}) do
        if (ev.time or 0) >= start and C.EventFriend(ev) == friend then n = n + 1 end
    end
    return n
end

-- Linjerne i tooltippen (til tests): { { venstre, højre?, r, g, b }, ... }
function Bar.TooltipLines(s, now)
    now = now or time()
    local lines = {}
    local function add(a, b, r, g, bl) lines[#lines + 1] = { a, b, r or 1, g or 1, bl or 1 } end
    local r, g, b = C.ClassColor(s.class)
    add(s.disp .. ((s.name == DB().me) and L(" (dig)") or ""), s.online and "|cff40e060Online|r" or "|cff888888Offline|r", r, g, b)
    if not s.class then
        add(L("Ikke set endnu"), nil, 0.6, 0.6, 0.66)
        return lines
    end
    add(string.format("%s  -  %s %s", s.charFull or s.char or "?", ns.LevelText(s.level, s.xp, "Level "), C.ClassName(s.class)))
    if s.online then
        local zone = (s.zone and s.zone ~= "") and s.zone or L("ukendt sted")
        add(L("Zone"), zone, 0.6, 0.6, 0.66)
        local doing
        if ns.IsInstanceZone and ns.IsInstanceZone(s.zone) then doing = L("I en dungeon") end
        local last = Latest(s.name, now)
        if last then doing = (doing and (doing .. ", ") or "") .. last.text .. " |cff888888(" .. Ago(last.t) .. ")|r" end
        add(L("Laver"), doing or L("Ude i verden. Intet farligt (endnu)"), 0.6, 0.6, 0.66)
    else
        add(L("Sidst set"), C.FormatAgo(s.seen) .. ((s.zone and s.zone ~= "") and (L(" i ") .. s.zone) or ""), 0.6, 0.6, 0.66)
    end
    local d = DeathsToday(s.name, now)
    add(L("Døde i dag"), d > 0 and ("|cffff6060" .. d .. "|r") or "0", 0.6, 0.6, 0.66)
    if ns.HatHolder and ns.HatHolder() == s.name then add(L("Bærer |cffffd100Skammens hat|r (døde sidst)"), nil, 1, 0.5, 0.5) end
    local st = ns.StomiHas and ns.StomiHas(s.name, now)
    if st then
        add(string.format(L("Har |cffd9b38cstomi|r (fra %s, %s tilbage)"), Name(st.from), ns.Stomi.Hours(ns.Stomi.Remaining(s.name, now))), nil, 0.85, 0.7, 0.55)
    end
    if s.chars and s.chars > 1 then add(L("Karakterer"), tostring(s.chars), 0.6, 0.6, 0.66) end
    add(" ")
    add(L("Klik: se vennens karakterer"), nil, 0.5, 0.5, 0.56)
    return lines
end

-- =============================================================================
-- XP-ringen: fire tynde kanter rundt om ikonet, der fyldes med uret fra øverste venstre hjørne
-- =============================================================================
local function MakeRing(btn)
    local ring = { track = {}, fill = {} }
    local outer = ICON + RING * 2
    for i = 1, 4 do
        local t = btn:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.75)
        ring.track[i] = t
        local f = btn:CreateTexture(nil, "ARTWORK")
        ring.fill[i] = f
    end
    -- Sporet: top, højre, bund, venstre
    local tr = ring.track
    tr[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)       tr[1]:SetSize(outer, RING)
    tr[2]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)     tr[2]:SetSize(RING, outer)
    tr[3]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0) tr[3]:SetSize(outer, RING)
    tr[4]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0) tr[4]:SetSize(RING, outer)
    btn.ring = ring
end

-- p = 0..1. Hver kant står for en fjerdedel.
local function SetRing(btn, p, r, g, b, a)
    local fill, outer = btn.ring.fill, ICON + RING * 2
    for i = 1, 4 do
        local part = math.max(0, math.min(1, p * 4 - (i - 1)))
        local f = fill[i]
        f:ClearAllPoints()
        if part <= 0 then
            f:Hide()
        else
            local len = math.max(1, math.floor(outer * part + 0.5))
            f:SetColorTexture(r, g, b, a or 1)
            if i == 1 then f:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0) f:SetSize(len, RING)
            elseif i == 2 then f:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0) f:SetSize(RING, len)
            elseif i == 3 then f:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0) f:SetSize(len, RING)
            else f:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0) f:SetSize(RING, len) end
            f:Show()
        end
    end
end

-- Ringens fyld: XP i levelet, fuld guld på max, intet når vi ikke ved det
function Bar.RingValue(level, xp)
    level = tonumber(level) or 0
    if level <= 0 then return 0, false end
    if level >= C.MAX_LEVEL then return 1, true end
    local pct = ns.XPPct(level, xp)
    return (pct or 0) / 100, false
end

local function SetIcon(tex, class)
    local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then
        tex:SetTexture(C.ICON_TEX)
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetColorTexture(0.16, 0.16, 0.2, 1)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- =============================================================================
-- Frames
-- =============================================================================
local function SavePos()
    local p, _, rp, x, y = bar:GetPoint(1)
    if p then S().barPos = { p, rp or p, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function Place()
    local pos = S().barPos
    bar:ClearAllPoints()
    if type(pos) == "table" and pos[1] then
        bar:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -24)
    end
end

local function StartMove()
    if S().barLocked then return end
    bar.moving = true
    bar:StartMoving()
    if GameTooltip then GameTooltip:Hide() end
end
local function StopMove()
    if not bar.moving then return end
    bar.moving = false
    bar:StopMovingOrSizing()
    SavePos()
end

local function OpenFriend(friend)
    if not ns.frame then return end
    ns.frame:Show()
    if ns.SelectTarget then ns.SelectTarget(friend) end
end

local function MakeIcon()
    local outer = ICON + RING * 2
    local btn = CreateFrame("Button", nil, bar)
    btn:SetSize(outer, outer)
    btn.friend, btn.stat, btn.online = false, false, false
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    MakeRing(btn)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", RING, -RING)
    btn.icon:SetSize(ICON, ICON)
    btn.level = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.level:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
    btn.level:SetJustifyH("RIGHT")
    btn.dot = btn:CreateTexture(nil, "OVERLAY")
    btn.dot:SetSize(5, 5)
    btn.dot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    btn.dot:SetColorTexture(0.25, 0.95, 0.35, 1)
    -- Skammens hat: en lille hat oven på ikonet hos den, der døde sidst
    btn.hat = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    btn.hat:SetSize(18, 18)
    btn.hat:SetPoint("CENTER", btn, "TOP", 0, 3)
    btn.hat:SetTexture(ns.HAT_ICON or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    btn.hat:Hide()
    -- v0.22: stomipose nederst til venstre hos den, der har stomi
    btn.stomi = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    btn.stomi:SetSize(14, 14)
    btn.stomi:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -3, -3)
    btn.stomi:SetTexture(ns.Stomi and ns.Stomi.ICON or "Interface\\Icons\\INV_Misc_Bag_10")
    btn.stomi:Hide()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", 0, 0)
    hl:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", 0, 0)
    hl:SetColorTexture(1, 0.85, 0.45, 0.18)
    hl:SetBlendMode("ADD")
    btn:SetScript("OnDragStart", StartMove)
    btn:SetScript("OnDragStop", StopMove)
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        elseif self.friend then
            OpenFriend(self.friend)
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if not self.stat or bar.moving or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        for n, l in ipairs(Bar.TooltipLines(self.stat)) do
            if n == 1 or l[2] then
                GameTooltip:AddDoubleLine(l[1], l[2] or "", l[3], l[4], l[5], 1, 1, 1)
            else
                GameTooltip:AddLine(l[1], l[3], l[4], l[5], true)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return btn
end

local function Layout()
    local n = #bar.icons
    local shown = 0
    for _, b in ipairs(bar.icons) do if b:IsShown() then shown = shown + 1 end end
    n = math.max(shown, 1)
    local outer = ICON + RING * 2
    local logoW = 22
    local w = PAD * 2 + logoW + GAP + n * outer + (n - 1) * GAP
    local tickerOn = S().barTicker ~= false
    if tickerOn then w = math.max(w, MIN_W) end
    local nRows = 0
    for _, r in ipairs(bar.rows) do if r:IsShown() then nRows = nRows + 1 end end
    local h = PAD * 2 + outer + (tickerOn and (nRows * TICK_H + 3) or 0)
    bar:SetSize(w, h)
    local i = 0
    for _, b in ipairs(bar.icons) do
        b:ClearAllPoints()
        if b:IsShown() then
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + logoW + GAP + i * (outer + GAP), -PAD)
            i = i + 1
        end
    end
    bar.news:SetShown(tickerOn)
    bar.news:SetSize(w - PAD * 2, math.max(1, nRows * TICK_H))
    for _, r in ipairs(bar.rows) do
        r:SetWidth(w - PAD * 2)
        r.fs:SetWidth(w - PAD * 2)
    end
end

-- Ikonerne: én pr. ven, der er online (v0.21.1), i vennelistens rækkefølge
function Bar.Refresh()
    if not bar or not DB() then return end
    local list = {}
    for _, s in ipairs(C.BuildStats()) do
        if s.online then list[#list + 1] = s end
    end
    for i = #bar.icons + 1, #list do bar.icons[i] = MakeIcon() end
    local online = 0
    local hat = ns.HatHolder and ns.HatHolder()
    for i, b in ipairs(bar.icons) do
        local s = list[i]
        b:SetShown(s ~= nil)
        if s then
            b.friend, b.stat = s.name, s
            SetIcon(b.icon, s.class)
            local r, g, bl = C.ClassColor(s.class)
            if s.online then
                online = online + 1
                if b.icon.SetDesaturated then b.icon:SetDesaturated(false) end
                b.icon:SetAlpha(1)
                b.level:SetTextColor(1, 1, 1)
                b.dot:Show()
            else
                if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
                b.icon:SetAlpha(0.4)
                b.level:SetTextColor(0.55, 0.55, 0.6)
                b.dot:Hide()
            end
            b.level:SetText((s.level and s.level > 0) and tostring(s.level) or "")
            local p, max = Bar.RingValue(s.level, s.xp)
            if max then
                SetRing(b, 1, C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3], s.online and 1 or 0.45)
            else
                SetRing(b, p, r, g, bl, s.online and 1 or 0.4)
            end
            b.online = s.online
            b.hat:SetShown(hat ~= nil and hat == s.name)
            b.stomi:SetShown(ns.StomiHas ~= nil and ns.StomiHas(s.name) ~= nil)
        end
    end
    bar.online = online
    bar.logoText:SetText(online > 0 and tostring(online) or "")
    Bar.UpdateTicker()
    Layout()
end

-- Nyhederne: faste linjer under ikonerne. Musen over en linje viser det hele, og for loot
-- itemets egen tooltip.
local function RowEnter(self)
    local it = self.line and self.line.item
    if not it or bar.moving or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if it.link and GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(it.text .. " |cff888888(" .. C.FormatAgo(it.t) .. ")|r", 0.8, 0.8, 0.84, true)
        GameTooltip:AddLine(L("Shift-klik for at sende linket i chatten"), 0.5, 0.5, 0.56)
    else
        GameTooltip:AddLine(it.text, 1, 1, 1, true)
        GameTooltip:AddLine(C.FormatAgo(it.t), 0.6, 0.6, 0.66)
    end
    GameTooltip:Show()
end
local function RowClick(self)
    local it = self.line and self.line.item
    if not (it and it.link and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink) then return end
    for _, ev in ipairs(DB().loot or {}) do
        if ev.item == it.link then ChatEdit_InsertLink(C.LootLink(ev)) return end
    end
end

local function MakeRow(i)
    local row = CreateFrame("Button", nil, bar.news)
    row.line = false
    row:SetHeight(TICK_H)
    row:SetPoint("TOPLEFT", bar.news, "TOPLEFT", 0, -(i - 1) * TICK_H)
    row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fs:SetWordWrap(false)
    row.fs:SetJustifyH("LEFT")
    row.fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 0.85, 0.45, 0.07)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", StartMove)
    row:SetScript("OnDragStop", StopMove)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", RowClick)
    return row
end

function Bar.UpdateTicker()
    if not bar then return end
    local lines = Bar.NewsLines(Bar.Items())
    for i = #bar.rows + 1, #lines do bar.rows[i] = MakeRow(i) end
    for i, row in ipairs(bar.rows) do
        local line = lines[i]
        row:SetShown(line ~= nil)
        row.line = line or false
        row.fs:SetText(line and line.text or "")
    end
end

function ns.BuildBar()
    if bar or not DB() then return end
    bar = C.MakeBox("Frame", UIParent, { C.COL_BG[1], C.COL_BG[2], C.COL_BG[3], 0.82 }, C.COL_BORDER)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartMove)
    bar:SetScript("OnDragStop", StopMove)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.OpenOptions then ns.OpenOptions() end
    end)
    bar.icons = {}
    bar.moving, bar.online = false, 0

    -- Logoet: klik åbner hovedvinduet. Tallet = venner online.
    local logo = CreateFrame("Button", nil, bar)
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -PAD - RING - 1)
    logo:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    logo:RegisterForDrag("LeftButton")
    local lt = logo:CreateTexture(nil, "ARTWORK")
    lt:SetAllPoints(logo)
    lt:SetTexture(ns.LOGO)
    bar.logoText = logo:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    bar.logoText:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", 2, -2)
    bar.logoText:SetTextColor(0.4, 1, 0.5)
    logo:SetScript("OnDragStart", StartMove)
    logo:SetScript("OnDragStop", StopMove)
    logo:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        elseif ns.frame then
            ns.frame:SetShown(not ns.frame:IsShown())
        end
    end)
    logo:SetScript("OnEnter", function(self)
        if bar.moving or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Wasted Coast Forever", C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3])
        GameTooltip:AddLine(string.format(L("%d af %d venner online"), bar.online or 0, #C.ROSTER), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("Klik: åbn/luk vinduet"), 0.7, 0.7, 0.76)
        GameTooltip:AddLine(L("Højreklik: indstillinger"), 0.7, 0.7, 0.76)
        GameTooltip:AddLine(S().barLocked and L("Baren er låst (lås op i indstillingerne)") or L("Træk: flyt baren"), 0.7, 0.7, 0.76)
        GameTooltip:Show()
    end)
    logo:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Nyhederne: de seneste 5 begivenheder under ikonerne
    bar.news = CreateFrame("Frame", nil, bar)
    bar.news:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -(PAD + ICON + RING * 2 + 3))
    bar.rows = {}

    Place()
    ns.barFrame = bar
    bar:SetShown(S().bar ~= false)
    Bar.Refresh()
end

-- =============================================================================
-- Indstillinger og /wc4ever bar
-- =============================================================================
function ns.SetBarShown(v)
    S().bar = v and true or false
    if bar then bar:SetShown(v) if v then Bar.Refresh() end end
end

function ns.SetBarLocked(v)
    S().barLocked = v and true or nil
    if not v then return end
    StopMove()
end

function ns.SetBarTicker(v)
    S().barTicker = v and true or false
    if bar then Layout() end
end

function ns.BarSlash(arg)
    arg = arg or ""
    local P = C.Print
    if arg == "lås" or arg == "laas" or arg == "lock" or arg == "unlock" then
        ns.SetBarLocked(not S().barLocked)
        P(S().barLocked and L("Bande-baren er låst.") or L("Bande-baren kan flyttes igen."))
    elseif arg == "ticker" or arg == "nyheder" or arg == "news" then
        ns.SetBarTicker(S().barTicker == false)
        P(L("Nyhederne på baren er ") .. ((S().barTicker ~= false) and L("slået til") or L("slået fra")) .. ".")
    elseif arg == "nulstil" or arg == "reset" then
        S().barPos = nil
        if bar then Place() end
        ns.SetBarShown(true)
        P(L("Bande-baren står øverst på skærmen igen."))
    else
        ns.SetBarShown(S().bar == false)
        P(L("Bande-baren er ") .. ((S().bar ~= false) and L("vist") or L("skjult")) .. ".")
    end
    if ns.options and ns.options:IsShown() and ns.RefreshOptions then ns.RefreshOptions() end
end

-- Opdater, når der sker noget (RefreshUI kaldes ved alle nye data), men højst én gang i sekundet
do
    local dirty = true
    local orig = ns.RefreshUI
    if orig then
        ns.RefreshUI = function(...)
            dirty = true
            return orig(...)
        end
    end
    function Bar.MarkDirty() dirty = true end
    local n = 0
    local function Tick()
        n = n + 1
        if not bar or not bar:IsShown() then return end
        -- Online-status ændrer sig også, uden at der kommer nye data (en ven holder op med at svare)
        if dirty or n % 15 == 0 then
            dirty = false
            Bar.Refresh()
        end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, Tick) end
    Bar.Tick = Tick
end
