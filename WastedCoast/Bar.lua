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
--   * v0.28: en ven, der sover AFK i en by, har zZz på ikonet; et klik vækker vennen (Hjemmesko.lua),
--     shift-klik åbner karaktererne.
-- Bygger kun på data, addonet allerede har og synker, så baren sender ingen beskeder.
-- db.settings.bar (false = skjult), barLocked, barTicker (false = uden ticker),
-- barPos = { point, relPoint, x, y }
-- =============================================================================

local C = ns.core
local GAME, Name = C.GAME, C.Name

local ICON, GAP, PAD = 24, 4, 4      -- ikonstørrelse, afstand og kant
local RING = 2                       -- XP-ringens tykkelse
local TICK_H = 16                    -- v0.26: lidt mere luft mellem nyhederne
local GLYPH = 12                     -- ikonet foran hver nyhed
local TIME_W = 30                    -- tids-kolonnen til højre
local PEEK = 15                      -- v0.26: sek. en foldet bar står foldet ud ved en vigtig nyhed
local GRACE = 30                     -- intet folder ud de første sek. efter login (synken henter gamle nyheder)
local FRESH = 120                    -- kun nyheder, der højst er så gamle, folder baren ud
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

-- v0.26: nyhederne læses hvem → hvad → hvornår. Linjens grundfarve er dæmpet grå (udsagnsordene),
-- navne står i klassefarve, og "objektet" (dræber, modstander, mob) står i hvid.
local TEXT_DIM = { 0.65, 0.67, 0.71 }
local TIME_DIM = { 0.49, 0.51, 0.55 }
Bar.TEXT_DIM = TEXT_DIM
local function W(s) return "|cffffffff" .. tostring(s) .. "|r" end

-- Et lille ikon foran hver nyhed, så typen kan ses uden at læse (dødsfald, gank, loot ...)
local function IC(name) return "Interface\\Icons\\" .. name end
local KIND_ICON = {
    death = IC("INV_Misc_Bone_HumanSkull_01"),
    gank  = IC("INV_Sword_27"),
    level = IC("Spell_Holy_SurgeOfLight"),
    loot  = IC("INV_Misc_Bag_10"),
    ach   = IC("Spell_Shadow_AnimateDead"),
    rare  = IC("Ability_Hunter_SniperShot"),
    duel  = IC("Ability_Warrior_Challange"),
    stomi = IC("INV_Misc_Bag_10"),
    haan  = IC("Spell_Nature_Cyclone"),
    gz    = IC("Spell_Holy_SurgeOfLight"),
    hjemmesko = IC("Spell_Nature_Sleep"),
    cup   = IC("INV_Misc_Coin_02"),
}
Bar.KIND_ICON = KIND_ICON

