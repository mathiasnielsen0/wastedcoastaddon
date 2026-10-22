local _, ns = ...

-- =============================================================================
-- Dueller (v0.9): vundet/tabt og mod hvem, både mellem vennerne og mod andre.
-- Hver ven registrerer kun sine egne dueller og sender dem til de andre, så en duel
-- mellem to venner står hos begge (én gang hver) uden at blive talt dobbelt.
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
-- db.duels[ven] = { { id, char, opp, of (modstanderens ven eller nil), won, fled, zone, t }, ... }
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Name = C.Name   -- medlemmets valgte navn (nøglerne er medlems-ID'er)
local Print = C.Print
local Plain = C.GAME.Plain

local DUEL_KEEP = 300   -- så mange dueller gemmes pr. ven
local DUEL_ICON = "Interface\\Icons\\Ability_Warrior_Challange"

local function DB()
    local db = WastedCoastDB
    db.duels = db.duels or {}
    return db
end

local function Clean(s)
    return (tostring(s or ""):gsub(";", ","))
end

-- Duel-teksterne bruger nummererede felter ("%2$s has fled from %1$s in a duel"), så de
-- laves om til et mønster, og vi husker, hvilket felt der kom hvor. Felt 1 = vinderen, 2 = taberen.
local function PositionalPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local order, n = {}, 0
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%(%d)%%%$s", function(i)
        n = n + 1
        order[n] = tonumber(i)
        return "(.+)"
    end)
    p = p:gsub("%%s", function()
        n = n + 1
        order[n] = n
        return "(.+)"
    end)
    if n < 2 then return nil end
    return { pattern = "^" .. p .. "$", order = order }
end

