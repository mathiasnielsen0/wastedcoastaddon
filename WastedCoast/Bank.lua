local _, ns = ...

-- =============================================================================
-- Guild bank og repair (v0.11): hvem har taget mest fra guild banken, hvem har lagt mest
-- i den, og hvem bruger flest penge på at reparere.
-- Hver ven måler kun sine egne transaktioner (spillets bank-log er kort og har kun
-- omtrentlige tider, så den er ikke til at tælle sammen uden dubletter). Totalerne sendes
-- som én lille besked, når de ændrer sig (samlet efter et bank-besøg) og ved synk.
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
--
-- db.bank[ven] = {
--   dg, wg   = guld lagt ind / taget ud (kobber)
--   di, wi   = antal ting lagt ind / taget ud
--   dv, wv   = tingenes værdi hos en vendor (kobber)
--   rep      = repair i alt (kobber), grep = heraf betalt af guild banken
--   nrep     = antal reparationer, maxrep = største enkelte regning
--   items    = { [itemID] = { d, w } }  (kun dine egne)
--   tw, td   = "itemID:antal" for vennens mest hævede / indsatte ting (fra netværket)
--   since, t = første og seneste måling
-- }
-- Besked: BK;ven;t;dg;wg;di;wi;dv;wv;rep;grep;nrep;maxrep;tw;td;since
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Name = C.Name
local Print = C.Print

local FIELDS = { "dg", "wg", "di", "wi", "dv", "wv", "rep", "grep", "nrep", "maxrep" }
local BIG_GOLD = 50 * 10000     -- så meget guld ud/ind giver en besked i chatten hos de andre
local BIG_REPAIR = 15 * 10000   -- så stor en repair-regning giver en besked

local function DB()
    local db = WastedCoastDB
    db.bank = db.bank or {}
    return db
end

local function Entry(friend, create)
    local db = DB()
    local e = db.bank[friend]
    if not e and create then
        e = { since = time() }
        for _, k in ipairs(FIELDS) do e[k] = 0 end
        db.bank[friend] = e
    end
    return e
end

-- Kort guldtekst til tabeller: 1.2k g, 35 g, 4g 20s, 45s
local function Money(copper)
    copper = math.floor(copper or 0)
    local neg = copper < 0
    copper = math.abs(copper)
    local g = copper / 10000
    local s
    if g >= 10000 then
        s = string.format("%.0fk g", g / 1000)
    elseif g >= 1000 then
        s = string.format("%.1fk g", g / 1000)
    elseif g >= 100 then
        s = string.format("%d g", math.floor(g))
    elseif g >= 1 then
        local silver = math.floor((copper % 10000) / 100)
        s = silver > 0 and string.format("%dg %ds", math.floor(g), silver) or string.format("%d g", math.floor(g))
    else
        s = string.format("%ds", math.floor(copper / 100))
    end
    return (neg and "-" or "") .. s
end
ns.BankMoney = Money

-- Den ting, der er hævet (k = "w") eller indsat (k = "d") flest af: id, antal
local function TopItem(friend, k)
    local e = Entry(friend)
    if not e then return nil end
    if e.items then
        local best, n = nil, 0
        for id, c in pairs(e.items) do
            if (c[k] or 0) > n or ((c[k] or 0) == n and best and id < best) then best, n = id, c[k] or 0 end
        end
        if best and n > 0 then return best, n end
        return nil
    end
    local s = e["t" .. k]
    local id, n = (s or ""):match("^(%d+):(%d+)$")
    if id then return tonumber(id), tonumber(n) end
end
ns.BankTopItem = TopItem

local function ItemName(id)
    local name, _, q = C.GAME.ItemInfo(id)
    if not name then return "ting #" .. id end
    local hex = q and C.QUALITY_HEX and C.QUALITY_HEX[q]
    return hex and ("|cff" .. hex .. name .. "|r") or name
end