-- =============================================================================
-- Ticker: det seneste nye fra de data, vi har. Hver linje = { t, key, text }
-- =============================================================================
-- v0.23: maxItems og maxAge kan sættes (nyhedspanelet i hovedvinduet viser de 100 seneste uden
-- aldersgrænse); uden dem er det tickerens 12 fra det seneste døgn.
function Bar.Items(now, maxItems, maxAge)
    local db = DB()
    now = now or time()
    maxItems = maxItems or MAX_ITEMS
    local since = now - (maxAge or MAX_AGE)
    local out = {}
    -- v0.26: kind = nyhedens type, icon = ikonet foran linjen, x = { demo, q } (demo-data, lootets kvalitet)
    local function add(t, key, text, link, dead, kind, icon, x)
        if t and t > since and t <= now + 60 and text then
            out[#out + 1] = { t = t, key = key, text = text, link = link, dead = dead, kind = kind,
                              icon = icon or KIND_ICON[kind], demo = x and x.demo or nil, q = x and x.q or nil,
                              ding = x and x.ding or nil }
        end
    end

    -- Dødsfald
    for _, ev in ipairs(db.events or {}) do
        local f = C.EventFriend(ev)
        if f and (ev.time or 0) > since then
            local killer = W((ev.killer and ev.killer ~= "") and L(ev.killer) or L("Ukendt"))
            local kl, lv = tonumber(ev.klvl), tonumber(ev.level)
            local text
            if ev.pvp == true then
                text = F("%s blev ganket af %s", Who(f, ev.class), killer)
            elseif kl and lv and kl > 0 and lv - kl >= 5 then
                text = F("%s døde til en level %d %s. Pinligt.", Who(f, ev.class), kl, killer)
            else
                text = F("%s døde til %s", Who(f, ev.class), killer)
            end
            -- v0.24: dead = vennen, så linjen kan bruges til at prutte (Haan.lua)
            add(ev.time, "d" .. tostring(ev.id or ev.time), text, nil, f, ev.pvp == true and "gank" or "death", nil,
                { demo = ev.demo })
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
            -- v0.27: ding = vennen, så linjen kan bruges til at sige tillykke (Gz.lua)
            add(e.t, "l" .. f .. e.l, text, nil, nil, "level", nil, { demo = e.d or e.demo, ding = f })
        end
    end

    -- Loot
    for _, ev in ipairs(db.loot or {}) do
        local f = (ev.friend and C.ROSTER_SET[ev.friend] and ev.friend) or C.FriendOfChar(ev.char)
        if f and (ev.time or 0) > since and ev.item and ev.name then
            -- v0.21: vundet på need/greed/disenchant står efter itemet
            local how = (ev.how == "need" or ev.how == "greed" or ev.how == "de") and C.HOW_LABEL and C.HOW_LABEL[ev.how]
            local tail = how and (" |cff9aa0a6(" .. how .. ")|r") or ""
            -- v0.21.1: musen over viser itemets tooltip. v0.26: itemets ikon står i ikon-kolonnen
            local id = tonumber(ev.item:match("^item:(%d+)"))
            local icon = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
            add(ev.time, "o" .. tostring(ev.id or ev.time), F("%s fik %s", Who(f, ev.class), C.LootLink(ev)) .. tail, ev.item,
                nil, "loot", icon, { demo = ev.demo, q = tonumber(ev.quality) })
        end
    end

    -- Trofæer
    for f, list in pairs(db.ach or {}) do
        if C.ROSTER_SET[f] then
            for id, t in pairs(list) do
                local a = C.ACH_BY_ID[id]
                if a and type(t) == "number" then
                    add(t, "a" .. f .. id, F("%s låste |cffffd100%s|r op", Who(f), a.name), nil, nil, "ach", a.icon)
                end
            end
        end
    end

    -- Rare mobs
    for _, r in ipairs(db.rareLog or {}) do
        if C.ROSTER_SET[r.friend] then
            add(r.t, "r" .. r.friend .. tostring(r.mob) .. tostring(r.t),
                F("%s dræbte rare mob %s", Who(r.friend), W(r.mob)), nil, nil, "rare")
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
                        text = F("%s vandt en duel mod %s", Who(f), d.of and Who(d.of) or W(d.opp or "?"))
                    elseif not d.of then
                        text = F("%s tabte en duel til %s", Who(f), W(d.opp or "?"))
                    end
                    if text then duels[key] = true add(d.t, key, text, nil, nil, "duel") end
                end
            end
        end
    end

    -- v0.22: stomi
    for _, e in ipairs((db.stomi and db.stomi.log) or {}) do
        if e.r == "y" and C.ROSTER_SET[e.to] and C.ROSTER_SET[e.from] then
            add(e.t, "s" .. tostring(e.id), F("%s fik |cffd9b38cstomi|r af %s", Who(e.to), Who(e.from)), nil, nil, "stomi",
                ns.Stomi and ns.Stomi.ICON, { demo = e.demo })
        end
    end

    -- v0.24: prutter
    for _, e in ipairs((db.haan and db.haan.log) or {}) do
        if C.ROSTER_SET[e.to] and C.ROSTER_SET[e.from] then
            add(e.t, "h" .. tostring(e.id), F("%s pruttede af %s", Who(e.from), Who(e.to)), nil, nil, "haan", nil, { demo = e.demo })
        end
    end

    -- v0.27: gz
    for _, e in ipairs((db.gz and db.gz.log) or {}) do
        if C.ROSTER_SET[e.to] and C.ROSTER_SET[e.from] then
            add(e.t, "g" .. tostring(e.id), F("%s sagde tillykke til %s med level %d", Who(e.from), Who(e.to), tonumber(e.l) or 0),
                nil, nil, "gz", nil, { demo = e.demo })
        end
    end

    -- v0.28: prik til sovende venner (Hjemmesko.lua)
    for _, e in ipairs((db.hjemmesko and db.hjemmesko.log) or {}) do
        if C.ROSTER_SET[e.to] and C.ROSTER_SET[e.from] then
            add(e.t, "v" .. tostring(e.id), F("%s vækkede %s i hjemmeskoene", Who(e.from), Who(e.to)), nil, nil, "hjemmesko",
                nil, { demo = e.demo })
        end
    end

    -- v0.25: ugens pokaler (én linje pr. uddeling)
    if ns.Weekly then
        for _, it in ipairs(ns.Weekly.NewsItems(now)) do add(it.t, it.key, it.text, nil, nil, "cup", it.icon) end
    end

    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.key < b.key
    end)
    for i = #out, maxItems + 1, -1 do out[i] = nil end
    return out
