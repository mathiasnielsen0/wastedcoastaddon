local _, ns = ...
local L = ns.L

-- =============================================================================
-- Sjældne mobs (v0.16): når en ven dræber et rare eller rare elite mob, får alle en toast.
-- Vi holder øje med dit target, focus, mouseover, gruppens targets og (i kamp) nameplates.
-- Et rare mob, du/din gruppe har tagget og er i kamp med, huskes. Når det er dødt (corpset
-- ses, eller combat loggen melder UNIT_DIED/PARTY_KILL, hvor den findes), sendes en besked.
-- Er flere venner med til drabet, vises toasten kun én gang (mobbets GUID er nøglen).
-- Alt læses gennem GAME.Plain, så "secret values" (Forever) bare tæller som "ved ikke".
--
-- Besked: RM;ven;karakter;klasse;mob;level;rare|rareelite;zone;tid;guid
-- =============================================================================

local C = ns.core
local ROSTER_SET, GAME, Name = C.ROSTER_SET, C.GAME, C.Name

local RARE_LABEL = { rare = "Rare", rareelite = "Rare Elite" }
local ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
local TRACK_TIME = 600     -- så længe huskes et rare mob, vi har været i kamp med
local MAX_AGE = 120        -- ældre beskeder giver ingen toast

local tracked = {}   -- guid -> { name, level, cls, t }
local shown = {}     -- guid -> true (toast vist / drab meldt)

local function DB() return WastedCoastDB end
local function P(v) return GAME.Plain(v) end
local function Yes(v) return P(v) == true end
local function Clean(s) return (tostring(s or ""):gsub("[;|]", "")) end

local function Zone()
    local z = P(GetZoneText and GetZoneText())
    return type(z) == "string" and z or ""
end

local function LevelText(level)
    level = tonumber(level)
    if not level or level <= 0 then return "??" end
    return tostring(level)
end

local function ShowRareToast(friend, char, class, mob, level, cls, zone)
    local db = DB()
    if not db or not db.settings or db.settings.rareToasts == false then return end
    local full = (C.CharFull and C.CharFull(friend, char)) or char or "?"
    local head = L("RARE MOB DRÆBT")
    if friend and char and Name(friend) ~= char then head = head .. "  -  " .. Name(friend) end
    ns.Toast({
        kind = "raremob", head = head, title = full, class = class, icon = ICON,
        text = string.format("%s |cff9a9aa6(level %s %s%s)|r", mob, LevelText(level), RARE_LABEL[cls] or "Rare",
                             (zone and zone ~= "") and (", " .. zone) or ""),
        sound = "bosskill", friend = friend, dur = 6.5,
    })
end

-- v0.19: log over drab (til dagens sladder). db.rareLog = { { friend, mob, lvl, cls, zone, t }, ... }
local RARE_LOG_MAX = 100
local function LogRare(db, friend, mob, level, cls, zone, at)
    db.rareLog = db.rareLog or {}
    table.insert(db.rareLog, { friend = friend, mob = mob, lvl = tonumber(level) or 0, cls = cls, zone = zone, t = at or time() })
    while #db.rareLog > RARE_LOG_MAX do table.remove(db.rareLog, 1) end
end

-- Vi (eller gruppen) dræbte et rare mob: vis toasten og fortæl de andre
local function Killed(guid, info)
    local db = DB()
    if not db or not db.me or shown[guid] then return end
    shown[guid] = true
    tracked[guid] = nil
    local char = P(UnitName("player")) or "?"
    local _, class = UnitClass("player")
    local now = time()
    local zone = Zone()
    ShowRareToast(db.me, char, class, info.name, info.level, info.cls, zone)
    db.rareKills = db.rareKills or {}
    db.rareKills[db.me] = (db.rareKills[db.me] or 0) + 1
    LogRare(db, db.me, info.name, info.level, info.cls, zone, now)
    C.Send(table.concat({
        "RM", db.me, Clean(char), class or "", Clean(info.name):sub(1, 40), tostring(info.level or 0),
        info.cls, Clean(zone):sub(1, 30), tostring(now), Clean(guid):sub(1, 60),
    }, ";"), true)
end

-- Kig på én unit: husk levende rare mobs, vi er i kamp med, og meld dem, når de er døde
local function ScanUnit(u)
    if not Yes(UnitExists(u)) then return end
    local guid = P(UnitGUID(u))
    if type(guid) ~= "string" or shown[guid] then return end
    if not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return end
    local cls = P(UnitClassification(u))
    if not RARE_LABEL[cls] then return end
    local denied = UnitIsTapDenied and Yes(UnitIsTapDenied(u))

    if Yes(UnitIsDead(u)) then
        local info = tracked[guid]
        if info and not denied then Killed(guid, info) end
        return
    end
    if denied then
        tracked[guid] = nil      -- en anden har tagget det
        return
    end
    local info = tracked[guid]
    if info or Yes(UnitAffectingCombat(u)) then
        local name = P(UnitName(u))
        if type(name) ~= "string" or name == "" then return end
        tracked[guid] = {
            name = name, level = tonumber(P(UnitLevel(u))) or (info and info.level) or 0,
            cls = cls, t = GetTime(),
        }
    end
end

local GROUP_UNITS = { "target", "focus", "mouseover", "pettarget" }
for i = 1, 4 do GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i .. "target" end

local function Scan()
    if not DB() or not DB().me then return end
    for _, u in ipairs(GROUP_UNITS) do ScanUnit(u) end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do ScanUnit("raid" .. i .. "target") end
    end
    if Yes(UnitAffectingCombat("player")) or next(tracked) then
        for i = 1, 40 do ScanUnit("nameplate" .. i) end
    end
    local now = GetTime()
    for g, info in pairs(tracked) do
        if now - info.t > TRACK_TIME then tracked[g] = nil end
    end
end
ns.ScanRares = Scan

-- Combat loggen (hvor den findes): et husket rare mob døde
function ns.OnRareDied(guid)
    guid = P(guid)
    local info = type(guid) == "string" and tracked[guid]
    if info then Killed(guid, info) end
end

-- En vens drab
function ns.OnRareMessage(t)
    local db = DB()
    local friend, char, class, mob, level, cls, zone, at, guid =
        t[2], t[3], t[4], t[5], tonumber(t[6]), t[7], t[8], tonumber(t[9]), t[10]
    if not db or not ROSTER_SET[friend] or friend == db.me then return end
    if not RARE_LABEL[cls] or not mob or mob == "" or not char or char == "" or not at then return end
    if math.abs(time() - at) > MAX_AGE then return end
    local key = (guid and guid ~= "") and guid or (friend .. "-" .. mob .. "-" .. at)
    if shown[key] then return end
    shown[key] = true
    tracked[key] = nil
    db.rareKills = db.rareKills or {}
    db.rareKills[friend] = (db.rareKills[friend] or 0) + 1
    LogRare(db, friend, mob, level, cls, zone, at)
    ShowRareToast(friend, char, class ~= "" and class or nil, mob, level, cls, zone)
end

-- Eksempel til /wc4ever testtoast
function ns.TestRareToast()
    local db = DB()
    local _, class = UnitClass("player")
    ShowRareToast(db and db.me, P(UnitName("player")), class, "Rak'shiri", 64, "rareelite", "Nagrand")
end

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED", "UNIT_HEALTH" }) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" then
        if unit ~= "target" and unit ~= "focus" and unit ~= "mouseover"
            and not (type(unit) == "string" and unit:find("^nameplate")) then return end
        ScanUnit(unit)
        return
    end
    Scan()
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.5, Scan) end