-- =============================================================================
-- Synk
-- =============================================================================
local function Serialize(friend)
    local e = Entry(friend)
    if not e then return nil end
    local parts = { "BK", friend, e.t or 0 }
    for _, k in ipairs(FIELDS) do parts[#parts + 1] = math.floor(e[k] or 0) end
    local wid, wn = TopItem(friend, "w")
    local did, dn = TopItem(friend, "d")
    parts[#parts + 1] = wid and (wid .. ":" .. wn) or ""
    parts[#parts + 1] = did and (did .. ":" .. dn) or ""
    parts[#parts + 1] = e.since or 0
    return table.concat(parts, ";")
end

function ns.SendBank()
    local db = DB()
    local e = db.me and Entry(db.me)
    if not e or e.demo or not e.t then return end
    C.Send(Serialize(db.me))
end

-- Mange flytninger i træk (et helt bank-besøg) bliver til én besked
local sendPending = false
local function ScheduleSend()
    if sendPending then return end
    sendPending = true
    C_Timer.After(20, function()
        sendPending = false
        ns.SendBank()
    end)
end

function ns.OnBankMessage(t)
    local db = DB()
    local friend, at = t[2], tonumber(t[3])
    if not ROSTER_SET[friend] or friend == db.me or not at then return end
    local old = Entry(friend)
    if old and not old.demo and at < (old.t or 0) then return end
    local e = { t = at, since = tonumber(t[16]) or at }
    for i, k in ipairs(FIELDS) do
        local v = tonumber(t[3 + i])
        if not v or v < 0 then return end
        e[k] = v
    end
    e.tw = (t[14] or ""):match("^%d+:%d+$")
    e.td = (t[15] or ""):match("^%d+:%d+$")
    -- Friske, store bevægelser bliver nævnt i chatten
    if old and not old.demo and db.settings.announce and (time() - at) < 300 then
        local took = e.wg - (old.wg or 0)
        local gave = e.dg - (old.dg or 0)
        local rep = e.rep - (old.rep or 0)
        if took >= BIG_GOLD then
            Print(string.format("%s tog lige |cffffd100%s|r fra guild banken.", Name(friend), Money(took)))
        elseif gave >= BIG_GOLD then
            Print(string.format("%s lagde lige |cffffd100%s|r i guild banken. Flot!", Name(friend), Money(gave)))
        end
        if rep >= BIG_REPAIR then
            Print(string.format("%s betalte lige |cffffd100%s|r for at reparere. Av.", Name(friend), Money(rep)))
        end
    end
    db.bank[friend] = e
    if ns.RefreshUI then ns.RefreshUI() end
end

-- =============================================================================
-- Måling: guld og ting i guild banken, og repair hos en vendor
-- =============================================================================
local function Changed()
    local e = Entry(DB().me)
    if e then e.t = time() end
    ScheduleSend()
    if ns.RefreshUI then ns.RefreshUI() end
end

local function Mine()
    local db = DB()
    if not db.me then return nil end
    local e = Entry(db.me, true)
    if e.demo then
        db.bank[db.me] = nil
        e = Entry(db.me, true)
    end
    return e
end

function ns.RecordBankGold(kind, copper)
    local e = Mine()
    if not e or not copper or copper <= 0 then return end
    if kind == "d" then e.dg = e.dg + copper else e.wg = e.wg + copper end
    Changed()
end

function ns.RecordBankItem(kind, id, count)
    local e = Mine()
    if not e or not id or not count or count <= 0 then return end
    e.items = e.items or {}
    local c = e.items[id]
    if not c then c = { d = 0, w = 0 }; e.items[id] = c end
    c[kind] = (c[kind] or 0) + count
    local price = select(11, C.GAME.ItemInfo(id))
    local value = (tonumber(price) or 0) * count
    if kind == "d" then
        e.di, e.dv = e.di + count, e.dv + value
    else
        e.wi, e.wv = e.wi + count, e.wv + value
    end
    Changed()
end

function ns.RecordRepair(copper, guild)
    local e = Mine()
    if not e or not copper or copper <= 0 then return end
    e.rep = e.rep + copper
    if guild then e.grep = e.grep + copper end
    e.nrep = e.nrep + 1
    if copper > (e.maxrep or 0) then e.maxrep = copper end
    Changed()
end

local watch = {
    bankOpen = false, merchantOpen = false,
    lastMoney = nil,
    pendingGold = nil,     -- { k = "d"/"w", a = kobber, at = GetTime() }
    repairCost = 0, spent = 0, guildRepairAt = nil, repairPending = false,
    snap = nil, diffSince = nil, slotsAt = -100, bagPending = false,
}
ns.bankWatch = watch

-- Antal af hver ting i taskerne og på kroppen
local function ItemAt(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        id = id or (link and tonumber(link:match("item:(%d+)")))
        return id, count
    end
end

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

local function Snapshot()
    local s = {}
    local bags = (NUM_BAG_SLOTS or 4) + ((NUM_REAGENTBAG_SLOTS or 0) > 0 and 1 or 0)
    for bag = 0, bags do
        for slot = 1, NumSlots(bag) do
            local id, count = ItemAt(bag, slot)
            if id then s[id] = (s[id] or 0) + (count or 1) end
        end
    end
    if GetInventoryItemID then
        for slot = 1, 19 do
            local id = GetInventoryItemID("player", slot)
            if id then s[id] = (s[id] or 0) + 1 end
        end
    end
    return s
end

-- Forskellen mellem to optællinger: { [id] = +n (kommet til) / -n (forsvundet) }
local function Diff(a, b)
    local d, any = {}, false
    for id, n in pairs(b) do
        local x = n - (a[id] or 0)
        if x ~= 0 then d[id], any = x, true end
    end
    for id, n in pairs(a) do
        if not b[id] then d[id], any = -n, true end
    end
    return any and d or nil
end

-- Ting tælles kun, når guild banken samtidig har meldt en ændring, så mad, du spiser,
-- eller gear, du skifter, mens banken er åben, ikke tæller med.
local function CheckBags()
    watch.bagPending = false
    if not watch.snap then return end
    local now = Snapshot()
    local d = Diff(watch.snap, now)
    if not d then
        watch.diffSince = nil
        return
    end
    local t = GetTime()
    watch.diffSince = watch.diffSince or t
    if math.abs(t - watch.slotsAt) < 4 then
        for id, n in pairs(d) do
            if n < 0 then ns.RecordBankItem("d", id, -n) else ns.RecordBankItem("w", id, n) end
        end
    elseif t - watch.diffSince < 3 then
        -- Bankens melding kan komme lidt efter taskens: prøv igen om lidt
        watch.bagPending = true
        C_Timer.After(1, CheckBags)
        return
    end
    watch.snap, watch.diffSince = now, nil
end

local function ScheduleBags()
    if watch.bagPending or not watch.bankOpen then return end
    watch.bagPending = true
    C_Timer.After(0.5, CheckBags)
end

local function RepairCost()
    local cost = GetRepairAllCost and GetRepairAllCost()
    return tonumber(cost) or 0
end

local function CheckRepair()
    watch.repairPending = false
    if not watch.merchantOpen then return end
    local cost = RepairCost()
    local drop = watch.repairCost - cost
    if drop > 0 then
        local guild = watch.guildRepairAt and (GetTime() - watch.guildRepairAt) < 5
        -- Uden guildens penge skal du selv have betalt (ellers var det fx en solgt, slidt ting)
        if guild or watch.spent >= drop then ns.RecordRepair(drop, guild) end
        watch.guildRepairAt = nil
    end
    watch.repairCost, watch.spent = cost, 0
end

local function ScheduleRepair()
    if watch.repairPending or not watch.merchantOpen then return end
    watch.repairPending = true
    C_Timer.After(0.4, CheckRepair)
end

local function OnMoney()
    local money = GetMoney()
    local delta = money - (watch.lastMoney or money)
    watch.lastMoney = money
    local p = watch.pendingGold
    if p and GetTime() - p.at < 15 then
        if (p.k == "d" and delta == -p.a) or (p.k == "w" and delta == p.a) then
            watch.pendingGold = nil
            ns.RecordBankGold(p.k, p.a)
        end
    elseif p then
        watch.pendingGold = nil
    end
    if watch.merchantOpen then
        if delta < 0 then watch.spent = watch.spent + (-delta) end
        ScheduleRepair()
    end
end

local function BankOpened()
    watch.bankOpen = true
    watch.snap, watch.diffSince = Snapshot(), nil
end

local function BankClosed()
    if watch.bankOpen and watch.snap then CheckBags() end
    watch.bankOpen, watch.snap = false, nil
end

local function MerchantOpened()
    watch.merchantOpen = true
    watch.repairCost, watch.spent, watch.guildRepairAt = RepairCost(), 0, nil
end

local function MerchantClosed()
    if watch.merchantOpen then CheckRepair() end
    watch.merchantOpen = false
end

-- Spillets egne knapper (og andre addons) kalder disse, så vi lytter med
if hooksecurefunc then
    if DepositGuildBankMoney then
        hooksecurefunc("DepositGuildBankMoney", function(copper)
            watch.pendingGold = { k = "d", a = tonumber(copper) or 0, at = GetTime() }
        end)
    end
    if WithdrawGuildBankMoney then
        hooksecurefunc("WithdrawGuildBankMoney", function(copper)
            watch.pendingGold = { k = "w", a = tonumber(copper) or 0, at = GetTime() }
        end)
    end
    if RepairAllItems then
        hooksecurefunc("RepairAllItems", function(guild)
            watch.guildRepairAt = guild and GetTime() or nil
            ScheduleRepair()
        end)
    end
end

-- Interaktionstyper på den moderne motor (Forever), hvor de gamle åbne/luk-events er væk
local INTERACT_GUILDBANK, INTERACT_MERCHANT = 10, 5
if Enum and Enum.PlayerInteractionType then
    INTERACT_GUILDBANK = Enum.PlayerInteractionType.GuildBanker or INTERACT_GUILDBANK
    INTERACT_MERCHANT = Enum.PlayerInteractionType.Merchant or INTERACT_MERCHANT
end

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_MONEY", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED",
                      "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE",
                      "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_LOGIN" }) do
    pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event, arg)
    if not WastedCoastDB then return end
    if event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "PLAYER_LOGIN" then
        watch.lastMoney = GetMoney()
    elseif event == "GUILDBANKFRAME_OPENED" then
        BankOpened()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        BankClosed()
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        watch.slotsAt = GetTime()
        ScheduleBags()
    elseif event == "BAG_UPDATE" then
        ScheduleBags()
    elseif event == "MERCHANT_SHOW" then
        MerchantOpened()
    elseif event == "MERCHANT_CLOSED" then
        MerchantClosed()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        ScheduleRepair()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if arg == INTERACT_GUILDBANK and not watch.bankOpen then BankOpened() end
        if arg == INTERACT_MERCHANT and not watch.merchantOpen then MerchantOpened() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg == INTERACT_GUILDBANK then BankClosed() end
        if arg == INTERACT_MERCHANT then MerchantClosed() end
    end
end)

-- =============================================================================
-- UI: side 15 - guild bank og repair (under Rangliste)
-- =============================================================================
local Txt, MakeBox, Field, MakeButton = C.Txt, C.MakeBox, C.Field, C.MakeButton
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN, COL_SELECT = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN, C.COL_SELECT
local ui = {}
ns.bankUI = ui

local SORTS = {
    { key = "took", label = "Taget",  title = "taget mest" },
    { key = "gave", label = "Lagt",   title = "lagt mest" },
    { key = "net",  label = "Netto",  title = "bedst for banken" },
}

local BANK_COLS = {
    { x = 4,   w = 18, j = "CENTER", label = "#" },
    { x = 24,  w = 86, j = "LEFT",   label = "Ven" },
    { x = 112, w = 74, j = "RIGHT",  label = "Lagt ind" },
    { x = 190, w = 74, j = "RIGHT",  label = "Taget ud" },
    { x = 268, w = 70, j = "RIGHT",  label = "Netto" },
}
local REP_COLS = {
    { x = 4,   w = 18, j = "CENTER", label = "#" },
    { x = 24,  w = 86, j = "LEFT",   label = "Ven" },
    { x = 112, w = 70, j = "RIGHT",  label = "Repair" },
    { x = 186, w = 62, j = "RIGHT",  label = "Guild" },
    { x = 252, w = 30, j = "RIGHT",  label = "Antal" },
    { x = 286, w = 52, j = "RIGHT",  label = "Største" },
}

-- Ind/ud i alt = guld + tingenes vendor-værdi
local function Totals(friend)
    local e = Entry(friend)
    if not e then return nil end
    local gave = (e.dg or 0) + (e.dv or 0)
    local took = (e.wg or 0) + (e.wv or 0)
    return { e = e, gave = gave, took = took, net = gave - took,
             any = (e.dg + e.wg + e.di + e.wi) > 0, anyRep = (e.nrep or 0) > 0 }
end

local function Header(box, text, sub)
    local h = Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(text)
    h:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    if sub then
        local s = Txt(box, "GameFontHighlightSmall")
        s:SetPoint("LEFT", h, "RIGHT", 8, -1)
        s:SetTextColor(0.5, 0.5, 0.56)
        s:SetText(sub)
        box.sub = s
    end
    return h
end

local function ColumnLabels(box, cols)
    for _, c in ipairs(cols) do
        local fs = Txt(box, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + c.x, -38)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.j)
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(c.label)
    end