end

-- Nyhedslinjerne: { text, ago, icon, item } pr. linje (højst ROWS). En stille dag giver én pladsholder.
-- v0.26: tiden står i sin egen højrestillede kolonne og ikonet i sin egen kolonne til venstre.
function Bar.NewsLines(items, rows)
    rows = rows or ROWS
    if #items == 0 then
        return { { text = "|cff888888" .. L("Stille på kysten. Nogen må gøre noget dumt snart.") .. "|r" } }
    end
    local out = {}
    for i = 1, math.min(rows, #items) do
        local it = items[i]
        out[i] = { text = it.text, ago = Ago(it.t), icon = it.icon, item = it }
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
    -- v0.28: sover i hjemmeskoene (Hjemmesko.lua)
    local sleepMin, sleepZone = ns.Hjemmesko and ns.Hjemmesko.Asleep(s.name, now)
    if sleepMin then
        local where = (sleepZone and sleepZone ~= "") and (L(" i ") .. sleepZone) or ""
        add(string.format(L("|cff8fb8ffzZz|r Sover i hjemmeskoene (AFK i %d min.%s)"), sleepMin, where), nil, 0.56, 0.72, 1)
    end
    local d = DeathsToday(s.name, now)
    add(L("Døde i dag"), d > 0 and ("|cffff6060" .. d .. "|r") or "0", 0.6, 0.6, 0.66)
    if ns.HatHolder and ns.HatHolder() == s.name then add(L("Bærer |cffffd100Skammens hat|r (døde sidst)"), nil, 1, 0.5, 0.5) end
    local st = ns.StomiHas and ns.StomiHas(s.name, now)
    if st then
        add(string.format(L("Har |cffd9b38cstomi|r (fra %s, %s tilbage)"), Name(st.from), ns.Stomi.Hours(ns.Stomi.Remaining(s.name, now))), nil, 0.85, 0.7, 0.55)
    end
    -- v0.24: prutter givet og fået
    if ns.Haan then
        local sent, recv = ns.Haan.Counts()
        local ps, pr = sent[s.name] or 0, recv[s.name] or 0
        if ps + pr > 0 then add(L("Prutter"), string.format(L("%d givet, %d fået"), ps, pr), 0.6, 0.6, 0.66) end
    end
    -- v0.27: gz givet og fået
    if ns.Gz then
        local sent, recv = ns.Gz.Counts()
        local gs, gr = sent[s.name] or 0, recv[s.name] or 0
        if gs + gr > 0 then add("Gz", string.format(L("%d givet, %d fået"), gs, gr), 0.6, 0.6, 0.66) end
    end
    -- v0.28: prik til sovende venner
    if ns.Hjemmesko then
        local sent, recv = ns.Hjemmesko.Counts()
        local vs, vr = sent[s.name] or 0, recv[s.name] or 0
        if vs + vr > 0 then add(L("Vækninger"), string.format(L("%d givet, %d fået"), vs, vr), 0.6, 0.6, 0.66) end
    end
    if s.chars and s.chars > 1 then add(L("Karakterer"), tostring(s.chars), 0.6, 0.6, 0.66) end
    -- v0.25: ugens pokaler
    local won = ns.Weekly and ns.Weekly.Won(s.name, now) or {}
    if #won > 0 then
        local names = {}
        for i, x in ipairs(won) do names[i] = x.cup.name end
        add(L("Ugens pokaler"), table.concat(names, ", "), 1, 0.82, 0.2)
    end
    add(" ")
    if Bar.CanWake(s.name, now) then
        add(string.format(L("Klik: væk %s med en vækkelyd"), Name(s.name)), nil, 0.56, 0.72, 1)
        add(L("Shift-klik: se vennens karakterer"), nil, 0.5, 0.5, 0.56)
    else
        add(L("Klik: se vennens karakterer"), nil, 0.5, 0.5, 0.56)
    end
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

-- v0.28: en sovende ven (ikke dig) kan vækkes med et klik på ikonet
function Bar.CanWake(friend, now)
    return ns.Hjemmesko ~= nil and friend ~= DB().me and ns.Hjemmesko.Asleep(friend, now) ~= nil
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
    -- v0.26: level står på en mørk plade, så tallet kan læses oven på ikonet
    btn.levelBg = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    btn.levelBg:SetSize(15, 10)
    btn.levelBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.levelBg:SetColorTexture(0.04, 0.05, 0.06, 0.85)
    btn.level = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    if btn.level.SetDrawLayer then btn.level:SetDrawLayer("OVERLAY", 2) end
    btn.level:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
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
    -- v0.28: zZz over ikonet hos en ven, der sover AFK i en by (Hjemmesko.lua)
    btn.zzz = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if btn.zzz.SetDrawLayer then btn.zzz:SetDrawLayer("OVERLAY", 7) end
    btn.zzz:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 4)
    btn.zzz:SetTextColor(0.56, 0.72, 1)
    btn.zzz:SetText("zZz")
    btn.zzz:Hide()
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
        elseif self.friend and Bar.CanWake(self.friend) and not (IsShiftKeyDown and IsShiftKeyDown()) then
            if ns.HjemmeskoWake then ns.HjemmeskoWake(self.friend) end
            Bar.MarkDirty()
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
    local h = PAD * 2 + outer + (tickerOn and (nRows * TICK_H + 7) or 0)
    bar:SetSize(w, h)
    -- v0.26: med nyhederne står "N online" som tekst til højre og en streg skiller venner fra nyheder.
    -- Uden nyhederne er baren for smal, så tallet står på logoet som før.
    bar.onlineText:SetShown(tickerOn)
    bar.fold:SetShown(tickerOn)
    -- Pilen peger derhen, baren folder: op = fold ind, ned = fold ud
    bar.fold.tex:SetTexture(S().barFolded and "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
        or "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
    bar.logoText:SetShown(not tickerOn)
    bar.divider:SetShown(tickerOn)
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
        r.fs:SetWidth(w - PAD * 2 - GLYPH - 4 - TIME_W)
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
            b.levelBg:SetShown(s.level ~= nil and s.level > 0)
            local p, max = Bar.RingValue(s.level, s.xp)
            if max then
                SetRing(b, 1, C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3], s.online and 1 or 0.45)
            else
                SetRing(b, p, r, g, bl, s.online and 1 or 0.4)
            end
            b.online = s.online
            b.hat:SetShown(hat ~= nil and hat == s.name)
            b.stomi:SetShown(ns.StomiHas ~= nil and ns.StomiHas(s.name) ~= nil)
            local asleep = ns.Hjemmesko ~= nil and ns.Hjemmesko.Asleep(s.name) ~= nil
            b.zzz:SetShown(asleep)
            b.asleep = asleep
            if asleep and s.online then b.icon:SetAlpha(0.7) end
        end
    end
    bar.online = online
    bar.logoText:SetText(online > 0 and tostring(online) or "")
    bar.onlineText:SetText(string.format(L("|cff66d36a%d|r online"), online))
    Bar.UpdateTicker()
    Layout()
