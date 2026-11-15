local _, ns = ...
local L = ns.L

-- =============================================================================
-- Gruppe-milepæle (v0.29): fælles mål for hele banden
--   * Fx "1000 levels tilsammen", "100 dødsfald", "10.000 guld" eller "50 rare mobs". Hver
--     kategori har en stige af mål. Når banden når et mål, kommer der en fest-popup (med
--     konfetti) hos alle, en linje i chatten og en nyhed på bande-baren. Kun én gang pr. mål.
--   * Det hele regnes ud fra data, der allerede synker (karakterer, dødsfald, loot, instanser,
--     spilletid, rare mobs og prutter). Demo-data tæller aldrig.
--   * For hændelser (dødsfald, loot, rare mobs, prutter) er det den N'te hændelse efter tid,
--     der nåede målet, så alle får samme tidspunkt og samme "skyldige" ven. For tilstande
--     (levels, guld, spilletid, bosser) er det den første, der så det, og det tidligste
--     tidspunkt vinder, når vennerne fortæller hinanden om det.
--   * Den, der opdager et mål, sender XM, så vennerne også fejrer det, selv om deres data
--     ikke er nået frem endnu. Er man væk, kommer festen, når man logger ind, hvis målet
--     højst er 2 døgn gammelt. Ældre mål gemmes stille.
--   * Første gang modulet kører, gemmes alt det, banden allerede har nået, stille (ingen byge
--     af popups). Det sendes med "stille", så vennerne heller ikke fejrer det.
--   * /wc4ever milepæle fra: ingen popup, kun en linje i chatten.
--
-- Besked:
--   XM;fra;kategori;mål;tid;udløser;stille      (udløser og stille må mangle)
-- db.milestones = { hit = { ["kategori:mål"] = { t, by, s = 1 (stille), shown = 1 } }, init = true }
-- db.settings.milestones = false: ingen fest-popup
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name

local M = {}
ns.Milestones = M

M.FRESH = 2 * 86400     -- så gammelt må et mål være, og man får stadig festen
M.SETTLE = 90           -- sek. efter login, før vi selv leder efter nye mål (synken skal nå frem)
local HIT_MAX = 400

local function IC(name) return "Interface\\Icons\\" .. name end