end

local function Rows(box, cols, onEnter)
    local rows = {}
    for i = 1, ns.MAX_MEMBERS do
        local row = MakeBox("Button", box, COL_BTN, COL_BORDER)
        row:SetSize(342, 24)
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(54 + (i - 1) * 27))
        row.f = {}
        for k, c in ipairs(cols) do
            row.f[k] = Field(row, c.x, c.w, c.j, k == 2 and "GameFontNormal" or "GameFontHighlight")
        end
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            onEnter(self.data)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        rows[i] = row
    end
    return rows
end

local function Facts(box, note)
    local fs = Txt(box, "GameFontHighlight")
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -(54 + ns.MAX_MEMBERS * 27 + 6))
    fs:SetWidth(338)
    fs:SetSpacing(4)
    fs:SetWordWrap(true)
    local n = Txt(box, "GameFontHighlightSmall")
    n:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
    n:SetWidth(338)
    n:SetTextColor(0.5, 0.5, 0.56)
    n:SetText(note)
    return fs
end

local function Line(label, value, r, g, b)
    GameTooltip:AddDoubleLine(label, value, 0.8, 0.8, 0.8, r or 1, g or 1, b or 1)
end

local function BankTooltip(d)
    GameTooltip:AddLine(Name(d.name), 1, 1, 1)
    local e = d.t and d.t.e
    if not d.t or not d.t.any then
        GameTooltip:AddLine("Ingen guild bank-handler endnu", 0.6, 0.6, 0.66)
        return
    end
    Line("Guld lagt ind", Money(e.dg))
    Line("Guld taget ud", Money(e.wg))
    Line("Ting lagt ind", string.format("%d  (%s)", e.di, Money(e.dv)))
    Line("Ting taget ud", string.format("%d  (%s)", e.wi, Money(e.wv)))
    local wid, wn = TopItem(d.name, "w")
    local did, dn = TopItem(d.name, "d")
    if wid or did then GameTooltip:AddLine(" ") end
    if wid then Line("Tager mest", ItemName(wid) .. " x" .. wn) end
    if did then Line("Lægger mest", ItemName(did) .. " x" .. dn) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Tingenes værdi er vendor-prisen. Målt siden " .. date("%d/%m/%Y", e.since or time()) .. ".", 0.5, 0.5, 0.56, true)
