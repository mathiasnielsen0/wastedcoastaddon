local _, ns = ...

-- =============================================================================
-- Grupper (v0.10)
--   * Hver spiller har et fast, unikt ID og et navn, man selv vælger (og kan ændre).
--   * En gruppe har en kode som WC-ABCD-EFGH-JKLM-NPQR. Den, der opretter gruppen, er admin
--     og deler koden med vennerne, som indsætter den og er med.
--   * Gruppen har sin egen skjulte kanal, afledt af koden. Beskeder fra spillere, der ikke er
--     med i gruppen, ignoreres (også i guild og party).
--   * Admin kan fjerne et medlem (og tage det ind igen).
--   * De 8 oprindelige venner er gruppen "Wasted Coast" med Mathias som admin. Deres ID er
--     deres navn, og gruppen bruger den gamle kanal, så ældre versioner spiller med.
--
-- Beskeder (felt 2 er altid afsenderens ID, felt 3 gruppens ID):
--   GM;afsender;gruppe;medlem;navn;navn-tid;kom-med-tid   et medlem (afsenderen selv eller videresendt)
--   GW;afsender;gruppe                                    "hvem er med?" - medlemmerne svarer med GM
--   GK;afsender;gruppe;medlem;tid;1|0                     admin fjerner (1) eller genoptager (0) et medlem
--
-- Begrænsning: WoW har ingen kryptografi. Admin-beskeder godtages kun fra karakterer, der er set
-- logge ind som admin (et livstegn sendt fra karakteren selv), og admins ID står i koden. Det
-- holder blandt venner, men en, der virkelig vil snyde, kan efterligne admin.
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name
local route = ns.route

local ALPHA = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   -- 32 tegn uden 0/O og 1/I
local LEGACY = {
    id = "WASTEDCOAST", code = "WC-WASTED-COAST", admin = "Mathias", name = "Wasted Coast",
    channel = "WC4Lsync", password = "wastedcoast",   -- den kanal, v0.9 og ældre bruger
}
local LEGACY_SET = {}
for i, n in ipairs(ns.LEGACY_ROSTER) do LEGACY_SET[n] = i end

local MAX_NAME = 24   -- bytes (æ, ø og å fylder to)

local function DB() return WastedCoastDB end
local function Group() return WastedCoastDB and WastedCoastDB.group end

local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Et navn må ikke have ; (skilletegn i beskeder) eller | (farvekoder) og skal være kort
local function CleanName(s)
    s = Trim(tostring(s or ""):gsub("[;|%c]", ""):gsub("%s+", " "))
    if s == "" then return nil end
    if #s > MAX_NAME then
        s = s:sub(1, MAX_NAME)
        -- Klip ikke et æ/ø/å over på midten
        local tail = s:match("[\192-\247][\128-\191]*$")
        if tail then
            local lead = tail:byte(1)
            local need = (lead >= 240 and 4) or (lead >= 224 and 3) or 2
            if #tail < need then s = s:sub(1, #s - #tail) end
        end
        s = Trim(s)
    end
    return s ~= "" and s or nil
end
ns.CleanMemberName = CleanName