end

-- Nyhederne: faste linjer under ikonerne. Musen over en linje viser det hele, og for loot
-- itemets egen tooltip.
local function RowEnter(self)
    local it = self.line and self.line.item
    if not it or (bar and bar.moving) or not GameTooltip then return end
    GameTooltip:SetOwner(self, self.anchor or "ANCHOR_BOTTOM")
    if it.link and GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(it.text .. " |cff888888(" .. C.FormatAgo(it.t) .. ")|r", 0.8, 0.8, 0.84, true)
        GameTooltip:AddLine(L("Shift-klik for at sende linket i chatten"), 0.5, 0.5, 0.56)
    else
        GameTooltip:AddLine(it.text, 1, 1, 1, true)
        GameTooltip:AddLine(C.FormatAgo(it.t), 0.6, 0.6, 0.66)
        if Bar.CanTaunt(it) then
            GameTooltip:AddLine(string.format(L("Klik: prut af %s"), Name(it.dead)), 0.85, 0.63, 0.36)
        elseif Bar.CanGz(it) then
            GameTooltip:AddLine(string.format(L("Klik: sig tillykke til %s"), Name(it.ding)), 0.4, 0.83, 0.42)
        end
    end
    GameTooltip:Show()
end

-- v0.24: en linje om et dødsfald kan bruges til at prutte af vennen, så længe det er friskt
function Bar.CanTaunt(it)
    if not (it and it.dead and ns.Haan) then return false end
    return ns.Haan.Can(it.dead) and true or false