end

local function RepairTooltip(d)
    GameTooltip:AddLine(Name(d.name), 1, 1, 1)
    local e = d.t and d.t.e
    if not d.t or not d.t.anyRep then
        GameTooltip:AddLine("Ingen reparationer endnu", 0.6, 0.6, 0.66)
        return
    end
    Line("Repair i alt", Money(e.rep))
    Line("Selv betalt", Money(e.rep - e.grep))
    Line("Betalt af guild banken", Money(e.grep), 0.4, 0.9, 0.5)
    Line("Reparationer", tostring(e.nrep))
    Line("Snit pr. gang", Money(e.rep / math.max(1, e.nrep)))
    Line("Største regning", Money(e.maxrep), 1, 0.45, 0.45)
end

local function BuildPage(page)
    ns.bankSort = ns.bankSort or "took"
    local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(362)
    Header(left, "Guild bank")
    ui.sortBtns = {}
    for i = #SORTS, 1, -1 do
        local s = SORTS[i]
        local b = MakeButton(left, 52, 20, s.label, function()
            ns.bankSort = s.key
            ns.RefreshUI()
        end)
        b.text:SetFontObject(GameFontHighlightSmall)
        b:SetPoint("TOPRIGHT", left, "TOPRIGHT", -10 - (#SORTS - i) * 56, -9)
        b.key = s.key
        ui.sortBtns[i] = b
    end
    ColumnLabels(left, BANK_COLS)
    ui.bankRows = Rows(left, BANK_COLS, BankTooltip)
    ui.bankFacts = Facts(left, "Lagt ind og taget ud = guld + tingenes vendor-værdi. Hver ven måler sine egne handler i guild banken. Hold musen over en ven for detaljer.")

    local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(362)
    Header(right, "Repair", "hvem slider mest på gearet")
    ColumnLabels(right, REP_COLS)
    ui.repRows = Rows(right, REP_COLS, RepairTooltip)
    ui.repFacts = Facts(right, "Guild = betalt af guild banken (Repair med guildens penge). Tæller alle reparationer hos en vendor.")
end

local function Shade(row, first, me, any)
    if first and any then
        row:SetBackdropColor(0.20, 0.17, 0.06, 1)
    elseif me then
        row:SetBackdropColor(0.13, 0.17, 0.26, 1)
    else
        row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
    end
end

local function Best(list, f)
    local best, v = nil, 0
    for _, d in ipairs(list) do
        local x = d.t and f(d.t) or 0
        if x > v then best, v = d, x end
    end
    return best, v
end

local function RefreshPage()
    local db = DB()
    local classOf = {}
    for _, s in ipairs(C.BuildStats()) do classOf[s.name] = s.class end
    local function Colored(name) return C.ColorName(name, classOf[name]) end

    for i, b in ipairs(ui.sortBtns) do
        local c = (b.key == ns.bankSort) and COL_SELECT or COL_BTN
        b:SetBackdropColor(c[1], c[2], c[3], 1)
    end

    local list = {}
    for _, name in ipairs(ROSTER) do list[#list + 1] = { name = name, t = Totals(name) } end

    -- Guild bank
    local key = ns.bankSort or "took"
    local bank = {}
    for i, d in ipairs(list) do bank[i] = d end
    table.sort(bank, function(a, b)
        local aa, ba = (a.t and a.t.any) and true or false, (b.t and b.t.any) and true or false
        if aa ~= ba then return aa end
        local av, bv = aa and a.t[key] or 0, ba and b.t[key] or 0
        if av ~= bv then return av > bv end
        return a.name < b.name
    end)
    ns.ShowFirst(ui.bankRows, #bank)
    for i, d in ipairs(bank) do
        local row, t = ui.bankRows[i], d.t
        local any = t and t.any
        row.data = d
        local r, g, b = C.ClassColor(classOf[d.name])
        row.f[1]:SetText(any and tostring(i) or "-")
        row.f[2]:SetText(Name(d.name) .. (d.name == db.me and " (dig)" or ""))
        row.f[2]:SetTextColor(r, g, b)
        row.f[3]:SetText(any and Money(t.gave) or "-")
        row.f[4]:SetText(any and Money(t.took) or "-")
        if any then
            local col = t.net > 0 and "66e080" or (t.net < 0 and "ff7070" or "cccccc")
            row.f[5]:SetText("|cff" .. col .. (t.net > 0 and "+" or "") .. Money(t.net) .. "|r")
        else
            row.f[5]:SetText("-")
        end
        Shade(row, i == 1, d.name == db.me, any)
    end

    local facts = {}
    local robber, took = Best(list, function(t) return t.any and t.took or 0 end)
    if robber then facts[#facts + 1] = string.format("|cffffd100Bankrøveren:|r %s (%s taget)", Colored(robber.name), Money(took)) end
    local friend, net = Best(list, function(t) return t.any and t.net or 0 end)
    if friend then facts[#facts + 1] = string.format("|cffffd100Bankens bedste ven:|r %s (+%s)", Colored(friend.name), Money(net)) end
    local leech, neg = Best(list, function(t) return t.any and -t.net or 0 end)
    if leech and leech ~= robber then facts[#facts + 1] = string.format("|cffffd100Snylteren:|r %s (%s i minus)", Colored(leech.name), Money(neg)) end
    local fav, favN, favWho = nil, 0, nil
    for _, d in ipairs(list) do
        local id, n = TopItem(d.name, "w")
        if id and n > favN then fav, favN, favWho = id, n, d.name end
    end
    if fav then facts[#facts + 1] = string.format("|cffffd100Mest hævet:|r %s x%d (%s)", ItemName(fav), favN, Colored(favWho)) end
    if #facts == 0 then facts[1] = "|cff888888Ingen har været i guild banken med addonet endnu.|r" end
    ui.bankFacts:SetText(table.concat(facts, "\n"))

    -- Repair
    local rep = {}
    for i, d in ipairs(list) do rep[i] = d end
    table.sort(rep, function(a, b)
        local av, bv = (a.t and a.t.e.rep) or 0, (b.t and b.t.e.rep) or 0
        if av ~= bv then return av > bv end
        return a.name < b.name
    end)
    ns.ShowFirst(ui.repRows, #rep)
    for i, d in ipairs(rep) do
        local row, t = ui.repRows[i], d.t
        local any = t and t.anyRep
        local e = t and t.e
        row.data = d
        local r, g, b = C.ClassColor(classOf[d.name])
        row.f[1]:SetText(any and tostring(i) or "-")
        row.f[2]:SetText(Name(d.name) .. (d.name == db.me and " (dig)" or ""))
        row.f[2]:SetTextColor(r, g, b)
        row.f[3]:SetText(any and Money(e.rep) or "-")
        row.f[4]:SetText((any and e.grep > 0) and ("|cff66e080" .. Money(e.grep) .. "|r") or "-")
        row.f[5]:SetText(any and tostring(e.nrep) or "-")
        row.f[6]:SetText(any and ("|cffff7070" .. Money(e.maxrep) .. "|r") or "-")
        Shade(row, i == 1, d.name == db.me, any)
    end

    facts = {}
    local rusty, rv = Best(list, function(t) return t.e.rep or 0 end)
    if rusty then facts[#facts + 1] = string.format("|cffffd100Rustbunken:|r %s (%s i repair)", Colored(rusty.name), Money(rv)) end
    local sponsored, sv = Best(list, function(t) return t.e.grep or 0 end)
    if sponsored then facts[#facts + 1] = string.format("|cffffd100Guildens regning:|r %s har fået %s betalt", Colored(sponsored.name), Money(sv)) end
    local ouch, ov = Best(list, function(t) return t.e.maxrep or 0 end)
    if ouch then facts[#facts + 1] = string.format("|cffffd100Største regning:|r %s (%s på én gang)", Colored(ouch.name), Money(ov)) end
    local total = 0
    for _, d in ipairs(list) do total = total + ((d.t and d.t.e.rep) or 0) end
    if total > 0 then facts[#facts + 1] = string.format("|cffffd100Samlet:|r I har brugt %s på repair", Money(total)) end
    if #facts == 0 then facts[1] = "|cff888888Ingen har repareret med addonet endnu.|r" end
    ui.repFacts:SetText(table.concat(facts, "\n"))
end

C.EXTRA_PAGES[15] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Demo og nulstilling
-- =============================================================================
local DEMO_ITEMS = { 22829, 13446, 21877, 22445, 2589, 4306, 28101, 22832 }

function ns.MakeBankDemo()
    local db = DB()
    local now = time()
    for _, name in ipairs(ROSTER) do
        if name ~= db.me and math.random() < 0.9 then
            local g = 10000
            local e = {
                demo = true, t = now - math.random(60, 300000), since = now - 30 * 86400,
                dg = math.random(0, 400) * g, wg = math.random(0, 400) * g,
                di = math.random(0, 120), wi = math.random(0, 120),
                rep = math.random(5, 300) * g, nrep = math.random(3, 60),
            }
            e.dv, e.wv = e.di * math.random(10, 300) * 100, e.wi * math.random(10, 300) * 100
            e.grep = math.floor(e.rep * math.random(0, 60) / 100)
            e.maxrep = math.min(e.rep, math.random(2, 35) * g)
            e.tw = DEMO_ITEMS[math.random(#DEMO_ITEMS)] .. ":" .. math.random(1, 40)
            e.td = DEMO_ITEMS[math.random(#DEMO_ITEMS)] .. ":" .. math.random(1, 40)
            db.bank[name] = e
        end
    end
end

function ns.ClearBankDemo()
    local db = DB()
    for friend, e in pairs(db.bank) do
        if e.demo then db.bank[friend] = nil end
    end
end

function ns.ResetBank()
    wipe(DB().bank)
end
