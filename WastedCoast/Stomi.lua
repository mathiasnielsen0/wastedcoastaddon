local _, ns = ...
local L = ns.L

-- =============================================================================
-- Stomi-fælden (v0.22)
--   Den gamle leg i spilform: du stiller en ven et spørgsmål, vennen helt sikkert siger ja
--   til, og lige inden vennen svarer, spørger du "HAR DU STOMI?". Siger vennen ja, har
--   vennen stomi i 24 timer.
--
--   * Du sender fælden med højreklik på vennen under Sjov > Drilleri eller med
--     /wc4ever stomi <ven>. Cooldown: 6 timer mellem dine fælder.
--   * Vennen får en popup med en stor JA-knap lige under musen og en lille "nej" i hjørnet.
--     Spørgsmålet er en lokkemad, man har lyst til at sige ja til, og som passer til
--     situationen: en gruppe-invite, en summon til din zone, en rez (hvis vennen er død, og du
--     kan rezze), en gave med et rigtigt item fra din taske, lidt guld eller en dungeon-carry.
--   * I samme øjeblik vennen trykker ned på JA, skifter teksten til "HAR DU STOMI?". Slipper
--     vennen knappen, er det et ja. Den eneste udvej er den lille nej.
--   * Knapperne gør aldrig noget i spillet: ingen invite, summon, rez, trade eller duel.
--   * Popuppen kommer ikke midt i kamp (den venter, til kampen er slut), og den kan slås fra
--     i indstillingerne eller med /wc4ever stomi fra.
--   * Ja = stomi i 24 timer: en lille stomipose på vennens ikon i bande-baren, en besked
--     og en toast hos alle, en linje i tickeren og i dagens sladder og en tæller for flest
--     givne og flest modtagne stomier.
--
-- Beskeder:
--   XS;fra;til;nonce;karakter;klasse;zone;itemId;kvalitet;guld;itemnavn   (fælden, sendes af giveren)
--   XT;offer;fra;nonce;resultat;tid;lokkemad                          (svaret, sendes af offeret)
--   resultat: y = sagde ja (stomi), n = så spørgsmålet og sagde nej, d = afviste lokkematen,
--   x = lukkede/ignorerede popuppen
-- db.stomi = { log = { { id, from, to, r, t, bait } }, lastSent = tid }
-- db.settings.stomi = false: modtag ingen fælder
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name
local Plain = C.GAME.Plain

local Stomi = {}
ns.Stomi = Stomi

Stomi.ICON = "Interface\\AddOns\\WastedCoast\\media\\stomi"
Stomi.DURATION = 24 * 3600     -- så længe har man stomi
Stomi.COOLDOWN = 6 * 3600      -- så længe mellem dine fælder (med vilje længe)
Stomi.TIMEOUT = 60             -- popuppen lukker af sig selv (som spillets egne)
local LOG_MAX = 200
local FRESH = 300              -- kun nye svar giver toast og besked

-- Klasser, der kan rezze uden for kamp
local REZ = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }

local function DB()
    local db = WastedCoastDB
    db.stomi = db.stomi or {}
    db.stomi.log = db.stomi.log or {}
    return db, db.stomi
end

local function Clean(s)
    return (tostring(s or ""):gsub("[;|]", ","))
end

-- =============================================================================
-- Status: hvem har stomi, og hvem giver/får flest
-- =============================================================================
-- Den seneste stomi, vennen har fået, hvis den stadig sidder der (ellers nil)
function Stomi.Has(friend, now)
    now = now or time()
    local _, st = DB()
    local best
    for _, e in ipairs(st.log) do
        if e.to == friend and e.r == "y" and (e.t or 0) > now - Stomi.DURATION and (e.t or 0) <= now + 60
            and (not best or e.t > best.t) then
            best = e
        end
    end
    return best
end
ns.StomiHas = Stomi.Has

