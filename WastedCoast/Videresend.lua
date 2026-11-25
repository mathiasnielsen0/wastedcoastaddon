local addonName, ns = ...
local L = ns.L

-- =============================================================================
-- Videresendelse (v0.31.2): venner, der er online, giver data videre om venner, der er offline
--   Før sendte hver ven kun sine EGNE karakterer, dødsfald og loot. Var to venner aldrig online
--   samtidig, så de aldrig hinandens nye data: Søren så fx Nick som level 27 "6 d siden", mens
--   Mathias (der havde spillet sammen med Nick) så level 32 "48 min siden".
--   * Når du beder om synk (RequestSync), sender du også et "hvad har jeg"-resumé (QV): for hver
--     ven det nyeste dødsfald, den nyeste loot og det seneste "sidst set", du kender.
--   * De andre online venner svarer (efter et par sekunder) med det, de har, som er nyere:
--     CV for karakterer og de almindelige D og L for dødsfald og loot. Kun for venner, der ikke
--     selv er online (de svarer selv), aldrig for spørgeren selv og aldrig demo-/testdata.
--   * Dødsfald og loot sendes ældste først og højst RELAY.PER pr. ven og RELAY.BUDGET i alt pr.
--     runde; resten kommer ved næste synk (den lette synk hvert 10. minut sender også QV).
--   * Det samme dødsfald/loot/karakter-stempel, der lige er set på kanalen (fra vennen selv eller
--     en anden, der videresender), sendes ikke igen i RELAY.QUIET sekunder. Så sender to online
--     venner ikke det hele to gange.
--   * CV bruges kun, hvis "sidst set" er nyere end det, modtageren har. Den gamle C-besked
--     overskriver altid, så videresendte karakterer har en ny type (ældre versioner ignorerer
--     den). D og L betyder det samme som altid (dubletter filtreres via id), så de genbruges.
--
-- Beskeder:
--   QV;ven;navn=d.l.c,navn=d.l.c,...   d/l/c = nyeste dødsfald, loot og sidst set (base 36, 0 = intet)
--                                      Deles op i flere beskeder ved 255 tegn.
--   CV;videresender;ven;karakter;klasse;level;guld;zone;sidst set;xp;efternavn
-- v0.31.3: H har addonets version i felt 11. Den gemmes i db.friends[ven].ver og vises i
--   /wc4ever status sammen med, hvad der er givet videre (begge veje) siden login. Videresendelse
--   kræver nemlig, at både spørgeren og den, der svarer, har 0.31.2 eller nyere.
-- db.friends[ven].ver = vennens version (fra livstegnet). Ellers ingen nye db-felter.
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET

local RELAY = {
    PER = 25,        -- dødsfald + loot pr. ven pr. runde
    BUDGET = 120,    -- beskeder i alt pr. runde
    QUIET = 120,     -- sekunder, et element ikke sendes igen efter at være set på kanalen
    WAIT = 3,        -- sekunder (+ op til 8 tilfældige) før svaret sendes
    want = {},       -- ven -> { d, l, c } = det mindste, nogen af spørgerne har
    heard = {},      -- nøgle -> GetTime(), da den sidst blev set/sendt
    pending = false,
}
ns.Relay = RELAY
RELAY.stats = { qvIn = 0, sent = 0, cvIn = 0, cvUsed = 0 }

-- -----------------------------------------------------------------------------
-- Versioner (v0.31.3)
-- -----------------------------------------------------------------------------
do
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return get and get(addonName, "Version") end)
    ns.VERSION = (ok and type(v) == "string" and v:match("^%d+%.%d+%.%d+$")) and v or nil
end

function ns.NoteVersion(friend, v)
    local info = WastedCoastDB and WastedCoastDB.friends[friend]
    if info and type(v) == "string" and v:match("^%d+%.%d+%.%d+$") and #v <= 12 then info.ver = v end
end

-- Sammenlign "0.31.2" med "0.31.10" tal for tal
function RELAY.VersionAtLeast(v, want)
    if type(v) ~= "string" then return false end
    local a, b = { v:match("^(%d+)%.(%d+)%.(%d+)$") }, { want:match("^(%d+)%.(%d+)%.(%d+)$") }
    if not a[1] then return false end
    for i = 1, 3 do
        local x, y = tonumber(a[i]), tonumber(b[i])
        if x ~= y then return x > y end
    end
    return true
end