local randomMixed = false
local function RandomChars(n)
    if not randomMixed then
        -- Bland lidt, hvis klienten ikke selv har seedet math.random
        for _ = 1, (math.floor((GetTime() or 0) * 1000) + (time() or 0)) % 97 do math.random() end
        randomMixed = true
    end
    local t = {}
    for i = 1, n do
        local k = math.random(1, #ALPHA)
        t[i] = ALPHA:sub(k, k)
    end
    return table.concat(t)
end

local function ValidId(id)
    if type(id) ~= "string" then return false end
    if LEGACY_SET[id] then return true end
    return #id == 9 and id:match("^u[" .. ALPHA .. "]+$") ~= nil
end
ns.ValidMemberId = ValidId

local function NewId() return "u" .. RandomChars(8) end

local function FormatCode(key, adminPart)
    local s = key .. adminPart
    return "WC-" .. s:sub(1, 4) .. "-" .. s:sub(5, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16)
end

-- Læser en indsat kode. Returnerer { id, admin, code, legacy } eller nil
local function ParseCode(text)
    local s = tostring(text or ""):upper():gsub("[^%w]", "")
    if s == "WCWASTEDCOAST" or s == "WASTEDCOAST" then
        return { id = LEGACY.id, admin = LEGACY.admin, code = LEGACY.code, legacy = true }
    end
    if #s == 18 and s:sub(1, 2) == "WC" then s = s:sub(3) end
    if #s ~= 16 or not s:match("^[" .. ALPHA .. "]+$") then return nil end
    local key, adminPart = s:sub(1, 8), s:sub(9, 16)
    return { id = key, admin = "u" .. adminPart, code = FormatCode(key, adminPart) }
end
ns.ParseGroupCode = ParseCode

local function IsKicked(id)
    local g = Group()
    local k = g and g.kicked and g.kicked[id]
    return (k and k.on) and true or false
end

local function IsMember(id)
    local g = Group()
    return (g and g.members[id] and not IsKicked(id)) and true or false
end

function ns.MemberName(id)
    local g = Group()
    local m = g and g.members[id]
    return m and m.n or nil
end

function ns.IsGroupAdmin()
    local g = Group()
    return (g and DB().me and g.admin == DB().me) and true or false
end

function ns.GroupName(g)
    g = g or Group()
    if not g then return nil end
    if g.legacy then return LEGACY.name end
    local admin = ns.MemberName(g.admin)
    return admin and (admin .. "s gruppe") or "Jeres gruppe"
end

-- =============================================================================
-- Vennelisten (ROSTER) og den skjulte kanal følger gruppen
-- =============================================================================
local function Rebuild()
    wipe(ROSTER)
    wipe(ROSTER_SET)
    local g = Group()
    if not g then return end
    local list = {}
    for id, m in pairs(g.members) do
        if not IsKicked(id) then list[#list + 1] = { id = id, m = m } end
    end
    table.sort(list, function(a, b)
        local la, lb = g.legacy and LEGACY_SET[a.id] or 100, g.legacy and LEGACY_SET[b.id] or 100
        if la ~= lb then return la < lb end
        local ja, jb = a.m.j or 0, b.m.j or 0
        if ja ~= jb then return ja < jb end
        return a.id < b.id
    end)
    local me = DB().me
    for i = 1, math.min(#list, ns.MAX_MEMBERS) do ROSTER[i] = list[i].id end
    -- Er gruppen fuld, får du selv den sidste plads (du skal altid kunne se dig selv)
    if me and IsMember(me) and #list > ns.MAX_MEMBERS then
        local found = false
        for _, id in ipairs(ROSTER) do if id == me then found = true end end
        if not found then ROSTER[#ROSTER] = me end
    end
    for _, id in ipairs(ROSTER) do ROSTER_SET[id] = true end
    ns.groupOverflow = math.max(0, #list - ns.MAX_MEMBERS)
end
ns.RebuildRoster = Rebuild

local function LeaveChannel(name)
    if name and LeaveChannelByName and ((GetChannelName(name)) or 0) > 0 then pcall(LeaveChannelByName, name) end
end

local function UseChannel(g)
    local old = route.CHANNEL
    if g then
        if g.legacy then
            route.CHANNEL, route.PASSWORD = LEGACY.channel, LEGACY.password
        else
            route.CHANNEL = "WCg" .. g.id
            route.PASSWORD = (g.admin or ""):sub(2):lower()
        end
    end
    if old and old:lower() ~= route.CHANNEL:lower() then
        LeaveChannel(old)
        wipe(route.shared)
        wipe(route.whisper)
    end
    if not g then LeaveChannel(route.CHANNEL) end
end

local function NewGroupRecord(info)
    return {
        id = info.id, admin = info.admin, code = info.code, legacy = info.legacy or nil,
        members = {}, kicked = {}, owners = {}, joined = time(),
    }
end

-- De 8 oprindelige venner bliver til gruppen "Wasted Coast". Kaldes ved login.
local function MigrateLegacy(db)
    local g = NewGroupRecord({ id = LEGACY.id, admin = LEGACY.admin, code = LEGACY.code, legacy = true })
    for i, n in ipairs(ns.LEGACY_ROSTER) do g.members[n] = { n = n, nt = 0, j = i } end
    -- Karakterer, vi allerede kender, regnes for at høre til deres ven (bruges til admin-tjek)
    for char, friend in pairs(db.chars or {}) do
        if LEGACY_SET[friend] then g.owners[char] = friend end
    end
    return g
end

function ns.InitGroup()
    local db = DB()
    if not db.group and db.me and LEGACY_SET[db.me] then
        db.group = MigrateLegacy(db)
        db.myId = db.myId or db.me
        db.myName = db.myName or db.me
    end
    local g = db.group
    if g then
        g.members, g.kicked, g.owners = g.members or {}, g.kicked or {}, g.owners or {}
        db.me = db.me or db.myId
        if db.me and IsKicked(db.me) then
            db.group, db.me, g = nil, nil, nil
        elseif db.me then
            local m = g.members[db.me]
            if not m then
                g.members[db.me] = { n = db.myName or Name(db.me), nt = time(), j = time() }
            elseif db.myName and m.n ~= db.myName then
                db.myName = m.n
            end
            g.owners[UnitName("player")] = g.owners[UnitName("player")] or db.me
        end
    else
        db.me = nil
    end
    UseChannel(db.group)
    Rebuild()
end

-- =============================================================================
-- Netværk
-- =============================================================================
local function MemberMsg(id)
    local g = Group()
    local m = g.members[id]
    return table.concat({ "GM", DB().me, g.id, id, m.n or id, m.nt or 0, m.j or 0 }, ";")
end

-- Send dig selv og de medlemmer, du kender (så de, der ikke er online samtidig, finder hinanden).
-- Admin sender også, hvem der er fjernet.
local lastInfo = -100
function ns.SendGroupInfo(force)
    local db, g = DB(), Group()
    if not g or not db.me or not IsMember(db.me) then return end
    if not force and GetTime() - lastInfo < 20 then return end
    lastInfo = GetTime()
    C.Send(MemberMsg(db.me), true)
    for id in pairs(g.members) do
        if id ~= db.me and not IsKicked(id) then C.Send(MemberMsg(id)) end
    end
    if g.admin == db.me then
        for id, k in pairs(g.kicked) do
            C.Send(table.concat({ "GK", db.me, g.id, id, k.t or 0, k.on and 1 or 0 }, ";"))
        end
    end
end

local lastAsk = -100
function ns.UnknownMember(id)
    local db, g = DB(), Group()
    if not g or not db.me or not ValidId(id) or IsKicked(id) or g.members[id] then return end
    if GetTime() - lastAsk < 60 then return end
    lastAsk = GetTime()
    C.Send("GW;" .. db.me .. ";" .. g.id)
end

-- Et livstegn sendt fra karakteren selv: karakteren hører til medlemmet (den første vinder)
function ns.NoteCharOwner(friend, char, sender)
    local g = Group()
    if not g or not char or char == "" or not sender or not IsMember(friend) then return end
    local from = (Ambiguate and Ambiguate(sender, "none")) or sender:match("^[^%-]+") or sender
    if from ~= char then return end
    if not g.owners[char] then g.owners[char] = friend end
end

local function Refresh()
    if ns.RefreshUI then ns.RefreshUI() end
    if ns.RefreshGroupWindow then ns.RefreshGroupWindow() end
end

local function Removed(byWhom)
    local db = DB()
    local g = Group()
    Print("|cffff6060Du er blevet fjernet fra " .. (ns.GroupName(g) or "gruppen") .. "|r" .. (byWhom and (" af " .. byWhom) or "") .. ".")
    db.group, db.me = nil, nil
    UseChannel(nil)
    Rebuild()
    Refresh()
end

local lastWhoReply = -100
function ns.OnGroupMessage(kind, t, sender)
    local db, g = DB(), Group()
    if not g or t[3] ~= g.id then return end
    local from = t[2]
    if not ValidId(from) or IsKicked(from) then return end

    if kind == "GM" then
        local id, name = t[4], CleanName(t[5])
        local nt, j = tonumber(t[6]) or 0, tonumber(t[7]) or 0
        if not ValidId(id) or not name or IsKicked(id) or id == db.me then return end
        -- Nye medlemmer melder sig selv. Kendte medlemmer må videresende andre.
        if from ~= id and not IsMember(from) then return end
        local m = g.members[id]
        if not m then
            g.members[id] = { n = name, nt = nt, j = (j > 0) and j or time() }
            Rebuild()
            if from == id then Print("|cffffd100" .. name .. "|r er kommet med i " .. ns.GroupName(g) .. ".") end
            if ns.groupOverflow and ns.groupOverflow > 0 and ROSTER_SET[db.me] then
                Print("Gruppen har nu flere end " .. ns.MAX_MEMBERS .. " medlemmer. Kun de første " .. ns.MAX_MEMBERS .. " vises.")
            end
            Refresh()
        elseif nt > (m.nt or 0) then
            local old = m.n
            m.n, m.nt = name, nt
            if (m.j or 0) == 0 and j > 0 then m.j = j end
            if old ~= name and from == id then Print((old or id) .. " hedder nu |cffffd100" .. name .. "|r.") end
            Refresh()
        end

    elseif kind == "GW" then
        if db.me and IsMember(db.me) and GetTime() - lastWhoReply > 20 then
            lastWhoReply = GetTime()
            C_Timer.After(1 + math.random() * 4, function() ns.SendGroupInfo(true) end)
        end

    elseif kind == "GK" then
        local id, at, on = t[4], tonumber(t[5]), t[6] == "1"
        if from ~= g.admin or from == db.me or not ValidId(id) or id == g.admin or not at then return end
        local char = (Ambiguate and Ambiguate(sender or "", "none")) or tostring(sender or ""):match("^[^%-]+")
        if g.owners[char] ~= g.admin then return end
        local k = g.kicked[id]
        if k and (k.t or 0) >= at then return end
        g.kicked[id] = { on = on, t = at }
        if id == db.me then
            if on then Removed(Name(g.admin)) end
            return
        end
        Rebuild()
        if on and g.members[id] then Print(Name(id) .. " er fjernet fra gruppen af " .. Name(g.admin) .. ".") end
        Refresh()
    end
end

-- =============================================================================
-- Handlinger: opret, deltag, forlad, skift navn, fjern medlem
-- =============================================================================
local function Start(g, myId)
    local db = DB()
    UseChannel(nil)   -- forlad den gamle kanal
    db.group = g
    db.myId = myId
    db.me = myId
    g.members[myId] = { n = db.myName, nt = time(), j = time() }
    g.owners[UnitName("player")] = myId
    UseChannel(g)
    Rebuild()
    route.channelOK = true
    route.Join()
    ns.SendGroupInfo(true)
    C.Send("GW;" .. myId .. ";" .. g.id)
    ns.SetMe(myId)
    Refresh()
end

function ns.SetMyName(text)
    local db = DB()
    local name = CleanName(text)
    if not name then
        Print("Skriv et navn (højst " .. MAX_NAME .. " tegn, uden ; og |).")
        return false
    end
    db.myName = name
    local g = Group()
    if g and db.me and g.members[db.me] then
        local m = g.members[db.me]
        if m.n ~= name then
            m.n, m.nt = name, time()
            ns.SendGroupInfo(true)
            Print("Du hedder nu |cffffd100" .. name .. "|r.")
        end
    end
    Refresh()
    return true
end

function ns.CreateGroup()
    local db = DB()
    if not db.myName then Print("Skriv først dit navn.") return false end
    local myId = (db.myId and not LEGACY_SET[db.myId]) and db.myId or NewId()
    local key = RandomChars(8)
    local info = { id = key, admin = myId, code = FormatCode(key, myId:sub(2)) }
    Start(NewGroupRecord(info), myId)
    Print("Ny gruppe oprettet. Del koden med dine venner: |cffffd100" .. info.code .. "|r")
    return true
end

function ns.JoinGroup(text)
    local db = DB()
    if not db.myName then Print("Skriv først dit navn.") return false end
    local info = ParseCode(text)
    if not info then
        Print("Koden ser forkert ud. Den ligner |cffffd100WC-ABCD-EFGH-JKLM-NPQR|r.")
        return false
    end
    local g = Group()
    if g and g.id == info.id then Print("Du er allerede med i den gruppe.") return false end
    local myId
    if info.legacy then
        -- En af de oprindelige venner? Så får du dit gamle ID og al din historik tilbage.
        for _, n in ipairs(ns.LEGACY_ROSTER) do
            if n:lower() == db.myName:lower() then myId = n end
        end
        if not myId then
            Print("Tip: Er du en af de oprindelige venner, så skriv dit navn præcis som før (fx Nick), og deltag igen.")
        end
    end
    if not myId then
        myId = (db.myId and not LEGACY_SET[db.myId]) and db.myId or NewId()
    end
    local rec = NewGroupRecord(info)
    if info.legacy then rec = MigrateLegacy(db) end
    Start(rec, myId)
    Print("Du er med i " .. ns.GroupName(rec) .. ". Det tager et øjeblik, før de andre dukker op.")
    return true
end

function ns.LeaveGroup()
    local db = DB()
    if not db.group then return end
    local name = ns.GroupName()
    UseChannel(nil)
    db.group, db.me = nil, nil
    Rebuild()
    Print("Du har forladt " .. name .. ". Du kan komme med igen med koden.")
    Refresh()
end

function ns.KickMember(id, on)
    local db, g = DB(), Group()
    if not g or g.admin ~= db.me or id == db.me or not g.members[id] then return end
    local at = time()
    local k = g.kicked[id]
    if k and (k.t or 0) >= at then at = k.t + 1 end
    g.kicked[id] = { on = on and true or false, t = at }
    C.Send(table.concat({ "GK", db.me, g.id, id, at, on and 1 or 0 }, ";"), true)
    Rebuild()
    if on then
        Print(Name(id) .. " er fjernet fra gruppen.")
    else
        Print(Name(id) .. " kan komme med igen (med koden).")
    end
    Refresh()
end

function ns.GroupStatusText()
    local db, g = DB(), Group()
    if not g or not db.me then
        return "|cffff6060Du er ikke med i en gruppe endnu.|r Opret en, eller indsæt en vens kode."
    end
    local admin = (g.admin == db.me) and "dig" or (Name(g.admin) or "?")
    return string.format("Du er |cffffd100%s|r i |cffffd100%s|r (admin: %s).  Kode: |cffffd100%s|r",
        Name(db.me), ns.GroupName(g), admin, g.code or "?")
end

-- =============================================================================
-- Vinduet: navn, opret/deltag, kode og medlemmer
-- =============================================================================
local MEMBER_ROWS = 12
local ui = {}

local function MakeEdit(parent, w, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or 40)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local function Label(parent, text, template)
    local fs = C.Txt(parent, template or "GameFontNormal")
    fs:SetText(text or "")
    return fs
end

local function BuildWindow()
    local COL_BG, COL_GOLD, COL_BTN, COL_BORDER = C.COL_BG, C.COL_GOLD, C.COL_BTN, C.COL_BORDER
    local p = C.MakeBox("Frame", UIParent, COL_BG, COL_GOLD, "WastedCoastGroup")
    p:SetSize(440, 500)
    p:SetPoint("CENTER", 0, 40)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if C.AddShadow then C.AddShadow(p, 8) end
    table.insert(UISpecialFrames, "WastedCoastGroup")

    local close = C.MakeButton(p, 22, 22, "x", function() p:Hide() end)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)

    ui.title = Label(p, "", "GameFontNormalLarge")
    ui.title:SetPoint("TOP", p, "TOP", 0, -14)
    ui.title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    ui.sub = Label(p, "", "GameFontHighlightSmall")
    ui.sub:SetPoint("TOP", ui.title, "BOTTOM", 0, -4)
    ui.sub:SetWidth(400)
    ui.sub:SetJustifyH("CENTER")
    ui.sub:SetTextColor(0.6, 0.6, 0.66)

    -- Dit navn
    local nh = Label(p, "Dit navn")
    nh:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -62)
    ui.nameEdit = MakeEdit(p, 240, 40)
    ui.nameEdit:SetPoint("TOPLEFT", nh, "BOTTOMLEFT", 6, -4)
    local function SaveName()
        if ns.SetMyName(ui.nameEdit:GetText()) then ui.nameEdit:ClearFocus() end
    end
    local saveName = C.MakeButton(p, 120, 22, "Gem navn", SaveName)
    saveName:SetPoint("LEFT", ui.nameEdit, "RIGHT", 10, 0)
    ui.nameEdit:SetScript("OnEnterPressed", SaveName)
    local nn = Label(p, "Det navn, vennerne ser. Du kan altid ændre det. Bag navnet har du et fast ID.", "GameFontHighlightSmall")
    nn:SetPoint("TOPLEFT", ui.nameEdit, "BOTTOMLEFT", -6, -4)
    nn:SetTextColor(0.5, 0.5, 0.56)

    -- Uden gruppe: deltag eller opret
    local join = CreateFrame("Frame", nil, p)
    join:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -140)
    join:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    ui.join = join
    local jh = Label(join, "Deltag i en vens gruppe")
    jh:SetPoint("TOPLEFT", join, "TOPLEFT", 20, 0)
    local js = Label(join, "Indsæt koden, du har fået (Ctrl+V):", "GameFontHighlightSmall")
    js:SetPoint("TOPLEFT", jh, "BOTTOMLEFT", 0, -4)
    js:SetTextColor(0.6, 0.6, 0.66)
    ui.codeIn = MakeEdit(join, 240, 40)
    ui.codeIn:SetPoint("TOPLEFT", js, "BOTTOMLEFT", 6, -4)
    local function Join()
        if ns.SetMyName(ui.nameEdit:GetText()) and ns.JoinGroup(ui.codeIn:GetText()) then
            ui.codeIn:SetText("")
            ui.codeIn:ClearFocus()
        end
    end
    local joinBtn = C.MakeButton(join, 120, 22, "Deltag", Join)
    joinBtn:SetPoint("LEFT", ui.codeIn, "RIGHT", 10, 0)
    ui.codeIn:SetScript("OnEnterPressed", Join)

    local ch = Label(join, "Eller start en ny gruppe")
    ch:SetPoint("TOPLEFT", jh, "BOTTOMLEFT", 0, -70)
    local cs = Label(join, "Du bliver admin og får en kode, du sender til dine venner.", "GameFontHighlightSmall")
    cs:SetPoint("TOPLEFT", ch, "BOTTOMLEFT", 0, -4)
    cs:SetTextColor(0.6, 0.6, 0.66)
    local createBtn = C.MakeButton(join, 160, 24, "Opret gruppe", function()
        if ns.SetMyName(ui.nameEdit:GetText()) then ns.CreateGroup() end
    end)
    createBtn:SetPoint("TOPLEFT", cs, "BOTTOMLEFT", 0, -8)

    -- Med gruppe: kode og medlemmer
    local inG = CreateFrame("Frame", nil, p)
    inG:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -140)
    inG:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    ui.inGroup = inG
    local kh = Label(inG, "Gruppens kode")
    kh:SetPoint("TOPLEFT", inG, "TOPLEFT", 20, 0)
    local ks = Label(inG, "Send den til dine venner. Klik i feltet og tryk Ctrl+C for at kopiere.", "GameFontHighlightSmall")
    ks:SetPoint("TOPLEFT", kh, "BOTTOMLEFT", 0, -4)
    ks:SetTextColor(0.6, 0.6, 0.66)
    ui.codeOut = MakeEdit(inG, 260, 40)
    ui.codeOut:SetPoint("TOPLEFT", ks, "BOTTOMLEFT", 6, -4)
    -- Feltet kan ikke ændres: det viser altid koden, markeret og klar til Ctrl+C
    ui.codeOut:SetScript("OnTextChanged", function(self, user)
        local g = Group()
        if user and g then self:SetText(g.code or "") self:HighlightText() end
    end)
    ui.codeOut:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    ui.codeOut:SetScript("OnMouseUp", function(self) self:HighlightText() end)

    local mh = Label(inG, "Medlemmer")
    mh:SetPoint("TOPLEFT", kh, "BOTTOMLEFT", 0, -56)
    ui.memberHead = mh
    ui.rows = {}
    for i = 1, MEMBER_ROWS do
        local row = C.MakeBox("Frame", inG, C.COL_PANEL, COL_BORDER)
        row:SetSize(400, 20)
        row:SetPoint("TOPLEFT", mh, "BOTTOMLEFT", 0, -4 - (i - 1) * 21)
        row.name = C.Field(row, 8, 220, "LEFT", "GameFontHighlight")
        row.note = C.Field(row, 226, 90, "LEFT", "GameFontHighlightSmall")
        row.btn = C.MakeButton(row, 76, 18, "", function()
            if row.id then ns.KickMember(row.id, not IsKicked(row.id)) end
        end)
        row.btn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        ui.rows[i] = row
    end
    ui.leave = C.MakeButton(inG, 140, 22, "Forlad gruppen", function() ns.LeaveGroup() end)
    ui.leave:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 20, 14)
    ui.adminNote = Label(inG, "", "GameFontHighlightSmall")
    ui.adminNote:SetPoint("LEFT", ui.leave, "RIGHT", 12, 0)
    ui.adminNote:SetWidth(250)
    ui.adminNote:SetTextColor(0.5, 0.5, 0.56)

    p:SetScript("OnShow", function() ns.RefreshGroupWindow(true) end)
    ui.frame = p
    return p