end

-- v0.27: en linje om et level kan bruges til at sige tillykke, så længe det er friskt
function Bar.CanGz(it)
    if not (it and it.ding and ns.Gz) then return false end
    return ns.Gz.Can(it.ding) and true or false
end

-- v0.26: tids-kolonnen. Over et dødsfald, man kan prutte af, bliver tiden til en "Prut"-knap,
-- så man kan se, at linjen kan klikkes.
local function SetRowTime(row, hover)
    local line = row.line
    local it = line and line.item
    if hover and it and Bar.CanTaunt(it) then
        row.time:SetText(L("Prut"))
        row.time:SetTextColor(0.94, 0.77, 0.54)
        row.chip:SetColorTexture(0.85, 0.63, 0.36, 0.22)
        row.chip:Show()
    elseif hover and it and Bar.CanGz(it) then
        -- v0.27: over et frisk level bliver tiden til "Gz"
        row.time:SetText("Gz")
        row.time:SetTextColor(0.55, 0.9, 0.55)
        row.chip:SetColorTexture(0.4, 0.83, 0.42, 0.22)
        row.chip:Show()
    else
        row.time:SetText(line and line.ago or "")
        row.time:SetTextColor(TIME_DIM[1], TIME_DIM[2], TIME_DIM[3])
        row.chip:Hide()
    end
end