-- Kategorierne. kind = "event": hændelser med tid og ven (den N'te afgør), "state": et tal nu.
-- done: festens overskrift, %s er målet.
-- Teksterne oversættes med L(), når de vises (id'erne må ikke røres af oversættelsen)
M.CATS = {
    { id = "lvl",   name = "Levels tilsammen",   icon = IC("Spell_Holy_SurgeOfLight"),       kind = "state",
      tiers = { 100, 250, 500, 750, 1000, 1500, 2000, 3000 },
      done = "%s levels tilsammen!", desc = "Alle levels på alle karakterer lagt sammen." },
    { id = "max",   name = "Max level-karakterer", icon = IC("INV_Misc_Head_Dragon_01"),     kind = "state",
      tiers = { 1, 3, 5, 8, 12, 16, 24 },
      done = "%s karakterer på max level!", desc = "Karakterer, der har nået spillets max level." },
    { id = "dead",  name = "Dødsfald",           icon = IC("INV_Misc_Bone_HumanSkull_01"),   kind = "event",
      tiers = { 10, 25, 50, 100, 200, 300, 500, 750, 1000 },
      done = "%s dødsfald! Spirit healeren kender jer ved navn.", desc = "Alle dødsfald i banden." },
    { id = "loot",  name = "Rare loot",          icon = IC("INV_Misc_Bag_10"),               kind = "event",
      tiers = { 10, 25, 50, 100, 250, 500, 1000 },
      done = "%s stykker rare loot (eller bedre)!", desc = "Vundet loot af kvaliteten rare eller bedre." },
    { id = "gold",  name = "Guld tilsammen",     icon = IC("INV_Misc_Coin_01"),              kind = "state",
      tiers = { 100, 500, 1000, 2500, 5000, 10000, 25000 },
      done = "%s guld tilsammen! Nogen burde give en omgang.", desc = "Guldet på alle karakterer lige nu." },
    { id = "boss",  name = "Boss-kills",         icon = IC("INV_Sword_48"),                  kind = "state",
      tiers = { 10, 50, 100, 250, 500, 1000, 2500 },
      done = "%s boss-kills!", desc = "Bosser dræbt i instanser, talt for hver ven." },
    { id = "hours", name = "Timer spillet",      icon = IC("INV_Misc_PocketWatch_01"),       kind = "state",
      tiers = { 24, 100, 250, 500, 1000, 2500, 5000 },
      done = "%s timer spillet tilsammen. Puha.", desc = "/played for alle karakterer lagt sammen." },
    { id = "rare",  name = "Rare mobs",          icon = IC("Ability_Hunter_SniperShot"),     kind = "event",
      tiers = { 5, 10, 25, 50, 100 },
      done = "%s rare mobs fældet!", desc = "Rare mobs dræbt af banden." },
    { id = "haan",  name = "Prutter",            icon = IC("Spell_Nature_Cyclone"),          kind = "event",
      tiers = { 10, 25, 50, 100, 200 },
      done = "%s prutter delt ud. Det lugter af fællesskab.", desc = "Prutter fra hån-knappen." },
}
M.BY_ID = {}
for _, cat in ipairs(M.CATS) do M.BY_ID[cat.id] = cat end

local loadedAt          -- GetTime(), da du loggede ind

local function DB()
    local db = WastedCoastDB
    db.milestones = db.milestones or {}
    db.milestones.hit = db.milestones.hit or {}
    return db, db.milestones
end

local function IsDemo(e)
    return e.demo or e.d or (type(e.id) == "string" and e.id:find("^demo%-") ~= nil)
end

-- Tal med punktum for hvert tusinde (engelsk: komma)
function M.Num(n)
    local s = tostring(math.floor(n or 0))
    local sep = L(".")
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    return out
end

local function Who(friend)
    local best, lvl
    local info = WastedCoastDB.friends and WastedCoastDB.friends[friend]
    for _, c in pairs((info and info.chars) or {}) do
        if c.class and (not lvl or (c.level or 0) > lvl) then best, lvl = c.class, c.level or 0 end
    end
    return C.ColorName(friend, best), best
end

-- =============================================================================
-- Tallene
-- =============================================================================
local function LootOwner(ev)
    if ev.friend and ROSTER_SET[ev.friend] then return ev.friend end
    return C.FriendOfChar(ev.char)
end

-- Hændelser i en kategori: { { t, f } }, sorteret efter tid (og ven, så rækkefølgen er ens hos alle)
function M.Events(id)
    local db = WastedCoastDB
    local list = {}
    local function add(t, f)
        if type(t) == "number" and f and ROSTER_SET[f] then list[#list + 1] = { t = t, f = f } end
    end
    if id == "dead" then
        for _, ev in ipairs(db.events or {}) do
            if not IsDemo(ev) then add(ev.time, C.EventFriend(ev)) end
        end
    elseif id == "loot" then
        for _, ev in ipairs(db.loot or {}) do
            if not IsDemo(ev) and (tonumber(ev.quality) or 0) >= 3 then add(ev.time, LootOwner(ev)) end
        end
    elseif id == "rare" then
        for _, r in ipairs(db.rareLog or {}) do
            if not IsDemo(r) then add(r.t, r.friend) end
        end
    elseif id == "haan" then
        local seen = {}
        for _, x in ipairs((db.haan and db.haan.log) or {}) do
            if not IsDemo(x) and ROSTER_SET[x.to] and not seen[x.id or ""] then
                if x.id then seen[x.id] = true end
                add(x.t, x.from)
            end
        end
    end
    table.sort(list, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.f < b.f
    end)
    return list
end

-- Tallet nu i hver kategori: { id -> tal }, og hændelseslisterne
function M.Values()
    local db = WastedCoastDB
    local v = { lvl = 0, max = 0, gold = 0, boss = 0, hours = 0 }
    local copper, secs = 0, 0
    for _, f in ipairs(ROSTER) do
        local info = db.friends and db.friends[f]
        for _, c in pairs((info and info.chars) or {}) do
            if not c.demo then
                local lv = tonumber(c.level) or 0
                v.lvl = v.lvl + lv
                if lv >= C.MAX_LEVEL then v.max = v.max + 1 end
                copper = copper + (tonumber(c.gold) or 0)
                if type(c.played) == "table" then secs = secs + (tonumber(c.played.t) or 0) end
            end
        end
        for _, e in pairs((db.runs and db.runs[f]) or {}) do
            if type(e) == "table" and not e.demo then
                for _, n in pairs(e.boss or {}) do v.boss = v.boss + (tonumber(n) or 0) end
            end
        end
    end
    v.gold = math.floor(copper / 10000)
    v.hours = math.floor(secs / 3600)
    local events = {}
    for _, cat in ipairs(M.CATS) do
        if cat.kind == "event" then
            events[cat.id] = M.Events(cat.id)
            v[cat.id] = #events[cat.id]
        end
    end
    return v, events
end

local function Key(id, tier) return id .. ":" .. tier end
M.Key = Key

local function ValidTier(cat, tier)
    for _, x in ipairs(cat.tiers) do if x == tier then return true end end
    return false
end

-- Næste mål i kategorien (nil, når alle er nået)
function M.Next(cat)
    local _, ms = DB()
    for _, tier in ipairs(cat.tiers) do
        local h = ms.hit[Key(cat.id, tier)]
        if not h or h.demo then return tier end
    end
    return nil
end

-- Hvor mange mål i kategorien er nået
function M.Reached(cat)
    local _, ms = DB()
    local n = 0
    for _, tier in ipairs(cat.tiers) do
        local h = ms.hit[Key(cat.id, tier)]
        if h and not h.demo then n = n + 1 end
    end
    return n
end

-- =============================================================================
-- Festen
-- =============================================================================
local CONFETTI = {
    { 1, 0.82, 0.2 }, { 0.4, 0.83, 0.42 }, { 0.25, 0.6, 1 }, { 1, 0.45, 0.75 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
local confetti

-- Konfetti, der drysser ned over toasten et par sekunder (pynt: fejler den, sker der intet)
function M.Confetti()
    if not UIParent then return end
    if not confetti then
        confetti = CreateFrame("Frame", nil, UIParent)
        confetti:SetAllPoints(UIParent)
        confetti:SetFrameStrata("FULLSCREEN_DIALOG")
        confetti:EnableMouse(false)
        confetti.bits = {}
        for i = 1, 48 do
            local t = confetti:CreateTexture(nil, "OVERLAY")
            local col = CONFETTI[(i % #CONFETTI) + 1]
            t:SetColorTexture(col[1], col[2], col[3], 1)
            confetti.bits[i] = t
        end
        confetti:SetScript("OnUpdate", function(self, dt)
            self.t = (self.t or 0) + (dt or 0)
            if self.t > 4 then self:Hide() return end
            local fade = self.t > 3 and (4 - self.t) or 1
            for _, b in ipairs(self.bits) do
                local x = b.x0 + b.vx * self.t + math.sin(self.t * b.w) * 12
                local y = b.y0 + b.vy * self.t - 70 * self.t * self.t
                b:ClearAllPoints()
                b:SetPoint("CENTER", UIParent, "TOP", x, y)
                b:SetAlpha(fade)
            end
        end)
    end
    for _, b in ipairs(confetti.bits) do
        local s = math.random(4, 8)
        b:SetSize(s, math.random(4, 10))
        b.x0, b.y0 = math.random(-220, 220), -100 - math.random(0, 40)
        b.vx, b.vy = math.random(-60, 60), math.random(60, 160)
        b.w = math.random(2, 6)
        b:Show()
    end
    confetti.t = 0
    confetti:Show()
end

-- Hvem nåede målet, som tekst (tom, hvis vi ikke ved det)
local function ByLine(cat, tier, by)
    if not by or not ROSTER_SET[by] then return "" end
    if by == WastedCoastDB.me then return string.format(L("Du stod for nummer %s."), M.Num(tier)) end
    return string.format(L("%s stod for nummer %s."), Name(by), M.Num(tier))
end

function M.Celebrate(cat, tier, h, test)
    local db = WastedCoastDB
    local title = string.format(L(cat.done), M.Num(tier))
    local by = ByLine(cat, tier, h and h.by)
    local nextTier
    for _, x in ipairs(cat.tiers) do if x > tier then nextTier = x break end end
    local text = by
    if nextTier then
        text = (by ~= "" and (by .. " ") or "") .. string.format(L("Næste mål: %s."), M.Num(nextTier))
    end
    Print("|cffffd100" .. L("Gruppe-milepæl!") .. "|r " .. title .. (by ~= "" and (" " .. by) or ""))
    if db.settings.milestones == false and not test then return end
    local _, class = Who(h and h.by or db.me)
    ns.Toast({ kind = "trophy", head = L("GRUPPE-MILEPÆL"), title = title, text = text, icon = cat.icon,
               class = class, sound = "achievement", friend = h and h.by, dur = 9, force = test })
    if db.settings.toasts ~= false or test then pcall(M.Confetti) end
end

-- =============================================================================
-- Registrering, beskeder og synk
-- =============================================================================
local function Serialize(id, tier, h)
    local by = (h.by and ROSTER_SET[h.by]) and h.by or ""
    return table.concat({ "XM", WastedCoastDB.me, id, tostring(tier), tostring(math.floor(h.t or 0)), by,
                          h.s and "1" or "" }, ";")
end

local function Trim()
    local _, ms = DB()
    local n, oldest, oldestK = 0
    for k, h in pairs(ms.hit) do
        n = n + 1
        if not oldest or (h.t or 0) < oldest then oldest, oldestK = h.t or 0, k end
    end
    if n > HIT_MAX and oldestK then ms.hit[oldestK] = nil end
end

-- Gemmer et nået mål. Returnerer true, hvis det var nyt.
function M.Record(id, tier, t, by, silent)
    local cat = M.BY_ID[id]
    if not cat or not ValidTier(cat, tier) or type(t) ~= "number" then return false end
    local _, ms = DB()
    local k = Key(id, tier)
    local h = ms.hit[k]
    if h and h.demo then h = nil end   -- demo må aldrig skygge for et ægte mål
    if h then
        -- Det tidligste tidspunkt vinder, så alle ender med det samme
        if t < (h.t or math.huge) then
            h.t = t
            if by and ROSTER_SET[by] then h.by = by end
        end
        if not h.by and by and ROSTER_SET[by] then h.by = by end
        return false
    end
    ms.hit[k] = { t = t, by = (by and ROSTER_SET[by]) and by or nil, s = silent and 1 or nil }
    Trim()
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    return true
end

-- Viser festen for et mål, hvis den ikke er vist, ikke er stille og stadig er frisk
local function MaybeCelebrate(id, tier, now)
    local _, ms = DB()
    local h = ms.hit[Key(id, tier)]
    if not h or h.shown or h.s then return false end
    if (now or time()) - (h.t or 0) > M.FRESH then return false end
    h.shown = 1
    M.Celebrate(M.BY_ID[id], tier, h)
    return true
end

-- Leder efter nye mål ud fra vores egne data. Returnerer antal nye.
function M.Check(now)
    local db, ms = DB()
    if not db.me then return 0 end
    now = now or time()
    local init = not ms.init
    local values, events = M.Values()
    local fresh = {}
    local new = 0
    for _, cat in ipairs(M.CATS) do
        local v = values[cat.id] or 0
        for _, tier in ipairs(cat.tiers) do
            local old = ms.hit[Key(cat.id, tier)]
            if v >= tier and (not old or old.demo) then
                local t, by = now, nil
                if cat.kind == "event" then
                    local e = events[cat.id][tier]
                    if e then t, by = math.min(e.t, now), e.f end
                end
                local silent = init or (now - t > M.FRESH)
                if M.Record(cat.id, tier, t, by, silent) then
                    new = new + 1
                    local h = ms.hit[Key(cat.id, tier)]
                    C.Send(Serialize(cat.id, tier, h), true)
                    if not silent then fresh[cat.id] = tier end   -- kun det højeste i hver kategori
                end
            end
        end
    end
    ms.init = true
    for _, cat in ipairs(M.CATS) do
        local tier = fresh[cat.id]
        if tier then
            -- De lavere mål, der blev nået samtidig, får ingen egen fest
            for _, x in ipairs(cat.tiers) do
                local h = ms.hit[Key(cat.id, x)]
                if x < tier and h and not h.shown then h.shown = 1 end
            end
            MaybeCelebrate(cat.id, tier, now)
        end
    end
    if new > 0 and ns.RefreshUI then ns.RefreshUI() end
    return new
end

function ns.HandleMilestoneMessage(t)
    local db, ms = DB()
    local from, id, tier, at, by, silent = t[2], t[3], tonumber(t[4]), tonumber(t[5]), t[6], t[7] == "1"
    if not ROSTER_SET[from] or from == db.me then return end
    local cat = id and M.BY_ID[id]
    if not cat or not tier or not ValidTier(cat, tier) then return end
    if not at or at < 1000000000 then return end
    at = math.min(math.floor(at), time())
    if by == "" or not ROSTER_SET[by] then by = nil end
    if M.Record(id, tier, at, by, silent) then
        -- Er det højeste nye mål i kategorien? Lavere mål, vi ikke har fejret, springes over
        local higher = false
        for _, x in ipairs(cat.tiers) do
            local h = ms.hit[Key(id, x)]
            if x > tier and h and h.shown then higher = true end
        end
        if not higher then MaybeCelebrate(id, tier) end
        if ns.RefreshUI then ns.RefreshUI() end
    end
end

-- Ved synk: de nåede mål (den lette synk kun de friske), nyeste først
function M.SendLog(light)
    local db, ms = DB()
    if not db.me then return end
    local list = {}
    for k, h in pairs(ms.hit) do
        local id, tier = k:match("^(%w+):(%d+)$")
        if id and not h.demo and (not light or time() - (h.t or 0) < M.FRESH) then
            list[#list + 1] = { id = id, tier = tonumber(tier), h = h }
        end
    end
    table.sort(list, function(a, b) return (a.h.t or 0) > (b.h.t or 0) end)
    for i = 1, math.min(#list, light and 10 or 40) do
        C.Send(Serialize(list[i].id, list[i].tier, list[i].h))
    end
end

-- =============================================================================
-- Nyheder og fremskridt
-- =============================================================================
function M.NewsItems()
    local _, ms = DB()
    local out = {}
    for k, h in pairs(ms.hit) do
        local id, tier = k:match("^(%w+):(%d+)$")
        local cat = id and M.BY_ID[id]
        if cat and not h.s then
            local text = string.format(L("|cffffd100Gruppe-milepæl:|r %s"), string.format(L(cat.done), M.Num(tonumber(tier))))
            out[#out + 1] = { t = h.t, key = "m" .. k, text = text, icon = cat.icon, demo = h.demo }
        end
    end
    return out
end

-- Kort fremskridt pr. kategori: { cat, v, next, reached }
function M.Progress()
    local values = M.Values()
    local out = {}
    for _, cat in ipairs(M.CATS) do
        local v = values[cat.id] or 0
        out[#out + 1] = { cat = cat, v = v, next = M.Next(cat), reached = M.Reached(cat) }
    end
    return out
end

-- =============================================================================
-- Side 19: Sjov > Milepæle
-- =============================================================================
local Txt, MakeBox = C.Txt, C.MakeBox
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN
local ui = {}
M.ui = ui
local BAR_W = 200

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

local function ShowTiers(owner, cat)
    local _, ms = DB()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L(cat.name), 1, 0.82, 0.2)
    GameTooltip:AddLine(L(cat.desc), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    for _, tier in ipairs(cat.tiers) do
        local h = ms.hit[Key(cat.id, tier)]
        if h then
            local right = C.FormatAgo(h.t or 0)
            if h.by and ROSTER_SET[h.by] then right = Name(h.by) .. ", " .. right end
            GameTooltip:AddDoubleLine("|cff66d36a+|r " .. M.Num(tier), right, 1, 1, 1, 0.6, 0.6, 0.66)
        else
            GameTooltip:AddDoubleLine("|cff666666-|r " .. M.Num(tier), L("ikke nået"), 0.6, 0.6, 0.66, 0.5, 0.5, 0.56)
        end
    end
    GameTooltip:Show()
end

local function BuildPage(page)
    local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(452)
    local _, sub = Header(left, L("Gruppe-milepæle"))
    ui.sub = sub
    ui.rows = {}
    for i, cat in ipairs(M.CATS) do
        local row = MakeBox("Button", left, COL_BTN, COL_BORDER)
        row:SetSize(432, 38)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -(38 + (i - 1) * 42))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon:SetTexture(cat.icon)
        row.name = Txt(row, "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.name:SetText(L(cat.name))
        row.count = Txt(row, "GameFontHighlightSmall")
        row.count:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        row.count:SetTextColor(0.6, 0.6, 0.66)
        row.barBG = row:CreateTexture(nil, "ARTWORK")
        C.BarFill(row.barBG, 0.22, 0.22, 0.27, 1)
        row.barBG:SetSize(BAR_W, 8)
        row.barBG:SetPoint("RIGHT", row, "RIGHT", -10, -6)
        row.barFill = row:CreateTexture(nil, "OVERLAY")
        row.barFill:SetHeight(8)
        row.barFill:SetPoint("TOPLEFT", row.barBG, "TOPLEFT", 0, 0)
        C.BarFill(row.barFill, 1, 0.82, 0.2, 1)
        row.val = Txt(row, "GameFontHighlightSmall")
        row.val:SetPoint("BOTTOMRIGHT", row.barBG, "TOPRIGHT", 0, 3)
        row.val:SetJustifyH("RIGHT")
        row.cat = cat
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            ShowTiers(self, self.cat)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.rows[i] = row
    end

    local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("LEFT", left, "RIGHT", 6, 0)
    Header(right, L("Seneste fester"))
    ui.recent = Txt(right, "GameFontHighlightSmall")
    ui.recent:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -40)
    ui.recent:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    ui.recent:SetJustifyH("LEFT")
    ui.recent:SetSpacing(4)
    local note = Txt(right, "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 10)
    note:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.5, 0.5, 0.56)
    note:SetText(L("Fælles mål for hele banden. Når et mål nås, holder alle fest. Hold musen over en række for at se alle mål."))
end

local function RefreshPage()
    local _, ms = DB()
    local total, done = 0, 0
    for _, p in ipairs(M.Progress()) do
        local row
        for _, r in ipairs(ui.rows) do if r.cat == p.cat then row = r end end
        if row then
            total, done = total + #p.cat.tiers, done + p.reached
            row.count:SetText(string.format(L("%d af %d mål nået"), p.reached, #p.cat.tiers))
            if p.next then
                local prev = 0
                for _, x in ipairs(p.cat.tiers) do if x < p.next then prev = x end end
                local k = math.max(0, math.min(1, (p.v - prev) / math.max(1, p.next - prev)))
                row.barFill:SetWidth(math.max(1, BAR_W * k))
                row.val:SetText(M.Num(p.v) .. " / " .. M.Num(p.next))
                row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
            else
                row.barFill:SetWidth(BAR_W)
                row.val:SetText(M.Num(p.v) .. "  |cff66d36a" .. L("alle nået!") .. "|r")
                row:SetBackdropColor(0.20, 0.17, 0.06, 1)
            end
        end
    end
    ui.sub:SetText(string.format(L("%d af %d nået"), done, total))

    local list = {}
    for k, h in pairs(ms.hit) do
        local id, tier = k:match("^(%w+):(%d+)$")
        if id and M.BY_ID[id] then list[#list + 1] = { cat = M.BY_ID[id], tier = tonumber(tier), h = h } end
    end
    table.sort(list, function(a, b) return (a.h.t or 0) > (b.h.t or 0) end)
    local lines = {}
    for i = 1, math.min(10, #list) do
        local x = list[i]
        lines[#lines + 1] = string.format("|T%s:14:14:0:0|t %s |cff888888%s|r", x.cat.icon,
            L(x.cat.name) .. ": " .. M.Num(x.tier), C.FormatAgo(x.h.t or 0))
    end
    if #lines == 0 then lines[1] = L("|cff888888Ingen endnu. Første mål er lige om hjørnet.|r") end
    ui.recent:SetText(table.concat(lines, "\n"))
end

C.EXTRA_PAGES[19] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Demo, nulstilling, kommandoer og events
-- =============================================================================
function M.MakeDemo()
    local db, ms = DB()
    local others = {}
    for _, name in ipairs(ROSTER) do if name ~= db.me then others[#others + 1] = name end end
    if not ms.hit[Key("dead", 50)] then
        ms.hit[Key("dead", 50)] = { t = time() - 5 * 3600, by = others[1], demo = true, shown = 1 }
    end
end

function M.ClearDemo()
    local _, ms = DB()
    for k, h in pairs(ms.hit) do
        if h.demo then ms.hit[k] = nil end
    end
end

function M.Reset()
    local db = WastedCoastDB
    if db then db.milestones = nil end
end

function ns.MilestonesSlash(cmd, arg)
    if cmd ~= "milepæle" and cmd ~= "milepæl" and cmd ~= "milestones" and cmd ~= "mål" and cmd ~= "goals" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "fra" or arg == "off" or arg == "til" or arg == "on" then
        if arg == "til" or arg == "on" then db.settings.milestones = nil else db.settings.milestones = false end
        Print(L("Milepæl-popups: ") .. ((db.settings.milestones ~= false) and L("til") or L("fra")))
    elseif arg == "test" then
        -- Kun hos dig selv: intet gemmes eller sendes
        M.Celebrate(M.BY_ID.lvl, 1000, { t = time(), by = db.me }, true)
    else
        Print("|cffffd100" .. L("Gruppe-milepæle") .. "|r")
        for _, p in ipairs(M.Progress()) do
            if p.next then
                print(string.format(L("  %s: %s af %s (%d af %d nået)"), L(p.cat.name), M.Num(p.v), M.Num(p.next), p.reached, #p.cat.tiers))
            else
                print(string.format(L("  %s: %s (alle nået!)"), L(p.cat.name), M.Num(p.v)))
            end
        end
    end
    return true
end

local function Tick()
    if not WastedCoastDB or not WastedCoastDB.me then return end
    if not loadedAt or GetTime() - loadedAt < M.SETTLE then return end
    M.Check()
end
M.Tick = Tick

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        loadedAt = GetTime()
        C_Timer.NewTicker(20, function() pcall(Tick) end)
    end
end)