function Stomi.Remaining(friend, now)
    now = now or time()
    local e = Stomi.Has(friend, now)
    return e and math.max(0, e.t + Stomi.DURATION - now) or 0
end

local function Hours(secs)
    if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. L(" min") end
    return math.floor(secs / 3600 + 0.5) .. L(" timer")
end
Stomi.Hours = Hours

-- { given = { ven -> n }, recv = { ven -> n }, escaped = { ven -> n } }
function Stomi.Counts()
    local _, st = DB()
    local given, recv, escaped = {}, {}, {}
    for _, e in ipairs(st.log) do
        if e.r == "y" then
            given[e.from] = (given[e.from] or 0) + 1
            recv[e.to] = (recv[e.to] or 0) + 1
        elseif e.r == "n" or e.r == "d" then
            escaped[e.to] = (escaped[e.to] or 0) + 1
        end
    end
    return { given = given, recv = recv, escaped = escaped }
end

local function Top(map)
    local best, n = nil, 0
    for f, c in pairs(map) do
        if ROSTER_SET[f] and (c > n or (c == n and best and f < best)) then best, n = f, c end
    end
    return best, n
end

-- Én linje til Drilleri-siden
function Stomi.Summary(now)
    local active = {}
    for _, name in ipairs(ROSTER) do
        if Stomi.Has(name, now) then
            active[#active + 1] = Name(name) .. " (" .. Hours(Stomi.Remaining(name, now)) .. ")"
        end
    end
    local c = Stomi.Counts()
    local giver, gn = Top(c.given)
    local bearer, bn = Top(c.recv)
    local parts = {}
    if #active > 0 then
        parts[#parts + 1] = L("|cffd9b38cStomi nu:|r ") .. table.concat(active, ", ")
    else
        parts[#parts + 1] = L("|cffd9b38cStomi nu:|r ingen")
    end
    if giver then parts[#parts + 1] = string.format(L("Flest givet: %s (%d)"), Name(giver), gn) end
    if bearer then parts[#parts + 1] = string.format(L("Flest fået: %s (%d)"), Name(bearer), bn) end
    return table.concat(parts, "   ")
end

-- =============================================================================
-- Lokkemaden: noget, man har lyst til at sige ja til, og som ligner spillets egne popups
-- =============================================================================
local QUALITY_COLOR = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }

local function ItemText(ctx)
    local link
    if ctx.itemId and C.GAME.ItemInfo then
        local ok, _, l = pcall(C.GAME.ItemInfo, ctx.itemId)
        if ok and type(l) == "string" and l:find("|H", 1, true) then link = l end
    end
    return link or string.format("|cff%s|Hitem:%d::::::::|h[%s]|h|r", QUALITY_COLOR[ctx.quality or 1] or "ffffff",
        ctx.itemId or 0, ctx.itemName or "?")
end

local function Coins(copper)
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, copper)
        if ok and type(s) == "string" then return s end
    end
    return math.floor(copper / 10000) .. "g"
end

-- Lokkematen: et spørgsmål, man har lyst til at sige JA til, med giverens karakter, zone og
-- et rigtigt item fra giverens taske.
-- ctx: char, class, zone, itemId, quality, itemName, gold (fra giveren)
--      myZone, dead, grouped (fra offeret). rnd = tilfældighed (til tests).
-- Returnerer { kind, text, sound }
function Stomi.Bait(ctx, rnd)
    rnd = rnd or math.random
    local who = ctx.char or "?"
    local bait = {}
    local function add(kind, w) if w > 0 then bait[#bait + 1] = { kind = kind, w = w } end end

    if ctx.dead and REZ[ctx.class or ""] then
        add("rez", 1)
    else
        if not ctx.grouped then add("invite", 25) end
        local otherZone = ctx.zone and ctx.zone ~= "" and ctx.zone ~= ctx.myZone
        if otherZone and not ctx.dead then add("summon", ctx.class == "WARLOCK" and 40 or 20) end
        if ctx.itemId and ctx.itemName then
            local q = ctx.quality or 0
            add("gift", q >= 4 and 50 or q == 3 and 35 or q == 2 and 12 or 0)
        end
        if (ctx.gold or 0) >= 10000 then add("gold", 25) end
        if not ctx.dead then add("carry", 15) end
    end
    if #bait == 0 then add("invite", 1) end

    local total = 0
    for _, b in ipairs(bait) do total = total + b.w end
    local roll, kind = rnd() * total, bait[#bait].kind
    for _, b in ipairs(bait) do
        if roll < b.w then kind = b.kind break end
        roll = roll - b.w
    end

    local snd = SOUNDKIT and (SOUNDKIT.IG_PLAYER_INVITE or SOUNDKIT.IG_MAINMENU_OPEN)
    local text
    if kind == "invite" then
        text = string.format(L("%s inviterer dig med i gruppen. Vil du med?"), who)
    elseif kind == "rez" then
        text = string.format(L("%s vil rezze dig. Vil du op at stå?"), who)
    elseif kind == "summon" then
        text = string.format(L("%s vil summone dig til %s. Vil du med?"), who, ctx.zone)
    elseif kind == "gift" then
        text = string.format(L("%s vil give dig %s. Vil du have den?"), who, ItemText(ctx))
    elseif kind == "gold" then
        text = string.format(L("%s vil give dig %s. Vil du have dem?"), who, Coins(ctx.gold))
    else
        kind = "carry"
        text = string.format(L("%s tilbyder at carry dig gennem en dungeon. Er du frisk?"), who)
    end
    return { kind = kind, text = text, sound = snd }
end

-- Det bedste item i din taske (lokkemad til en gave): højeste kvalitet, mindst grøn
local function BestBagItem()
    local best
    for bag = 0, 4 do
        local n = 0
        if C_Container and C_Container.GetContainerNumSlots then n = C_Container.GetContainerNumSlots(bag) or 0
        elseif GetContainerNumSlots then n = GetContainerNumSlots(bag) or 0 end
        for slot = 1, n do
            local id
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                id = info and Plain(info.itemID)
            elseif GetContainerItemInfo then
                id = Plain(select(10, GetContainerItemInfo(bag, slot)))
            end
            if id then
                local name, _, q = C.GAME.ItemInfo(id)
                name, q = Plain(name), Plain(q)
                if name and q and q >= 2 and q <= 5 and (not best or q > best.q) then best = { id = id, name = name, q = q } end
            end
        end
    end
    return best
end

-- =============================================================================
-- Popuppen: en stor JA-knap, der dukker op lige under musen, og en lille "nej" i hjørnet.
-- Først står lokkematen, men i samme øjeblik du trykker ned på JA, skifter spørgsmålet til
-- "HAR DU STOMI?". Slipper du knappen, er det et ja. Vil du slippe, skal du ramme den lille nej.
-- Knapperne gør aldrig noget i spillet, de svarer kun fælden.
-- =============================================================================
local popup
local current        -- fælden, der vises lige nu: { from, nonce, t, bait }
local pending        -- fælden, der venter på, at kampen slutter

local W, H = 340, 150
local YES_W, YES_H, YES_Y = 220, 56, 30     -- JA-knappens størrelse og afstand fra bunden

local function TryFrame(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
    return CreateFrame(kind, name, parent)
end

-- Hvor popuppen skal stå, så midten af JA-knappen er lige under musen.
-- Returnerer midtpunktet (x, y) i UIParents koordinater.
function Stomi.PopupCenter(cx, cy, scale, sw, sh)
    scale = (scale and scale > 0) and scale or 1
    local x, y = cx / scale, cy / scale
    y = y + (H / 2 - (YES_Y + YES_H / 2))
    -- Hold den inde på skærmen
    if sw then x = math.max(W / 2, math.min(sw - W / 2, x)) end
    if sh then y = math.max(H / 2, math.min(sh - H / 2, y)) end
    return x, y
end

local function Place()
    popup:ClearAllPoints()
    local cx, cy
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    local sw = UIParent.GetWidth and UIParent:GetWidth()
    local sh = UIParent.GetHeight and UIParent:GetHeight()
    sw, sh = tonumber(sw), tonumber(sh)
    if not (sw and sw > 0) then sw = nil end
    if not (sh and sh > 0) then sh = nil end
    local x, y = Stomi.PopupCenter(tonumber(cx) or 0, tonumber(cy) or 0, tonumber(scale) or 1, sw, sh)
    popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    popup.x, popup.y = x, y
end

local Resolve

local function Swap()
    if not current or popup.swapped then return end
    popup.swapped = true
    popup.text:SetText(L("HAR DU STOMI?"))
end
Stomi.Swap = Swap

local function BuildPopup()
    if popup then return popup end
    local f = TryFrame("Frame", "WastedCoastStomiPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, H)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetToplevel then f:SetToplevel(true) end
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    -- Samme ramme som spillets egne popups
    local backdrop = _G.BACKDROP_DIALOG_32_32 or {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }
    if f.SetBackdrop then pcall(f.SetBackdrop, f, backdrop) end

    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.text:SetWidth(W - 40)
    f.text:SetPoint("TOP", f, "TOP", 0, -20)
    f.text:SetJustifyH("CENTER")

    -- Den store JA-knap
    local yes = TryFrame("Button", nil, f, "UIPanelButtonTemplate")
    yes:SetSize(YES_W, YES_H)
    yes:SetPoint("BOTTOM", f, "BOTTOM", 0, YES_Y)
    yes:SetText(L("JA!"))
    local fs = yes.GetFontString and yes:GetFontString()
    if fs and fs.SetFontObject and _G.GameFontNormalHuge then fs:SetFontObject(_G.GameFontNormalHuge) end
    yes:RegisterForClicks("LeftButtonUp")
    f.yes = yes

    -- Den lille nej: et diskret tekstlink i hjørnet
    local no = CreateFrame("Button", nil, f)
    no:SetSize(30, 14)
    no:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    no.label = no:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    no.label:SetPoint("CENTER", no, "CENTER", 0, 0)
    no.label:SetText(L("nej"))
    no:RegisterForClicks("LeftButtonUp")
    f.no = no

    -- Musen ned på JA: spørgsmålet skifter med det samme. Slip = ja.
    yes:SetScript("OnMouseDown", function() Swap() end)
    yes:SetScript("OnClick", function()
        if not f.swapped then Swap() return end   -- uden musen ned (fx tastatur): spørg først
        Resolve("y")
    end)
    no:SetScript("OnClick", function() Resolve(f.swapped and "n" or "d") end)

    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + (elapsed or 0)
        if self.t >= Stomi.TIMEOUT then Resolve("x") end
    end)
    -- Escape og andet, der lukker popuppen, tæller som "ignoreret"
    f:SetScript("OnHide", function() if current then Resolve("x") end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "WastedCoastStomiPopup") end
    f:Hide()
    popup = f
    Stomi.popup = f
    return f
end

local function ShowTrap(trap)
    BuildPopup()
    current = trap
    popup.swapped, popup.t = false, 0
    popup.text:SetText(trap.bait.text)
    Place()
    popup:Show()
    if trap.bait.sound and PlaySound then pcall(PlaySound, trap.bait.sound) end
end

-- =============================================================================
-- Log, beskeder og annoncering
-- =============================================================================
local RESULTS = { y = true, n = true, d = true, x = true }

local function Announce(e)
    local db = WastedCoastDB
    local me = db.me
    if e.r == "y" then
        if e.to == me then
            ns.Toast({ kind = "stomi", head = L("STOMI!"), title = L("Du sagde ja. Du har stomi i 24 timer."),
                       text = string.format(L("%s satte fælden. Posen sidder på dit ikon til i morgen."), Name(e.from)),
                       icon = Stomi.ICON, dur = 7, sound = "achievement", friend = e.from })
            Print(string.format(L("|cffd9b38cDu har fået stomi af %s!|r Den sidder der i 24 timer."), Name(e.from)))
        else
            local by = (e.from == me) and L("dig") or Name(e.from)
            ns.Toast({ kind = "stomi", head = L("STOMI!"), title = string.format(L("%s har fået stomi!"), Name(e.to)),
                       text = string.format(L("%s sagde ja til \"HAR DU STOMI?\" i en fælde fra %s. Posen sidder i 24 timer."), Name(e.to), by),
                       icon = Stomi.ICON, dur = 7, sound = (e.from == me) and "achievement" or nil, friend = e.to })
            if e.from == me or db.settings.announce then
                Print(string.format(L("|cffd9b38c%s har fået stomi af %s!|r 24 timer med pose."), Name(e.to), by))
            end
        end
    elseif e.from == me and e.to ~= me then
        if e.r == "n" then
            Print(string.format(L("%s så spørgsmålet og sagde nej. Snydt!"), Name(e.to)))
        elseif e.r == "d" then
            Print(string.format(L("%s takkede nej til lokkematen og slap for stomi."), Name(e.to)))
        else
            Print(string.format(L("%s lukkede stomi-fælden uden at svare."), Name(e.to)))
        end
    end
end

-- Tilføjer et svar til loggen. Returnerer true, hvis det var nyt.
function Stomi.Record(e)
    local _, st = DB()
    if not e or not e.id or not RESULTS[e.r] or not ROSTER_SET[e.from] or not ROSTER_SET[e.to] then return false end
    for _, old in ipairs(st.log) do
        if old.id == e.id then return false end
    end
    st.log[#st.log + 1] = e
    table.sort(st.log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #st.log > LOG_MAX do table.remove(st.log, 1) end
    if not e.demo and math.abs(time() - (e.t or 0)) < FRESH then Announce(e) end
    if ns.Bar and ns.Bar.MarkDirty then ns.Bar.MarkDirty() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function Serialize(e)
    return table.concat({ "XT", e.to, e.from, tostring(e.nonce or ""), e.r, tostring(e.t or 0), e.bait or "" }, ";")
end

-- Offeret har svaret (eller lukket popuppen)
Resolve = function(result)
    if not current then return end
    local trap = current
    current = nil
    if popup and popup:IsShown() then popup:Hide() end
    local db = WastedCoastDB
    local e = { id = trap.from .. "-" .. trap.nonce, from = trap.from, to = db.me, nonce = trap.nonce,
                r = result, t = time(), bait = trap.bait.kind }
    C.Send(Serialize(e), true)
    Stomi.Record(e)
    if result == "n" then
        Print(string.format(L("Det var en stomi-fælde fra %s. Du sagde nej. Godt reddet."), Name(trap.from)))
    elseif result == "d" or result == "x" then
        Print(string.format(L("Puha. Det var en stomi-fælde fra %s, og du slap."), Name(trap.from)))
    end
end
Stomi.Resolve = function(r) Resolve(r) end

local seen = {}
local lastFrom = {}

local function Context(t)
    local ctx = {
        char = t[5] ~= "" and t[5] or Name(t[2]), class = t[6], zone = t[7],
        itemId = tonumber(t[8]), quality = tonumber(t[9]), gold = tonumber(t[10]) or 0,
        itemName = (t[11] and t[11] ~= "") and t[11]:sub(1, 50) or nil,
    }
    if not ctx.itemName then ctx.itemId = nil end
    ctx.myZone = GetZoneText and Plain(GetZoneText()) or ""
    ctx.dead = UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost("player")) and true or false
    ctx.grouped = IsInGroup and Plain(IsInGroup()) and true or false
    return ctx
end

local function InCombat()
    return (UnitAffectingCombat and Plain(UnitAffectingCombat("player"))) and true or false
end

-- En fælde til dig
local function OnTrap(t)
    local db = WastedCoastDB
    local from, to, nonce = t[2], t[3], t[4]
    if not ROSTER_SET[from] or from == db.me or to ~= db.me or not nonce or nonce == "" then return end
    if db.settings.stomi == false then return end
    local key = from .. "-" .. nonce
    if seen[key] then return end
    seen[key] = true
    -- Højst én fælde pr. cooldown fra samme ven (også hvis giverens addon er pillet ved), og kun én ad gangen
    if lastFrom[from] and GetTime() - lastFrom[from] < Stomi.COOLDOWN / 2 then return end
    if current or pending then return end
    lastFrom[from] = GetTime()
    local trap = { from = from, nonce = nonce, t = t, at = GetTime() }
    if InCombat() then
        pending = trap
        return
    end
    -- Et lille øjeblik, så det ikke føles som et svar på noget
    C_Timer.After(0.4 + math.random() * 1.2, function()
        if current then return end
        if InCombat() then pending = trap return end
        trap.bait = Stomi.Bait(Context(t))
        ShowTrap(trap)
    end)
end

function Stomi.OnCombatEnd()
    local trap = pending
    pending = nil
    if not trap or current or GetTime() - trap.at > 600 then return end
    C_Timer.After(1 + math.random() * 2, function()
        if current or InCombat() then return end
        trap.bait = Stomi.Bait(Context(trap.t))
        ShowTrap(trap)
    end)
end

function ns.HandleStomiMessage(kind, t)
    local db = WastedCoastDB
    if kind == "XS" then
        OnTrap(t)
    elseif kind == "XT" then
        local to, from, at = t[2], t[3], tonumber(t[6])
        if to and to ~= db.me and at and RESULTS[t[5]] and t[4] and t[4] ~= "" then
            Stomi.Record({ id = from .. "-" .. t[4], from = from, to = to, nonce = t[4], r = t[5],
                           t = math.min(at, time()), bait = (t[7] ~= "" and t[7]) or nil })
        end
    end
end

-- Ved synk: de seneste svar, du har været med i (dubletter filtreres fra hos modtageren)
function Stomi.SendLog()
    local db, st = DB()
    local sent = 0
    for i = #st.log, 1, -1 do
        local e = st.log[i]
        if not e.demo and e.nonce and (e.to == db.me or e.from == db.me) and time() - (e.t or 0) < 14 * 86400 then
            C.Send(Serialize(e))
            sent = sent + 1
            if sent >= 15 then break end
        end
    end
end

-- =============================================================================
-- Send en fælde
-- =============================================================================
function ns.StomiTrap(target)
    local db, st = DB()
    if not db.me then
        Print(L("Opret eller deltag først i en gruppe (|cffffd100/wc4ever gruppe|r)."))
        return false
    end
    if not ROSTER_SET[target] then return false end
    if target == db.me then
        Print(L("Du kan ikke give dig selv stomi. Det kræver en ven."))
        return false
    end
    local wait = (st.lastSent or 0) + Stomi.COOLDOWN - time()
    if wait > 0 then
        Print(string.format(L("Rolig nu. Du kan sætte en ny stomi-fælde om %s."), Hours(wait)))
        return false
    end
    if Stomi.Has(target) then
        Print(string.format(L("%s har allerede stomi (%s tilbage). Én pose ad gangen."), Name(target), Hours(Stomi.Remaining(target))))
        return false
    end
    if C.IsOnline and not C.IsOnline(target) then
        Print(string.format(L("%s er ikke online. Fælden virker kun, når vennen er der."), Name(target)))
        return false
    end
    local item = BestBagItem()
    local gold = (GetMoney and Plain(GetMoney())) or 0
    -- Et beløb, der er til at tro på: en tiendedel af dit guld, højst 50g, i hele guld
    local gift = math.min(50, math.floor(gold / 10 / 10000)) * 10000
    local nonce = tostring(math.random(100000, 999999))
    local msg = table.concat({ "XS", db.me, target, nonce, Clean(Plain(UnitName("player")) or ""),
        select(2, UnitClass("player")) or "", Clean(GetZoneText and Plain(GetZoneText()) or ""):sub(1, 30),
        item and tostring(item.id) or "", item and tostring(item.q) or "", tostring(gift),
        item and Clean(item.name):sub(1, 50) or "" }, ";")
    C.Send(msg, true)
    st.lastSent = time()
    Print(string.format(L("Stomi-fælden er sat. Nu venter vi bare på, at %s siger ja..."), Name(target)))
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- =============================================================================
-- Demo, nulstilling og kommandoer
-- =============================================================================
function Stomi.MakeDemo()
    local db, st = DB()
    local others = {}
    for _, name in ipairs(ROSTER) do if name ~= db.me then others[#others + 1] = name end end
    if #others < 2 then return end
    local now = time()
    Stomi.Record({ id = "demo-S-1", from = db.me or others[2], to = others[1], r = "y", t = now - 3 * 3600, bait = "gift", demo = true })
    Stomi.Record({ id = "demo-S-2", from = others[1], to = others[2], r = "n", t = now - 30 * 3600, bait = "invite", demo = true })
end

function Stomi.ClearDemo()
    local _, st = DB()
    for i = #st.log, 1, -1 do
        if st.log[i].demo then table.remove(st.log, i) end
    end
end

function Stomi.Reset()
    local _, st = DB()
    wipe(st.log)
    st.lastSent = nil
end

-- En prøve på popuppen (kun hos dig selv, intet sendes, og et ja giver ikke stomi)
function Stomi.Test()
    if current then return end
    local db = WastedCoastDB
    local fake = { "XS", db.me, db.me, "test", "Nickchar", "WARLOCK", "Shattrath City", "28830", "4", "250000", "Dragonspine Trophy" }
    local trap = { from = db.me, nonce = "test", t = fake, at = GetTime(), test = true }
    trap.bait = Stomi.Bait(Context(fake))
    ShowTrap(trap)
    -- Testen må ikke give stomi eller sende noget
    local real = Resolve
    Resolve = function(r)
        Resolve = real
        current = nil
        if popup and popup:IsShown() then popup:Hide() end
        Print(r == "y" and L("Test: du sagde ja. I virkeligheden havde du nu stomi i 24 timer.")
            or L("Test: du slap. Sådan ser fælden ud hos dine venner."))
    end
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
function ns.StomiSlash(cmd, arg)
    if cmd ~= "stomi" and cmd ~= "stoma" then return false end
    local db = WastedCoastDB
    arg = arg or ""
    if arg == "test" then
        Stomi.Test()
    elseif arg == "fra" or arg == "off" or arg == "til" or arg == "on" then
        if arg == "til" or arg == "on" then db.settings.stomi = nil else db.settings.stomi = false end
        Print(L("Stomi-fælder mod dig: ") .. ((db.settings.stomi ~= false) and L("til") or L("fra")))
    elseif arg == "" then
        Print(Stomi.Summary())
        Print(L("Skriv |cffffd100/wc4ever stomi <ven>|r for at sætte en fælde, eller højreklik på vennen under Sjov > Drilleri."))
    else
        local name = FindFriend(arg)
        if name then ns.StomiTrap(name) else Print(L("Hvem? Skriv fx |cffffd100/wc4ever stomi nick|r.")) end
    end
    return true
end

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    if not WastedCoastDB then return end
    if event == "PLAYER_REGEN_ENABLED" then Stomi.OnCombatEnd() end
end)