end

function ns.RefreshGroupWindow(fillName)
    local p = ui.frame
    if not p or not p:IsShown() then return end
    local db, g = DB(), Group()
    if fillName or not ui.nameEdit:HasFocus() then
        ui.nameEdit:SetText(db.myName or "")
    end
    local inGroup = g and db.me and true or false
    ui.join:SetShown(not inGroup)
    ui.inGroup:SetShown(inGroup)
    if not inGroup then
        ui.title:SetText("Kom i gang")
        ui.sub:SetText("Skriv dit navn, og deltag i en vens gruppe eller start din egen.")
        return
    end

    local isAdmin = g.admin == db.me
    ui.title:SetText(ns.GroupName(g))
    ui.sub:SetText(isAdmin and "Du er admin: du kan fjerne medlemmer." or ("Admin: " .. (Name(g.admin) or "?")))
    ui.codeOut:SetText(g.code or "")

    local list = {}
    for id, m in pairs(g.members) do list[#list + 1] = { id = id, m = m, kicked = IsKicked(id) } end
    table.sort(list, function(a, b)
        if a.kicked ~= b.kicked then return not a.kicked end
        local ja, jb = a.m.j or 0, b.m.j or 0
        if ja ~= jb then return ja < jb end
        return a.id < b.id
    end)
    local active = 0
    for _, e in ipairs(list) do if not e.kicked then active = active + 1 end end
    ui.memberHead:SetText(string.format("Medlemmer (%d)", active))
    for i, row in ipairs(ui.rows) do
        local e = list[i]
        row.id = e and e.id or false
        if e then
            local online = C.IsOnline(e.id) and ROSTER_SET[e.id]
            row.name:SetText((e.kicked and "|cff777777" or "") .. (e.m.n or e.id) .. (e.kicked and "|r" or ""))
            local note = {}
            if e.id == db.me then note[#note + 1] = "dig" end
            if e.id == g.admin then note[#note + 1] = "admin" end
            if e.kicked then note[#note + 1] = "fjernet" elseif online and e.id ~= db.me then note[#note + 1] = "|cff40e060online|r" end
            if not e.kicked and not ROSTER_SET[e.id] then note[#note + 1] = "skjult" end
            row.note:SetText(table.concat(note, ", "))
            local canKick = isAdmin and e.id ~= db.me
            row.btn:SetShown(canKick)
            row.btn.text:SetText(e.kicked and "Genoptag" or "Fjern")
            row:Show()
        else
            row:Hide()
        end
    end
    ui.adminNote:SetText(isAdmin and "Forlader du gruppen, kan du komme med igen med koden og er stadig admin."
        or "Du kan komme med igen med koden.")
end

function ns.ShowGroupWindow()
    local p = ui.frame or BuildWindow()
    p:Show()
    ns.RefreshGroupWindow(true)
end
ns.ShowIdentityPicker = ns.ShowGroupWindow