local function RowClick(self)
    local it = self.line and self.line.item
    if it and it.dead and not it.link and ns.HaanSend and not (IsShiftKeyDown and IsShiftKeyDown()) then
        if ns.Haan.FreshDeath(it.dead) then ns.HaanSend(it.dead) end
        return
    end
    -- v0.27: klik på et frisk level siger tillykke
    if it and it.ding and ns.GzSend and ns.Gz.FreshDing(it.ding) then
        ns.GzSend(it.ding)
        return
    end
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
    -- v0.26: ikon | tekst | tid
    row.glyph = row:CreateTexture(nil, "ARTWORK")
    row.glyph:SetSize(GLYPH, GLYPH)
    row.glyph:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.glyph:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fs:SetWordWrap(false)
    row.fs:SetJustifyH("LEFT")
    row.fs:SetPoint("LEFT", row, "LEFT", GLYPH + 4, 0)
    row.fs:SetTextColor(TEXT_DIM[1], TEXT_DIM[2], TEXT_DIM[3])
    row.chip = row:CreateTexture(nil, "BORDER")
    row.chip:SetSize(TIME_W, TICK_H - 2)
    row.chip:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.chip:SetColorTexture(0.85, 0.63, 0.36, 0.22)
    row.chip:Hide()
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.time:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.time:SetJustifyH("RIGHT")
    row.time:SetTextColor(TIME_DIM[1], TIME_DIM[2], TIME_DIM[3])
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 0.85, 0.45, 0.07)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", StartMove)
    row:SetScript("OnDragStop", StopMove)
    row:SetScript("OnEnter", function(self) SetRowTime(self, true) RowEnter(self) end)
    row:SetScript("OnLeave", function(self)
        SetRowTime(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", RowClick)
    return row
end

-- =============================================================================
-- v0.26: foldet ind/ud. Pilen øverst til højre skifter, og valget huskes (db.settings.barFolded = true
-- betyder foldet ind; nil = foldet ud, som alle starter med). Foldet ind står kun den nyeste nyhed,
-- men en vigtig nyhed folder baren ud i PEEK sek.
-- =============================================================================
local HOT = { death = true, gank = true, level = true, ach = true, cup = true, stomi = true, haan = true }
-- Tilstanden: set = nyheder, vi har set (key -> true), peekUntil = hvornår en udfoldning slutter,
-- readyAt = hvornår login-pausen er forbi
local fs = { seen = false, peekUntil = false, readyAt = 0 }
Bar.foldState = fs

-- Er nyheden vigtig nok til at folde baren ud? Loot kun fra epic og op. Demo-data aldrig.
function Bar.IsHot(it)
    if not it or it.demo then return false end
    if it.kind == "loot" then return (it.q or 0) >= 4 end
    return HOT[it.kind] == true
end

local function Clock() return GetTime and GetTime() or time() end

function Bar.Peeking()
    return bar ~= nil and fs.peekUntil and Clock() < fs.peekUntil or false
end

-- Hvor mange nyheder står der lige nu
function Bar.RowCount()
    if not S().barFolded or Bar.Peeking() then return ROWS end
    return 1
end

-- Nye vigtige nyheder (ikke set før, friske, ikke lige efter login) folder baren ud
function Bar.CheckNew(items, now)
    if not bar then return end
    now = now or time()
    local first = not fs.seen
    fs.seen = fs.seen or {}
    local hot = false
    local ready = Clock() >= (fs.readyAt or 0)
    for _, it in ipairs(items) do
        if not fs.seen[it.key] then
            fs.seen[it.key] = true
            if not first and ready and it.t >= now - FRESH and Bar.IsHot(it) then hot = true end
        end
    end
    if hot then fs.peekUntil = Clock() + PEEK end
end

function Bar.UpdateTicker()
    if not bar then return end
    local items = Bar.Items()
    Bar.CheckNew(items)
    local lines = Bar.NewsLines(items, Bar.RowCount())
    for i = #bar.rows + 1, #lines do bar.rows[i] = MakeRow(i) end
    for i, row in ipairs(bar.rows) do
        local line = lines[i]
        row:SetShown(line ~= nil)
        row.line = line or false
        row.fs:SetText(line and line.text or "")
        row.glyph:SetShown(line ~= nil and line.icon ~= nil)
        if line and line.icon then row.glyph:SetTexture(line.icon) end
        SetRowTime(row, false)
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

    -- v0.26: pilen øverst til højre folder nyhederne ind og ud
    local fold = CreateFrame("Button", nil, bar)
    fold:SetSize(16, 16)
    fold:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -PAD, -PAD - RING - 4)
    fold:RegisterForDrag("LeftButton")
    fold.tex = fold:CreateTexture(nil, "ARTWORK")
    fold.tex:SetAllPoints(fold)
    local fhl = fold:CreateTexture(nil, "HIGHLIGHT")
    fhl:SetAllPoints(fold)
    fhl:SetColorTexture(1, 0.85, 0.45, 0.15)
    fold:SetScript("OnDragStart", StartMove)
    fold:SetScript("OnDragStop", StopMove)
    fold:SetScript("OnClick", function() ns.SetBarFolded(not S().barFolded) end)
    fold:SetScript("OnEnter", function(self)
        if bar.moving or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(S().barFolded and L("Klik: fold nyhederne ud") or L("Klik: fold nyhederne ind"), 1, 1, 1)
        if not S().barFolded then
            GameTooltip:AddLine(L("Foldet ind står kun den nyeste. Vigtige nyheder folder den ud et øjeblik."), 0.7, 0.7, 0.76, true)
        end
        GameTooltip:Show()
    end)
    fold:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    bar.fold = fold

    -- v0.26: "N online" til højre i toppen og en tynd streg mellem venner og nyheder
    bar.onlineText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.onlineText:SetPoint("RIGHT", fold, "LEFT", -4, 0)
    bar.onlineText:SetJustifyH("RIGHT")
    bar.onlineText:SetTextColor(TEXT_DIM[1], TEXT_DIM[2], TEXT_DIM[3])
    bar.divider = bar:CreateTexture(nil, "ARTWORK")
    bar.divider:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -(PAD + ICON + RING * 2 + 3))
    bar.divider:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -(PAD + ICON + RING * 2 + 3))
    bar.divider:SetHeight(1)
    bar.divider:SetColorTexture(1, 1, 1, 0.08)

    -- Nyhederne: de seneste 5 begivenheder under ikonerne
    bar.news = CreateFrame("Frame", nil, bar)
    bar.news:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -(PAD + ICON + RING * 2 + 7))
    bar.rows = {}

    fs.readyAt = Clock() + GRACE
    Place()
    ns.barFrame = bar
    bar:SetShown(S().bar ~= false)
    Bar.Refresh()
end

-- =============================================================================
-- v0.23: nyhedspanelet i hovedvinduet. Samme nyheder som på baren, men de 100 seneste
-- (uden aldersgrænse) i en liste, man kan scrolle i. Står i højre side af vinduet,
-- uanset hvilken fane der er valgt.
-- v0.26: ikon pr. slags nyhed, tiden i sin egen kolonne og filterknapper øverst.
-- =============================================================================
local PANEL_MAX = 100
local PANEL_ROW_H = 30       -- plads til to linjer pr. nyhed
local PANEL_HEAD = 24
local CHIP_H = 18
local LIST_TOP = PANEL_HEAD + CHIP_H + 8
local panel
Bar.PANEL_MAX = PANEL_MAX