local PATTERNS
local function BuildPatterns()
    PATTERNS = {}
    local function add(globalName, fled)
        local pp = PositionalPattern(_G[globalName])
        if pp then
            pp.fled = fled
            PATTERNS[#PATTERNS + 1] = pp
        end
    end
    add("DUEL_WINNER_KNOCKOUT", false)
    add("DUEL_WINNER_RETREAT", true)
end

-- Returnerer vinder, taber, flygtede
function ns.ParseDuel(msg)
    msg = Plain(msg)
    if type(msg) ~= "string" then return nil end
    if not PATTERNS then BuildPatterns() end
    for _, pp in ipairs(PATTERNS) do
        local caps = { msg:match(pp.pattern) }
        if #caps >= 2 then
            local arg = {}
            for k, i in ipairs(pp.order) do arg[i] = caps[k] end
            if arg[1] and arg[2] then return arg[1], arg[2], pp.fled end
        end
    end
    return nil
end

local function Short(name)
    name = tostring(name or "")
    return (Ambiguate and Ambiguate(name, "none")) or name:match("^[^%-]+") or name
end

local function AddDuel(friend, d)
    local db = DB()
    local list = db.duels[friend]
    if not list then list = {}; db.duels[friend] = list end
    for _, old in ipairs(list) do
        if old.id == d.id then return false end
    end
    list[#list + 1] = d
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #list > DUEL_KEEP do table.remove(list, 1) end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function SerializeDuel(friend, d)
    return table.concat({ "XD", friend, d.id, d.char, d.opp, d.won and 1 or 0, d.fled and 1 or 0, d.t, Clean(d.zone):sub(1, 30) }, ";")
end

-- Stillingen mellem to venner (set fra a's side): vundet, tabt
local function HeadToHead(a, b)
    local w, l = 0, 0
    for _, d in ipairs(DB().duels[a] or {}) do
        if (d.of or C.FriendOfChar(d.opp)) == b then
            if d.won then w = w + 1 else l = l + 1 end
        end
    end
    return w, l
end
ns.DuelHeadToHead = HeadToHead

-- Samlet for en ven: { w, l, fw, fl (mod venner), ow, ol (mod andre), streak, opp = { navn = { w, l } } }
local function DuelStats(friend)
    local st = { w = 0, l = 0, fw = 0, fl = 0, ow = 0, ol = 0, fled = 0, streak = 0, opp = {} }
    for _, d in ipairs(DB().duels[friend] or {}) do
        local of = d.of or C.FriendOfChar(d.opp)
        local key = of or d.opp
        local o = st.opp[key]
        if not o then o = { w = 0, l = 0, friend = of }; st.opp[key] = o end
        if d.won then
            st.w, o.w = st.w + 1, o.w + 1
            if of then st.fw = st.fw + 1 else st.ow = st.ow + 1 end
            st.streak = (st.streak > 0) and (st.streak + 1) or 1
        else
            st.l, o.l = st.l + 1, o.l + 1
            if of then st.fl = st.fl + 1 else st.ol = st.ol + 1 end
            if d.fled then st.fled = st.fled + 1 end
            st.streak = (st.streak < 0) and (st.streak - 1) or -1
        end
    end
    return st
end
ns.DuelStats = DuelStats

-- Systembeskeden om en afsluttet duel. Kun dueller, du selv var med i, tælles her.
local function OnSystemMessage(msg)
    local db = DB()
    if not db.me then return end
    local winner, loser, fled = ns.ParseDuel(msg)
    if not winner then return end
    winner, loser = Short(winner), Short(loser)
    local me = UnitName("player")
    if winner ~= me and loser ~= me then return end
    local won = (winner == me)
    local opp = won and loser or winner
    local of = C.FriendOfChar(opp)
    if of == db.me then of = nil end
    local d = { id = string.format("%s-%d-%s", me, time(), opp), char = me, opp = opp, of = of,
                won = won, fled = fled or nil, zone = GetZoneText and GetZoneText() or "", t = time() }
    if AddDuel(db.me, d) then
        C.Send(SerializeDuel(db.me, d), true)
        if db.settings.announce then
            local w, l = 0, 0
            if of then w, l = HeadToHead(db.me, of) end
            local score = of and string.format(" Stillingen mod %s: |cffffd100%d-%d|r.", Name(of), w, l) or ""
            if won then
                Print(string.format("Du vandt en duel mod %s%s.%s", opp, fled and " (vedkommende flygtede)" or "", score))
            else
                Print(string.format("Du tabte en duel til %s%s.%s", opp, fled and " (du flygtede)" or "", score))
            end
        end
    end
end

-- En vens duel: XD;ven;id;karakter;modstander;vandt;flygtede;tid;zone
function ns.HandleDuelMessage(t)
    local db = DB()
    local friend, id, at = t[2], t[3], tonumber(t[8])
    if not ROSTER_SET[friend] or friend == db.me or not id or id == "" or not at or not t[5] or t[5] == "" then return end
    local of = C.FriendOfChar(t[5])
    if of == friend then of = nil end
    local d = { id = id, char = t[4], opp = t[5], of = of, won = t[6] == "1", fled = (t[7] == "1") or nil,
                zone = t[9] or "", t = at }
    -- Kun friske dueller giver besked. Var du selv med, har du allerede fået den.
    if AddDuel(friend, d) and (time() - at) < 120 and of ~= db.me then
        local winner = d.won and friend or (of or d.opp)
        local loser = d.won and (of or d.opp) or friend
        if of then
            local w, l = HeadToHead(friend, of)
            ns.Toast({ kind = "duel", head = "DUEL", title = Name(winner) .. " slog " .. Name(loser) .. (d.fled and " (flygtede)" or ""),
                       text = string.format("Stillingen: %s %d - %d %s", Name(friend), w, l, Name(of)), icon = DUEL_ICON, friend = winner })
        elseif db.settings.announce then
            Print(string.format("%s %s en duel %s %s.", Name(friend), d.won and "vandt" or "tabte", d.won and "mod" or "til", d.opp))
        end
    end
end

-- Ved synk: send dine seneste dueller
function ns.SendDuels()
    local db = DB()
    if not db.me then return end
    local list = db.duels[db.me] or {}
    for i = #list, math.max(1, #list - 49), -1 do
        if not list[i].demo then C.Send(SerializeDuel(db.me, list[i])) end
    end
end

-- =============================================================================
-- UI: side 14 - dueller (under Rangliste)
-- =============================================================================
local Txt, MakeBox = C.Txt, C.MakeBox
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN
local ui = {}

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
    end
    return h
end

local RANK_COLS = {
    { x = 4,   w = 18,  j = "CENTER", label = "#" },
    { x = 24,  w = 96,  j = "LEFT",   label = "Ven" },
    { x = 122, w = 34,  j = "CENTER", label = "V" },
    { x = 158, w = 34,  j = "CENTER", label = "T" },
    { x = 194, w = 44,  j = "CENTER", label = "Sejr" },
    { x = 240, w = 48,  j = "CENTER", label = "Venner" },
    { x = 290, w = 48,  j = "CENTER", label = "Stime" },
}
local CELL = 32

local function BuildPage(page)
    -- Venstre: rangliste
    local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(362)
    Header(left, "Dueller", "vundet og tabt")
    for _, c in ipairs(RANK_COLS) do
        local fs = Txt(left, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", left, "TOPLEFT", 10 + c.x, -38)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.j)
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(c.label)
    end
    ui.rows = {}
    for i = 1, ns.MAX_MEMBERS do
        local row = MakeBox("Button", left, COL_BTN, COL_BORDER)
        row:SetSize(342, 24)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -(54 + (i - 1) * 27))
        row.f = {}
        for k, c in ipairs(RANK_COLS) do
            row.f[k] = C.Field(row, c.x, c.w, c.j, k == 2 and "GameFontNormal" or "GameFontHighlight")
        end
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Name(d.name), 1, 1, 1)
            local st = d.st
            if st.w + st.l == 0 then
                GameTooltip:AddLine("Ingen dueller endnu", 0.6, 0.6, 0.66)
            else
                GameTooltip:AddDoubleLine("Mod venner", string.format("%d-%d", st.fw, st.fl), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine("Mod andre", string.format("%d-%d", st.ow, st.ol), 0.8, 0.8, 0.8, 1, 1, 1)
                if st.fled > 0 then GameTooltip:AddDoubleLine("Flygtet", tostring(st.fled), 0.8, 0.8, 0.8, 1, 0.45, 0.45) end
                local opps = {}
                for name, o in pairs(st.opp) do opps[#opps + 1] = { name = name, w = o.w, l = o.l, friend = o.friend } end
                table.sort(opps, function(a, b)
                    if a.w + a.l ~= b.w + b.l then return a.w + a.l > b.w + b.l end
                    return a.name < b.name
                end)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Modstandere", 1, 0.82, 0.2)
                for k = 1, math.min(8, #opps) do
                    local o = opps[k]
                    local r, g, b = 0.8, 0.8, 0.8
                    if o.w > o.l then r, g, b = 0.4, 0.9, 0.5 elseif o.l > o.w then r, g, b = 1, 0.45, 0.45 end
                    GameTooltip:AddDoubleLine(Name(o.name) .. (o.friend and "" or "  |cff888888(ikke ven)|r"), string.format("%d-%d", o.w, o.l), 0.9, 0.9, 0.9, r, g, b)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.rows[i] = row
    end
    ui.note = Txt(left, "GameFontHighlightSmall")
    ui.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 10)
    ui.note:SetWidth(338)
    ui.note:SetTextColor(0.5, 0.5, 0.56)
    ui.note:SetText("Sejr = andel vundne. Venner = stilling mod vennerne. Stime: +3 = tre sejre i træk. Hold musen over en ven for at se alle modstandere.")

    -- Højre: head-to-head mellem vennerne og de seneste dueller
    local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(362)
    Header(right, "Indbyrdes", "rækken mod kolonnen")
    ui.colHead, ui.rowHead, ui.cells = {}, {}, {}
    local x0, y0 = 84, -40
    for j = 1, ns.MAX_MEMBERS do
        local fs = Txt(right, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", right, "TOPLEFT", x0 + (j - 1) * CELL, y0)
        fs:SetWidth(CELL)
        fs:SetJustifyH("CENTER")
        ui.colHead[j] = fs
    end
    for i = 1, ns.MAX_MEMBERS do
        local fs = Txt(right, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", right, "TOPLEFT", 12, y0 - 16 - (i - 1) * 22)
        fs:SetWidth(70)
        fs:SetWordWrap(false)
        ui.rowHead[i] = fs
        ui.cells[i] = {}
        for j = 1, ns.MAX_MEMBERS do
            local cell = MakeBox("Frame", right, COL_BTN, COL_BORDER)
            cell:SetSize(CELL - 2, 20)
            cell:SetPoint("TOPLEFT", right, "TOPLEFT", x0 + (j - 1) * CELL + 1, y0 - 12 - (i - 1) * 22)
            cell.text = Txt(cell, "GameFontHighlightSmall")
            cell.text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            cell.text:SetJustifyH("CENTER")
            ui.cells[i][j] = cell
        end
    end
    local lh = Txt(right, "GameFontNormal")
    lh:SetPoint("TOPLEFT", right, "TOPLEFT", 12, y0 - 16 - ns.MAX_MEMBERS * 22 - 4)
    lh:SetText("Seneste dueller")
    lh:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    ui.recent = Txt(right, "GameFontHighlightSmall")
    ui.recent:SetPoint("TOPLEFT", lh, "BOTTOMLEFT", 0, -6)
    ui.recent:SetWidth(338)
    ui.recent:SetWordWrap(false)
    ui.recent:SetSpacing(3)
end

local function RefreshPage()
    local db = DB()
    local classOf = {}
    for _, s in ipairs(C.BuildStats()) do classOf[s.name] = s.class end

    local list = {}
    for _, name in ipairs(ROSTER) do
        local st = DuelStats(name)
        list[#list + 1] = { name = name, st = st, n = st.w + st.l, rate = (st.w + st.l) > 0 and st.w / (st.w + st.l) or nil }
    end
    table.sort(list, function(a, b)
        if (a.n > 0) ~= (b.n > 0) then return a.n > 0 end
        if a.st.w ~= b.st.w then return a.st.w > b.st.w end
        if (a.rate or 0) ~= (b.rate or 0) then return (a.rate or 0) > (b.rate or 0) end
        return a.name < b.name
    end)
    ns.ShowFirst(ui.rows, #list)
    for i, d in ipairs(list) do
        local row = ui.rows[i]
        row.data = d
        local st = d.st
        local r, g, b = C.ClassColor(classOf[d.name])
        row.f[1]:SetText(d.n > 0 and tostring(i) or "-")
        row.f[2]:SetText(Name(d.name) .. (d.name == db.me and " (dig)" or ""))
        row.f[2]:SetTextColor(r, g, b)
        row.f[3]:SetText(d.n > 0 and ("|cff66e080" .. st.w .. "|r") or "-")
        row.f[4]:SetText(d.n > 0 and ("|cffff7070" .. st.l .. "|r") or "-")
        row.f[5]:SetText(d.rate and string.format("%d%%", math.floor(d.rate * 100 + 0.5)) or "-")
        row.f[6]:SetText((st.fw + st.fl) > 0 and string.format("%d-%d", st.fw, st.fl) or "-")
        if st.streak >= 2 then
            row.f[7]:SetText("|cff66e080+" .. st.streak .. "|r")
        elseif st.streak <= -2 then
            row.f[7]:SetText("|cffff7070" .. st.streak .. "|r")
        else
            row.f[7]:SetText("-")
        end
        if i == 1 and d.n > 0 then
            row:SetBackdropColor(0.20, 0.17, 0.06, 1)
        elseif d.name == db.me then
            row:SetBackdropColor(0.13, 0.17, 0.26, 1)
        else
            row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end

    local n = #ROSTER
    ns.ShowFirst(ui.colHead, n)
    ns.ShowFirst(ui.rowHead, n)
    for i, list in ipairs(ui.cells) do ns.ShowFirst(list, i <= n and n or 0) end
    for i, a in ipairs(ROSTER) do
        local r, g, b = C.ClassColor(classOf[a])
        ui.colHead[i]:SetText(Name(a):sub(1, 3))
        ui.rowHead[i]:SetText(Name(a))
        ui.rowHead[i]:SetTextColor(r, g, b)
        ui.colHead[i]:SetTextColor(r, g, b)
        for j, bName in ipairs(ROSTER) do
            local cell = ui.cells[i][j]
            if a == bName then
                cell.text:SetText("")
                cell:SetBackdropColor(0.05, 0.05, 0.07, 1)
            else
                local w, l = HeadToHead(a, bName)
                if w + l == 0 then
                    -- Har kun den anden registreret dem (fx ældre version)? Så vend stillingen
                    local w2, l2 = HeadToHead(bName, a)
                    w, l = l2, w2
                end
                if w + l == 0 then
                    cell.text:SetText("|cff555555-|r")
                    cell:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
                else
                    cell.text:SetText(w .. "-" .. l)
                    if w > l then
                        cell:SetBackdropColor(0.08, 0.22, 0.10, 1)
                    elseif l > w then
                        cell:SetBackdropColor(0.24, 0.08, 0.08, 1)
                    else
                        cell:SetBackdropColor(0.18, 0.18, 0.10, 1)
                    end
                end
            end
        end
    end

    -- Seneste dueller (en duel mellem to venner vises kun én gang)
    local all, shown = {}, {}
    for friend, dl in pairs(db.duels) do
        if ROSTER_SET[friend] then
            for _, d in ipairs(dl) do all[#all + 1] = { friend = friend, d = d } end
        end
    end
    table.sort(all, function(x, y) return (x.d.t or 0) > (y.d.t or 0) end)
    local lines = {}
    for _, e in ipairs(all) do
        if #lines >= 6 then break end
        local d = e.d
        local of = d.of or C.FriendOfChar(d.opp)
        local key = of and (math.floor((d.t or 0) / 30) .. ":" .. ((e.friend < of) and (e.friend .. of) or (of .. e.friend))) or nil
        if not key or not shown[key] then
            if key then shown[key] = true end
            local winner = d.won and e.friend or (of or d.opp)
            local loser = d.won and (of or d.opp) or e.friend
            lines[#lines + 1] = string.format("%s slog %s%s |cff888888- %s|r", C.ColorName(winner, classOf[winner]),
                C.ColorName(loser, classOf[loser]), d.fled and " |cffff7070(flygtede)|r" or "", C.FormatAgo(d.t))
        end
    end
    if #lines == 0 then lines[1] = "|cff888888Ingen dueller endnu. Udfordr en ven (højreklik > Duel).|r" end
    ui.recent:SetText(table.concat(lines, "\n"))
end

C.EXTRA_PAGES[14] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Demo, nulstilling og events
-- =============================================================================
function ns.MakeDuelDemo()
    local db = DB()
    local now = time()
    local strangers = { "Gankmaster", "Bobthebuilder", "Leeroyj", "Hordemand" }
    for k = 1, 30 do
        local a = ROSTER[math.random(#ROSTER)]
        local b = ROSTER[math.random(#ROSTER)]
        if a ~= db.me then
            local stranger = (a == b) or math.random() < 0.3
            local d = { id = "demo-D-" .. k, char = a, opp = stranger and strangers[math.random(#strangers)] or b,
                        of = (not stranger) and b or nil, won = math.random() < 0.5,
                        fled = math.random() < 0.1 or nil, zone = "Shattrath City", t = now - math.random(60, 600000), demo = true }
            AddDuel(a, d)
        end
    end
end

function ns.ClearDuelDemo()
    local db = DB()
    for friend, list in pairs(db.duels) do
        for i = #list, 1, -1 do
            if list[i].demo then table.remove(list, i) end
        end
        if #list == 0 then db.duels[friend] = nil end
    end
end

function ns.ResetDuels()
    wipe(DB().duels)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:SetScript("OnEvent", function(_, _, msg)
    if WastedCoastDB then OnSystemMessage(msg) end
end)