-- " (v0.31.3)" efter navnet i /wc4ever status. Ukendt = en version fra før 0.31.3 (eller ikke hørt)
function ns.VersionTag(friend)
    local info = WastedCoastDB.friends[friend]
    local v = info and info.ver
    if not v then return L(" |cff9aa0a6(version ukendt)|r") end
    local col = (ns.VERSION and not RELAY.VersionAtLeast(v, ns.VERSION)) and "|cffff6060" or "|cff9aa0a6"
    return " " .. col .. "(v" .. v .. ")|r"
end

function ns.PrintRelayStatus()
    local st = RELAY.stats
    print(string.format(L("  Videresendelse siden login: %d resuméer fra andre, %d beskeder sendt videre, %d karakterer modtaget (%d brugt, resten var ældre)."),
        st.qvIn, st.sent, st.cvIn, st.cvUsed))
    if ns.VERSION then
        print(string.format(L("  Din version: v%s. Rødt = ældre end din. Videresendelse kræver 0.31.2 hos begge."), ns.VERSION))
    end
end

-- -----------------------------------------------------------------------------
-- Base 36 (tider fylder 6 tegn i stedet for 10)
-- -----------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function RELAY.B36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end

local function FromB36(s)
    if type(s) ~= "string" or s == "" or #s > 8 or s:find("[^0-9a-z]") then return nil end
    return tonumber(s, 36)
end

-- -----------------------------------------------------------------------------
-- Hvad kender jeg? Nyeste dødsfald, loot og "sidst set" pr. ven (demo tæller ikke)
-- -----------------------------------------------------------------------------
local function Newest()
    local db = WastedCoastDB
    local out = {}
    local function get(f)
        local e = out[f]
        if not e then e = { 0, 0, 0 }; out[f] = e end
        return e
    end
    for _, ev in ipairs(db.events or {}) do
        local f = C.EventFriend(ev)
        if f and not ev.demo and not C.IsLocalOnly(ev.id or "") then
            local e = get(f)
            if (ev.time or 0) > e[1] then e[1] = ev.time end
        end
    end
    for _, ev in ipairs(db.loot or {}) do
        local f = C.LootFriend(ev)
        if f and not ev.demo and not C.IsLocalOnly(ev.id or "") then
            local e = get(f)
            if (ev.time or 0) > e[2] then e[2] = ev.time end
        end
    end
    for f, info in pairs(db.friends or {}) do
        for _, c in pairs(info.chars or {}) do
            if not c.demo and (c.seen or 0) > get(f)[3] then get(f)[3] = c.seen end
        end
    end
    return out
end
RELAY.Newest = Newest