-- Hvilket filter en nyhed hører til. Typen (it.kind) og ikonet (it.icon) sætter Bar.Items.
local FILTER_OF = { death = "death", gank = "death", loot = "loot", level = "level" }
Bar.FILTERS = {
    { key = "all",   label = "Alle" },
    { key = "death", label = "Død" },
    { key = "loot",  label = "Loot" },
    { key = "level", label = "Level" },
    { key = "fun",   label = "Sjov" },
}

function Bar.KindOf(it)
    return it and FILTER_OF[it.kind] or "fun"
end

function Bar.IconOf(it)
    return it and (it.icon or KIND_ICON[it.kind]) or nil
end

function Bar.Filter(items, filter)
    if not filter or filter == "all" then return items end
    local out = {}
    for _, it in ipairs(items) do
        if Bar.KindOf(it) == filter then out[#out + 1] = it end
    end
    return out
end

-- De linjer, der kan ses fra offset (antal rows). Giver også det rettede offset og det største.
-- Hver linje: { text, time, icon, item }. Itemets ikon står i ikonkolonnen, ikke inde i teksten.
function Bar.PanelLines(items, offset, rows)
    local total = #items
    local maxOff = math.max(0, total - rows)
    offset = math.max(0, math.min(math.floor(offset or 0), maxOff))
    if total == 0 then return Bar.NewsLines(items), 0, 0 end
    local out = {}
    for i = 1, math.min(rows, total - offset) do
        local it = items[offset + i]
        out[i] = { text = it.text, time = Ago(it.t), icon = Bar.IconOf(it), item = it }
    end
    return out, offset, maxOff
end

local function MakePanelRow(i)
    local row = CreateFrame("Button", nil, panel.list)
    row.line = false
    row.anchor = "ANCHOR_RIGHT"
    row:SetHeight(PANEL_ROW_H)
    row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, -(i - 1) * PANEL_ROW_H)
    row:SetPoint("TOPRIGHT", panel.list, "TOPRIGHT", 0, -(i - 1) * PANEL_ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -4)
    row.time:SetWidth(TIME_W)
    row.time:SetJustifyH("RIGHT")
    row.time:SetTextColor(0.55, 0.55, 0.6)
    row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fs:SetTextColor(TEXT_DIM[1], TEXT_DIM[2], TEXT_DIM[3])
    row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 25, -4)
    row.fs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(TIME_W + 6), 2)
    row.fs:SetJustifyH("LEFT")
    row.fs:SetJustifyV("TOP")
    row.fs:SetWordWrap(true)
    if row.fs.SetMaxLines then row.fs:SetMaxLines(2) end
    local sep = row:CreateTexture(nil, "BORDER")
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(1, 1, 1, 0.05)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 0.85, 0.45, 0.07)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", RowClick)
    return row
end

-- Filterknap: guldkant og guldtekst, når den er valgt
local function MakeChip(parent, key, label)
    local b = C.MakeBox("Button", parent, C.COL_BTN, C.COL_BORDER)
    b:SetHeight(CHIP_H)
    b.key = key
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetText(L(label))
    function b:SetActive(on)
        self.active = on
        if on then
            self:SetBackdropBorderColor(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3], 1)
            self.text:SetTextColor(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3])
        else
            self:SetBackdropBorderColor(C.COL_BORDER[1], C.COL_BORDER[2], C.COL_BORDER[3], 1)
            self.text:SetTextColor(0.78, 0.78, 0.82)
        end
    end
    b:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(1, 1, 1) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    b:SetScript("OnClick", function(self) Bar.SetPanelFilter(self.key) end)
    b:SetActive(false)
    return b
end

function Bar.SetPanelFilter(key)
    if not panel then return end
    panel.filter = key or "all"
    panel.offset = 0
    for _, chip in ipairs(panel.chips) do chip:SetActive(chip.key == panel.filter) end
    ns.RefreshNewsPanel()
end