-- Sendes lige efter Q (RequestSync). Alle venner undtagen mig selv, også dem, jeg intet ved om.
function ns.SendSyncDigest()
    local db = WastedCoastDB
    if not db or not db.me then return end
    local have = Newest()
    local head = "QV;" .. db.me .. ";"
    local parts = {}
    local function flush()
        if #parts > 0 then C.Send(head .. table.concat(parts, ",")) end
        parts = {}
    end
    local len = #head
    for _, f in ipairs(ROSTER) do
        if f ~= db.me and not f:find("[,=;]") then
            local e = have[f] or { 0, 0, 0 }
            local p = f .. "=" .. RELAY.B36(e[1]) .. "." .. RELAY.B36(e[2]) .. "." .. RELAY.B36(e[3])
            if len + #p + 1 > 255 then flush(); len = #head end
            parts[#parts + 1] = p
            len = len + #p + 1
        end
    end
    flush()
end

-- -----------------------------------------------------------------------------
-- Set på kanalen: sendes ikke igen lige med det samme
-- -----------------------------------------------------------------------------
function ns.RelayHeard(key)
    if key then RELAY.heard[key] = GetTime() end
end

local function Fresh(key)
    local at = RELAY.heard[key]
    return at and (GetTime() - at) < RELAY.QUIET
end

local function CharKey(friend, char, seen) return "c|" .. friend .. "|" .. char .. "|" .. tostring(seen) end

-- Er vennen online lige nu (så svarer vennen selv)?
local function FriendOnline(friend)
    local info = WastedCoastDB.friends[friend]
    for char, c in pairs((info and info.chars) or {}) do
        if ns.CharOnline and ns.CharOnline(char, c) then return true end
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Svar: send det, jeg har, som er nyere end det, spørgerne har
-- -----------------------------------------------------------------------------
function RELAY.Respond()
    RELAY.pending = false
    local db = WastedCoastDB
    local want = RELAY.want
    RELAY.want = {}
    if not db or not db.me then return end
    local budget = RELAY.BUDGET
    local function send(key, msg)
        if budget <= 0 or Fresh(key) then return false end
        budget = budget - 1
        RELAY.stats.sent = RELAY.stats.sent + 1
        RELAY.heard[key] = GetTime()
        C.Send(msg)
        return true
    end

    for _, friend in ipairs(ROSTER) do
        local w = want[friend]
        if w and friend ~= db.me and ROSTER_SET[friend] and not FriendOnline(friend) and budget > 0 then
            -- Karakterer: alle vennens karakterer, der er set senere end det, spørgeren kender
            local info = db.friends[friend]
            for char, c in pairs((info and info.chars) or {}) do
                if not c.demo and (c.seen or 0) > w[3] then
                    send(CharKey(friend, char, c.seen), table.concat({
                        "CV", db.me, friend, char, c.class or "", c.level or 0, c.gold or 0, C.Clean(c.zone),
                        c.seen, c.xp or 0, C.Clean(c.surname or ""),
                    }, ";"))
                end
            end
            -- Dødsfald og loot, der er nyere end spørgerens nyeste, ældste først
            local list = {}
            for _, ev in ipairs(db.events) do
                if (ev.time or 0) > w[1] and not ev.demo and not C.IsLocalOnly(ev.id or "")
                    and C.EventFriend(ev) == friend then
                    list[#list + 1] = { t = ev.time, key = ev.id, ser = C.SerializeDeath, ev = ev }
                end
            end
            for _, ev in ipairs(db.loot) do
                if (ev.time or 0) > w[2] and not ev.demo and not C.IsLocalOnly(ev.id or "")
                    and C.LootFriend(ev) == friend then
                    list[#list + 1] = { t = ev.time, key = ev.id, ser = C.SerializeLoot, ev = ev }
                end
            end
            table.sort(list, function(a, b) return a.t < b.t end)
            local n = 0
            for _, x in ipairs(list) do
                if n >= RELAY.PER or budget <= 0 then break end
                local ok, msg = pcall(x.ser, x.ev)
                if ok and type(msg) == "string" and send(x.key, msg) then n = n + 1 end
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Modtag
-- -----------------------------------------------------------------------------
local function OnDigest(t)
    local db = WastedCoastDB
    local from = t[2]
    if not db.me or not ROSTER_SET[from] or from == db.me or type(t[3]) ~= "string" then return end
    local any = false
    for f, d, l, c in t[3]:gmatch("([^,=]+)=([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)") do
        d, l, c = FromB36(d), FromB36(l), FromB36(c)
        if ROSTER_SET[f] and f ~= from and f ~= db.me and d and l and c then
            local w = RELAY.want[f]
            if not w then
                RELAY.want[f] = { d, l, c }
            else
                w[1], w[2], w[3] = math.min(w[1], d), math.min(w[2], l), math.min(w[3], c)
            end
            any = true
        end
    end
    if any then RELAY.stats.qvIn = RELAY.stats.qvIn + 1 end
    if any and not RELAY.pending then
        RELAY.pending = true
        C_Timer.After(RELAY.WAIT + math.random() * 8, RELAY.Respond)
    end
end

local function OnChar(t)
    local db = WastedCoastDB
    local friend, char = t[3], t[4]
    if not db.me or not ROSTER_SET[t[2]] or not ROSTER_SET[friend] or friend == db.me then return end
    if type(char) ~= "string" or char == "" or #char > 40 then return end
    local seen, level = tonumber(t[9]), tonumber(t[6])
    if not seen or seen <= 0 or not level then return end
    if seen > time() then seen = time() end   -- vennens ur kan gå forkert
    ns.RelayHeard(CharKey(friend, char, t[9]))
    RELAY.stats.cvIn = RELAY.stats.cvIn + 1
    local info = db.friends[friend]
    local c = info and info.chars and info.chars[char]
    if c and (c.seen or 0) >= seen then return end   -- vi har nyere (eller det samme)
    local zone = t[8] and t[8]:sub(1, 60)
    local sur = t[11] and t[11]:sub(1, 30)
    RELAY.stats.cvUsed = RELAY.stats.cvUsed + 1
    C.UpdateChar(friend, char, {
        class = t[5] and t[5]:sub(1, 20), level = level, gold = tonumber(t[7]), zone = zone,
        xp = tonumber(t[10]), surname = sur,
    }, seen)
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.HandleRelayMessage(kind, t)
    local db = WastedCoastDB
    if not db or type(t) ~= "table" then return end
    if kind == "QV" then OnDigest(t)
    elseif kind == "CV" then OnChar(t) end
end