function ns.RefreshNewsPanel()
    if not panel or not panel:IsShown() then return end
    local items = Bar.Filter(Bar.Items(nil, PANEL_MAX, math.huge), panel.filter)
    local lines, off, maxOff = Bar.PanelLines(items, panel.offset, panel.nRows)
    panel.offset, panel.maxOffset, panel.total = off, maxOff, #items
    for i, row in ipairs(panel.rows) do
        local line = lines[i]
        row:SetShown(line ~= nil)
        row.line = line or false
        row.fs:SetText(line and line.text or "")
        row.time:SetText(line and line.time or "")
        if line and line.icon then
            row.icon:SetTexture(line.icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end
    end
    panel.count:SetText(#items > 0 and tostring(#items) or "")
    -- Rullebjælken: kun når der er mere, end der kan ses
    local trackH = panel.nRows * PANEL_ROW_H
    if maxOff > 0 then
        local h = math.max(16, trackH * panel.nRows / #items)
        panel.thumb:SetHeight(h)
        panel.thumb:ClearAllPoints()
        panel.thumb:SetPoint("TOPRIGHT", panel.list, "TOPRIGHT", 7, -((trackH - h) * off / maxOff))
    end
    panel.track:SetShown(maxOff > 0)
    panel.thumb:SetShown(maxOff > 0)
end

function Bar.ScrollPanel(delta)
    if not panel then return end
    panel.offset = (panel.offset or 0) - delta * 2
    ns.RefreshNewsPanel()
end

-- Bygges af hovedvinduet: parent er en tom frame i højre side, width og height dens størrelse
function ns.BuildNewsPanel(parent, height, width)
    if panel then return panel end
    panel = C.MakeBox("Frame", parent, C.COL_PANEL, C.COL_BORDER)
    panel:SetAllPoints(parent)
    panel.offset, panel.maxOffset, panel.total, panel.filter = 0, 0, 0, "all"
    panel.nRows = math.max(1, math.floor((height - LIST_TOP - 8) / PANEL_ROW_H))

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    title:SetJustifyH("LEFT")
    title:SetText(L("Nyheder"))
    title:SetTextColor(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3])
    panel.title = title
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.count:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    panel.count:SetJustifyH("RIGHT")
    panel.count:SetTextColor(0.5, 0.5, 0.56)

    -- Filterknapperne deler bredden
    panel.chips = {}
    local n, gap = #Bar.FILTERS, 3
    local cw = ((width or 240) - 12 - (n - 1) * gap) / n
    for i, fl in ipairs(Bar.FILTERS) do
        local chip = MakeChip(panel, fl.key, fl.label)
        chip:SetWidth(cw)
        chip:SetPoint("TOPLEFT", panel, "TOPLEFT", 6 + (i - 1) * (cw + gap), -PANEL_HEAD)
        panel.chips[i] = chip
    end
    panel.chips[1]:SetActive(true)

    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -LIST_TOP + 3)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -LIST_TOP + 3)
    line:SetHeight(1)
    line:SetColorTexture(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3], 0.3)

    panel.list = CreateFrame("Frame", nil, panel)
    panel.list:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -LIST_TOP)
    panel.list:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -LIST_TOP)
    panel.list:SetHeight(panel.nRows * PANEL_ROW_H)

    panel.track = panel:CreateTexture(nil, "ARTWORK")
    panel.track:SetPoint("TOPRIGHT", panel.list, "TOPRIGHT", 7, 0)
    panel.track:SetSize(3, panel.nRows * PANEL_ROW_H)
    panel.track:SetColorTexture(1, 1, 1, 0.06)
    panel.thumb = panel:CreateTexture(nil, "OVERLAY")
    panel.thumb:SetWidth(3)
    panel.thumb:SetColorTexture(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3], 0.6)

    panel.rows = {}
    for i = 1, panel.nRows do panel.rows[i] = MakePanelRow(i) end

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) Bar.ScrollPanel(delta) end)
    ns.newsPanel = panel
    return panel
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

-- v0.26: fold nyhederne ind (kun den nyeste) eller ud (alle 5). Et klik, mens baren står foldet
-- ud af sig selv, låser den åben.
function ns.SetBarFolded(v)
    S().barFolded = v and true or nil
    if bar then
        fs.peekUntil = false
        Bar.Refresh()
    end
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
    elseif arg == "fold" then
        ns.SetBarFolded(not S().barFolded)
        P(S().barFolded and L("Nyhederne på baren er foldet ind.") or L("Nyhederne på baren er foldet ud."))
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
        -- v0.26: en foldet bar, der stod foldet ud, folder ind igen
        if fs.peekUntil and Clock() >= fs.peekUntil then
            fs.peekUntil = false
            dirty = true
        end
        -- Online-status ændrer sig også, uden at der kommer nye data (en ven holder op med at svare)
        if dirty or n % 15 == 0 then
            dirty = false
            Bar.Refresh()
        end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, Tick) end
    Bar.Tick = Tick
end
