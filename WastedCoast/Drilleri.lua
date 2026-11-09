local _, ns = ...

-- =============================================================================
-- Drilleri (v0.6)
--   * Dødsannonce: en popup med en sjov annonce, når en ven dør
--   * Skammens hat: den, der døde sidst, bærer hatten, indtil en anden dør
--   * Need-politiet: gear, du har needet uden at bruge, bliver hængt ud
--   * Emote-angreb: send en tilfældig fornærmelse til en ven
--   * Held-rangering: hvem har haft de bedste rolls på det seneste
--   * Level-snegl: den, der er længst bagud i level, med tiden siden sidste level
-- Indlæses efter WastedCoast.lua og bruger dens hjælpefunktioner via ns.core.
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print = C.Print
local Name = C.Name   -- medlemmets valgte navn (nøglerne er medlems-ID'er)

-- WoW Forever har kun C_Item-udgaverne af item-funktionerne, og nogle værdier kan være "secret"
local Plain = C.GAME.Plain
local GetItemInfo = C.GAME.ItemInfo
local IsEquippableItem = IsEquippableItem or (C_Item and C_Item.IsEquippableItem)
local IsEquippedItem = IsEquippedItem or (C_Item and C_Item.IsEquippedItem)
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)

ns.HAT_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local OBIT_ICON = "Interface\\Icons\\Ability_Rogue_FeignDeath"
local EMOTE_ICON = "Interface\\Icons\\Ability_Warrior_BattleShout"

local LUCK_KEEP = 30        -- så mange af de seneste rolls gemmes pr. ven
local LUCK_MIN = 5          -- færre rolls end dette giver ingen held-rating
local ROLL_SD = 28.866      -- standardafvigelse for et roll 1-100
local NEED_DAYS = 3         -- needet gear, der ikke er taget på efter så mange dage, bliver hængt ud
local EMOTE_COOLDOWN = 15   -- sekunder mellem dine emote-angreb

local function DB()
    local db = WastedCoastDB
    db.needWatch = db.needWatch or {}     -- nøgle -> { id, item, name, quality, char, class, t }
    db.needShame = db.needShame or {}     -- liste af { id, friend, char, class, item, name, quality, why, time }
    db.emoteStats = db.emoteStats or { sent = {}, recv = {} }
    db.levelAt = db.levelAt or {}         -- ven -> { l = højeste level, t = hvornår det blev nået, g = gæt }
    return db
end

-- Beskeder bruger ";" som skilletegn
local function Clean(s)
    return (tostring(s or ""):gsub(";", ","))
end

local function Hash(s)
    local h = 0
    s = tostring(s or "")
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
    return h
end

local function ClassOf(friend)
    for _, s in ipairs(C.BuildStats()) do
        if s.name == friend then return s.class, s end
    end
end

local function ItemIcon(id)
    local ok, path = pcall(function()
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
        if GetItemIcon then return GetItemIcon(id) end
    end)
    return ok and path or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ItemLink(e)
    return string.format("|cff%s|H%s|h[%s]|h|r", C.QUALITY_HEX[e.quality] or "ffffff", e.item, e.name)
end

-- =============================================================================
-- Held-rangering: db.rolls[ven].last = { 54, 12, 99, ... } (nyeste sidst), lastT = tidspunkt
-- =============================================================================
-- Sandsynligheden for at få et lavere snit end z ved rent held (normalfordeling)
local function Phi(z)
    local t = 1 / (1 + 0.2316419 * math.abs(z))
    local d = 0.3989423 * math.exp(-z * z / 2)
    local p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
    return z > 0 and (1 - p) or p
end

-- Returnerer { n, mean, pct, best, worst } eller nil, hvis der er for få rolls
local function LuckStats(friend)
    local r = WastedCoastDB.rolls[friend]
    local list = r and r.last
    if type(list) ~= "table" or #list < LUCK_MIN then return nil end
    local sum, best, worst = 0, 0, 101
    for _, v in ipairs(list) do
        sum = sum + v
        if v > best then best = v end
        if v < worst then worst = v end
    end
    local n = #list
    local mean = sum / n
    local z = (mean - 50.5) / (ROLL_SD / math.sqrt(n))
    return { n = n, mean = mean, pct = Phi(z) * 100, best = best, worst = worst }
end
ns.LuckStats = LuckStats

-- Held i procent (0-100): hvor mange procent af tilfældige roll-serier dine seneste rolls slår
function ns.LuckPercent(friend)
    local st = LuckStats(friend)
    return st and math.floor(st.pct + 0.5) or nil
end

local function SendRecentRolls()
    local db = WastedCoastDB
    local r = db.me and db.rolls[db.me]
    if not r or type(r.last) ~= "table" or #r.last == 0 then return end
    C.Send(string.format("XK;%s;%d;%s", db.me, r.lastT or 0, table.concat(r.last, ",")))
end

local rollSendPending = false
function ns.AddRecentRoll(value)
    local db = WastedCoastDB
    if not db or not db.me or not value or value < 1 or value > 100 then return end
    local r = ns.RollEntry(db.me, true)
    r.last = type(r.last) == "table" and r.last or {}
    r.last[#r.last + 1] = math.floor(value)
    while #r.last > LUCK_KEEP do table.remove(r.last, 1) end
    r.lastT = time()
    if ns.RefreshUI then ns.RefreshUI() end
    if rollSendPending then return end
    rollSendPending = true
    C_Timer.After(15, function()
        rollSendPending = false
        SendRecentRolls()
    end)
end

-- /roll 1-100 tæller også med (kun dine egne; vennerne sender deres)
local ROLL_PATTERN
local function OnSystemMessage(msg)
    msg = Plain(msg)
    if type(msg) ~= "string" then return end
    if ROLL_PATTERN == nil then ROLL_PATTERN = C.FormatToPattern(RANDOM_ROLL_RESULT) or false end
    if not ROLL_PATTERN then return end
    local who, value, low, high = msg:match(ROLL_PATTERN)
    if who and who == UnitName("player") and tonumber(low) == 1 and tonumber(high) == 100 then
        ns.AddRecentRoll(tonumber(value))
    end
end

-- =============================================================================
-- Skammens hat: den ven, der døde sidst
-- =============================================================================
local function LatestDeath(exclude)
    local best
    for _, ev in ipairs(WastedCoastDB.events) do
        if ev ~= exclude and C.EventFriend(ev) and (not best or (ev.time or 0) > (best.time or 0)) then best = ev end
    end
    return best and C.EventFriend(best), best
end

function ns.HatHolder()
    return (LatestDeath())
end

-- Hvor længe hver ven har båret hatten i alt: { { name, secs }, ... } flest først
local function HatTimes()
    local list = {}
    for _, ev in ipairs(WastedCoastDB.events) do
        local f = C.EventFriend(ev)
        if f and ev.time then list[#list + 1] = { f = f, t = ev.time } end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    local total = {}
    for i, e in ipairs(list) do
        local stop = list[i + 1] and list[i + 1].t or time()
        total[e.f] = (total[e.f] or 0) + math.max(0, stop - e.t)
    end
    local res = {}
    for f, secs in pairs(total) do res[#res + 1] = { name = f, secs = secs } end
    table.sort(res, function(a, b)
        if a.secs ~= b.secs then return a.secs > b.secs end
        return a.name < b.name
    end)
    return res
end

local function Duration(secs)
    if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. " min" end
    if secs < 86400 then return math.floor(secs / 3600) .. " t" end
    return string.format("%d d %d t", math.floor(secs / 86400), math.floor((secs % 86400) / 3600))
end

-- =============================================================================
-- Level-snegl: db.levelAt[ven] = { l, t, g }. g = true betyder, at vi ikke så selve
-- level-up'et (fx første gang med v0.6), så tiden er "mindst".
-- =============================================================================
-- Der findes ingen snegl blandt spillets ikoner, så det bliver en skildpadde
ns.SNAIL_ICON = "|TInterface\\Icons\\Ability_Hunter_Pet_Turtle:14:14|t"

local function UpdateLevels(list)
    local db = DB()
    for _, s in ipairs(list) do
        local lvl = s.maxLevel or 0
        if lvl > 0 then
            local e = db.levelAt[s.name]
            if not e or lvl < e.l then
                -- Første gang (eller demo-data er fjernet): vi ved ikke, hvornår levelet blev nået
                db.levelAt[s.name] = { l = lvl, t = time(), g = true }
            elseif lvl > e.l then
                e.l, e.t, e.g = lvl, time(), nil
            end
        end
    end
end

local function SendMyLevel()
    local db = DB()
    local e = db.me and db.levelAt[db.me]
    if e then C.Send(string.format("XL;%s;%d;%d;%d", db.me, e.l, e.t, e.g and 1 or 0)) end
end

-- Kaldes, når du selv stiger i level
-- =============================================================================
-- Level-toast: når nogen stiger i level, får alle en popup med det samme (XU-besked),
-- med hvor lang tid det tog siden karakterens sidste level
-- =============================================================================
local levelToasted = {}   -- "ven-karakter" -> level, så livstegnet ikke giver en popup mere

function ns.LevelToasted(friend, char, level)
    return (levelToasted[tostring(friend) .. "-" .. tostring(char)] or 0) >= (level or 0)
end

local function LevelToastText(char, level, secs)
    local parts = { char }
    if secs and secs > 0 then parts[#parts + 1] = Duration(secs) .. " siden sidste level" end
    local text = table.concat(parts, "  -  ")
    if level == C.MAX_LEVEL then
        text = text .. "\nMAX LEVEL! Endelig. Nu kan det rigtige spil begynde."
    elseif level % 10 == 0 then
        text = text .. "\nLevel " .. level .. ". Et rundt tal, tillykke!"
    end
    return text
end

local function ShowLevelToast(friend, char, class, level, secs, isMe)
    levelToasted[friend .. "-" .. char] = level
    ns.Toast({ kind = "levelup", title = (isMe and "Du" or Name(friend)) .. " nåede level " .. level,
               text = LevelToastText(char, level, secs), class = class,
               sound = (not isMe) and "levelup" or nil, friend = friend })
end

local function OnMyLevelUp(level)
    local db = DB()
    if not db.me or not level then return end
    -- Tid siden karakterens sidste level (kun hvis vi så det)
    db.myLevelT = db.myLevelT or {}
    local char = UnitName("player")
    local prevT = db.myLevelT[char]
    db.myLevelT[char] = time()
    local secs = prevT and (time() - prevT) or 0
    local class = select(2, UnitClass("player"))
    C.Send(string.format("XU;%s;%s;%s;%d;%d", db.me, char, class or "", level, secs), true)
    ShowLevelToast(db.me, char, class, level, secs, true)

    local e = db.levelAt[db.me]
    if not e or level > e.l then
        db.levelAt[db.me] = { l = level, t = time() }
        SendMyLevel()
    end
end

-- Returnerer sneglen (laveste højeste-level af de venner, vi har set; ved lige level den, der har
-- ventet længst), eller nil hvis alle er lige langt
function ns.Snail(list)
    UpdateLevels(list)
    local db = DB()
    local best, top, n = nil, 0, 0
    for _, s in ipairs(list) do
        local lvl = s.maxLevel or 0
        if lvl > 0 then
            n = n + 1
            if lvl > top then top = lvl end
            local e = db.levelAt[s.name]
            if not best or lvl < best.lvl or (lvl == best.lvl and (e and e.t or 0) < best.t) then
                best = { name = s.name, lvl = lvl, t = e and e.t or time() }
            end
        end
    end
    local snail = (best and n >= 2 and best.lvl < top) and best.name or nil
    ns.snailHolder = snail
    return snail
end

-- "Level-snegl: level 34, 3 d 2 t siden sidste level" (eller nil, hvis vennen ikke er sneglen)
function ns.SnailText(friend)
    if ns.snailHolder ~= friend then return nil end
    local e = DB().levelAt[friend]
    if not e then return nil end
    return string.format("Level-snegl: level %d, %s%s siden sidste level", e.l, e.g and "mindst " or "", Duration(time() - e.t))
end

-- =============================================================================
-- Dødsannonce
-- =============================================================================
local OBITS = {
    fall = {
        "{N} testede tyngdekraften i {Z}. Tyngdekraften vandt.",
        "{N} troede, man kunne flyve i {Z}. Det kunne man ikke.",
        "{N} tog den hurtige vej ned. Bisættelsen holdes i bunden af kløften.",
        "Sidste ord fra {N}: \"Det er slet ikke så højt.\"",
    },
    drown = {
        "{N} glemte at trække vejret i {Z}.",
        "{N} ville se, hvor dybt vandet var. Meget dybt, viste det sig.",
        "{N} er nu fiskefoder i {Z}.",
    },
    fatigue = {
        "{N} svømmede ud i det store intet og kom aldrig hjem.",
        "{N} ville se, hvad der var på den anden side af havet. Svaret: udmattelse.",
    },
    lava = {
        "{N} ville lige mærke, om lavaen var varm. Det var den.",
        "{N} blev grillet i {Z}. Serveres medium rare.",
        "{N} tog et bad i noget, man ikke bør bade i.",
    },
    weak = {
        "{N} blev overlistet af en level {KL} {K}.",
        "{N} (level {L}) tabte til en level {KL} {K}. Familien beder om ro.",
        "En level {KL} {K} har nu {N} på sit CV.",
        "Breaking: Level {KL} {K} slår level {L} {N}. Eksperterne er målløse.",
    },
    strong = {
        "{N} gik hen til en level {KL} {K} for at sige hej. Det gik ikke godt.",
        "{K} sagde nej. {N} lyttede ikke.",
        "{N} var lidt for modig over for en level {KL} {K}.",
    },
    pvp = {
        "{N} blev ganket af {K} i {Z}. Det var PvP-dødsfald nummer {P}.",
        "{K} kom forbi {Z} og tog {N} med som trofæ.",
        "{N} mødte en rigtig spiller i {Z}: {K}. Det var ikke et venskabeligt møde.",
        "Breaking: {K} fra den anden faction har sendt {N} hjem i en kiste.",
        "{N} (level {L}) blev lagt ned af {K}{AB}. Hævnen planlægges allerede.",
    },
    unknown = {
        "{N} døde i {Z}. Ingen ved hvordan. Mistænkeligt.",
        "{N} faldt bare om i {Z}. Obduktionen er i gang.",
    },
    generic = {
        "{N} døde til {K}{AB} i {Z}. Det var dødsfald nummer {D}.",
        "{K} har sendt {N} til nærmeste spirit healer.",
        "Vi mindes {N}, der blev taget af {K} i {Z}. Ingen blomster, tak.",
        "{N} er død. Igen. {K} tager æren.",
        "{N} nåede level {L}, og så kom {K}.",
        "{N} havde en plan. {K} havde en bedre.",
    },
}

local function ObitKind(ev)
    local env = C.ENV_NAMES
    local what = (ev.killer == "Omgivelserne") and ev.ability or ev.killer
    if what == env.Falling then return "fall" end
    if what == env.Drowning then return "drown" end
    if what == env.Fatigue then return "fatigue" end
    if what == env.Lava or what == env.Fire or what == env.Slime then return "lava" end
    if ev.killer == "Omgivelserne" or not ev.killer or ev.killer == "" or ev.killer == "Ukendt" then return "unknown" end
    if ev.pvp == true then return "pvp" end
    local kl, l = tonumber(ev.klvl), tonumber(ev.level) or 0
    if kl and kl > 0 and kl <= l - 3 then return "weak" end
    if kl and (kl == -1 or kl >= l + 3) then return "strong" end
    return "generic"
end

local function DeathCount(friend, pvpOnly)
    local n = 0
    for _, ev in ipairs(WastedCoastDB.events) do
        if C.EventFriend(ev) == friend and (not pvpOnly or ev.pvp == true) then n = n + 1 end
    end
    return n
end

-- Samme dødsfald giver samme annonce hos alle venner
function ns.Obituary(ev, friend)
    local kind = ObitKind(ev)
    local list = OBITS[kind]
    local text = list[(Hash(ev.id) % #list) + 1]
    local kl = tonumber(ev.klvl)
    local vars = {
        N = (friend and Name(friend)) or ev.name or "?",
        K = ev.killer or "?",
        AB = (ev.ability and ev.ability ~= "" and ev.ability ~= "Nærkamp") and (" (" .. ev.ability .. ")") or "",
        Z = (ev.zone and ev.zone ~= "") and ev.zone or "et ukendt sted",
        L = tostring(ev.level or "?"),
        KL = (kl == -1) and "??" or tostring(kl or "?"),
        D = tostring(friend and DeathCount(friend) or 1),
        P = tostring(friend and DeathCount(friend, true) or 1),
    }
    return (text:gsub("{(%u+)}", vars))
end

function ns.OnFreshDeath(ev, friend)
    local db = WastedCoastDB
    if not friend then return end
    if db.settings.obits ~= false then
        local title = Name(friend)
        local full = ev.name and (C.CharFull and C.CharFull(friend, ev.name, ev.sur) or ev.name)
        if full and full ~= title then
            title = title .. " (" .. full .. ", level " .. tostring(ev.level or "?") .. ")"
        else
            title = title .. " (level " .. tostring(ev.level or "?") .. ")"
        end
        ns.Toast({ kind = "obit", head = "DØDSANNONCE", title = title, text = ns.Obituary(ev, friend),
                   icon = OBIT_ICON, class = ev.class, dur = 7, friend = friend })
    end
    if db.settings.announce then
        local prev = LatestDeath(ev)
        if prev == friend then
            Print(Name(friend) .. " beholder |cffffd100Skammens hat|r. Den sidder godt fast nu.")
        elseif prev then
            Print("|cffffd100Skammens hat|r går videre fra " .. Name(prev) .. " til " .. Name(friend) .. ".")
        else
            Print(Name(friend) .. " får |cffffd100Skammens hat|r som den første.")
        end
    end
end

-- Hvem slog dig ihjel? Find mobbets level, hvis det stadig kan ses (target, nameplates, gruppens targets)
function ns.KillerLevel(name)
    if not name or name == "" or not UnitExists then return nil end
    local units = { "target", "focus", "mouseover", "targettarget", "pettarget" }
    for i = 1, 4 do units[#units + 1] = "party" .. i .. "target" end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, u in ipairs(units) do
        if Plain(UnitExists(u)) and Plain(UnitName(u)) == name then
            local l = Plain(UnitLevel(u))
            if l and l ~= 0 then return l end
        end
    end
    return nil
end

-- =============================================================================
-- Need-politiet
-- =============================================================================
local SHAME_TEXT = {
    gone = "...og kom af med det uden nogensinde at tage det på. Solgt? Disenchanted? Skam dig.",
    unused = "...og det har ligget ubrugt i tasken i " .. NEED_DAYS .. " dage.",
}
local SHAME_SHORT = { gone = "solgt/væk uden at blive brugt", unused = "aldrig taget på" }

local function AddShame(e, fromNet)
    local db = DB()
    for _, old in ipairs(db.needShame) do
        if old.id == e.id then return false end
    end
    table.insert(db.needShame, e)
    while #db.needShame > 200 do table.remove(db.needShame, 1) end
    if not e.demo and (time() - (e.time or 0)) < 300 then
        ns.Toast({ kind = "police", head = "NEED-POLITIET", title = Name(e.friend) .. " needede " .. ItemLink(e),
                   text = SHAME_TEXT[e.why] or "", icon = ItemIcon(tonumber(e.item:match("^item:(%d+)"))),
                   dur = 7, friend = e.friend })
        if db.settings.announce then
            Print(string.format("|cff4080ffNeed-politiet:|r %s needede %s %s", Name(e.friend), ItemLink(e), SHAME_TEXT[e.why] or ""))
        end
    end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function SerializeShame(e)
    return table.concat({ "XN", e.id, e.friend, e.char, e.class or "", e.item, e.quality, e.why, e.time, Clean(e.name) }, ";")
end

-- Kaldes, når du vinder et item på need
function ns.WatchNeed(it)
    local db = DB()
    if not db.me or not it or not it.id or (it.quality or 0) < 2 then return end
    if IsEquippableItem and GetItemInfo(it.id) and not IsEquippableItem(it.id) then return end
    local char = UnitName("player")
    local key = string.format("%s-%d-%d", char, time(), it.id)
    db.needWatch[key] = { id = it.id, item = it.itemString, name = Clean(it.name):sub(1, 40), quality = it.quality,
                          char = char, class = select(2, UnitClass("player")), t = time() }
end

local function Shame(key, w, why)
    local db = DB()
    db.needWatch[key] = nil
    local e = { id = "N-" .. key, friend = db.me, char = w.char, class = w.class, item = w.item,
                name = w.name, quality = w.quality, why = why, time = time() }
    if AddShame(e) then C.Send(SerializeShame(e), true) end
end

-- Tjekker dine needede items: taget på = frikendt, væk eller ubrugt for længe = hængt ud
function ns.CheckNeeds()
    local db = DB()
    if not db.me then return end
    local me, now = UnitName("player"), time()
    for key, w in pairs(db.needWatch) do
        if w.char == me then
            if IsEquippableItem and GetItemInfo(w.id) and not IsEquippableItem(w.id) then
                db.needWatch[key] = nil
            elseif IsEquippedItem and IsEquippedItem(w.id) then
                db.needWatch[key] = nil
            elseif now - w.t > 60 and GetItemCount and GetItemCount(w.id, true) == 0 then
                Shame(key, w, "gone")
            elseif now - w.t > NEED_DAYS * 86400 then
                Shame(key, w, "unused")
            end
        elseif now - w.t > 30 * 86400 then
            db.needWatch[key] = nil
        end
    end
end

local needCheckPending = false
local function ScheduleNeedCheck()
    if needCheckPending then return end
    needCheckPending = true
    C_Timer.After(5, function()
        needCheckPending = false
        ns.CheckNeeds()
    end)
end

-- =============================================================================
-- Emote-angreb
-- =============================================================================
-- { tekst ({F} = angriberen, {T} = offeret), emote, der laves i spillet, hvis offeret er i nærheden }
local ATTACKS = {
    { "{F} kaster en død fisk i hovedet på {T}.", "SLAP" },
    { "{F} peger på {T} og griner højlydt.", "POINT" },
    { "{F} kalder {T} en kylling.", "CHICKEN" },
    { "{F} prutter i retning af {T}.", "FART" },
    { "{F} spytter efter {T}.", "SPIT" },
    { "{F} bonker {T} i hovedet.", "BONK" },
    { "{F} vifter {T} væk som en irriterende flue.", "SHOO" },
    { "{F} rækker tunge ad {T}.", "RASP" },
    { "{F} bøvser {T} lige op i ansigtet.", "BURP" },
    { "{F} viser {T} sin bare bagdel.", "MOON" },
    { "{F} sender {T} en meget uhøflig gestus.", "RUDE" },
    { "{F} har ondt af {T}. Mest på grund af gearet.", "PITY" },
    { "{F} spørger {T}, om det er første gang med tastatur og mus.", "LAUGH" },
    { "{F} tilbyder {T} et kursus i ikke at stå i ilden.", "TAUNT" },
    { "{F} siger, at {T} spiller som en level 1 gnome.", "ROFL" },
}

local function AttackText(idx, from, to)
    local a = ATTACKS[idx]
    -- Navnene kan indeholde %, som gsub ellers læser som et mønster
    from, to = Name(from):gsub("%%", "%%%%"), Name(to):gsub("%%", "%%%%")
    return a and (a[1]:gsub("{F}", from):gsub("{T}", to)) or nil
end

-- Finder en gruppe-unit eller dit target, der er en af vennens karakterer
local function FriendUnit(friend)
    if UnitExists("target") and C.FriendOfChar(UnitName("target")) == friend then return "target" end
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) and C.FriendOfChar(UnitName(u)) == friend then return u end
    end
    return nil
end

local seenAttacks = {}
local function OnAttack(from, to, idx, nonce)
    local db = DB()
    local key = from .. "-" .. tostring(nonce)
    if seenAttacks[key] then return end
    seenAttacks[key] = true
    db.emoteStats.sent[from] = (db.emoteStats.sent[from] or 0) + 1
    db.emoteStats.recv[to] = (db.emoteStats.recv[to] or 0) + 1
    if to == db.me and from ~= db.me then
        if db.settings.emotes ~= false then
            ns.Toast({ kind = "emote", head = "EMOTE-ANGREB", title = Name(from) .. " angriber dig!",
                       text = AttackText(idx, from, "dig"), icon = EMOTE_ICON, class = (ClassOf(from)), friend = from })
        end
        Print("|cffff70c0" .. AttackText(idx, from, "dig") .. "|r")
    elseif db.settings.announce then
        Print("|cffff70c0" .. AttackText(idx, from, to) .. "|r")
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

local lastAttack = -100
function ns.EmoteAttack(target)
    local db = DB()
    if not db.me then
        Print("Opret eller deltag først i en gruppe (|cffffd100/wc4ever gruppe|r).")
        return
    end
    if not ROSTER_SET[target] or target == db.me then return end
    if GetTime() - lastAttack < EMOTE_COOLDOWN then
        Print(string.format("Rolig nu. Du kan angribe igen om %d sek.", math.ceil(EMOTE_COOLDOWN - (GetTime() - lastAttack))))
        return
    end
    lastAttack = GetTime()
    local idx = math.random(#ATTACKS)
    local nonce = math.random(100000, 999999)
    local msg = string.format("XE;%s;%s;%d;%d", db.me, target, idx, nonce)
    C.Send(msg, true)
    local unit = FriendUnit(target)
    if unit and DoEmote then pcall(DoEmote, ATTACKS[idx][2], unit) end
    OnAttack(db.me, target, idx, nonce)
end

-- =============================================================================
-- Beskeder og synk
-- =============================================================================
function ns.HandlePrankMessage(kind, t)
    local db = DB()
    if kind == "XE" then
        local from, to, idx = t[2], t[3], tonumber(t[4])
        if ROSTER_SET[from] and ROSTER_SET[to] and from ~= db.me and idx and ATTACKS[idx] then
            OnAttack(from, to, idx, t[5])
        end

    elseif kind == "XN" then
        local friend, q, at = t[3], tonumber(t[7]), tonumber(t[9])
        if t[2] and ROSTER_SET[friend] and friend ~= db.me and (t[6] or ""):match("^item:%d+") and q
            and SHAME_TEXT[t[8]] and at then
            AddShame({ id = t[2], friend = friend, char = t[4], class = t[5], item = t[6], quality = q,
                       why = t[8], time = at, name = (t[10] or "?"):sub(1, 40) })
        end

    elseif kind == "XD" then
        if ns.HandleDuelMessage then ns.HandleDuelMessage(t) end

    elseif kind == "XU" then
        local friend, char, level = t[2], t[3], tonumber(t[5])
        if ROSTER_SET[friend] and friend ~= db.me and char and char ~= "" and level
            and not ns.LevelToasted(friend, char, level) then
            ShowLevelToast(friend, char, t[4] ~= "" and t[4] or nil, level, tonumber(t[6]))
        end

    elseif kind == "XL" then
        local friend, l, at = t[2], tonumber(t[3]), tonumber(t[4])
        if ROSTER_SET[friend] and friend ~= db.me and l and at and l > 0 then
            local e = db.levelAt[friend]
            local guess = t[5] == "1"
            -- Vennens egen tid vinder over vores gæt; to gæt: det tidligste vinder
            if not e or e.d or l > e.l or (l == e.l and (not guess or (e.g and at < e.t))) then
                db.levelAt[friend] = { l = l, t = at, g = guess or nil }
                if ns.RefreshUI then ns.RefreshUI() end
            end
        end

    elseif kind == "XK" then
        local friend, at = t[2], tonumber(t[3]) or 0
        if ROSTER_SET[friend] and friend ~= db.me and t[4] then
            local r = ns.RollEntry(friend, true)
            if at >= (r.lastT or 0) then
                local list = {}
                for v in t[4]:gmatch("%d+") do
                    local n = tonumber(v)
                    if n >= 1 and n <= 100 then list[#list + 1] = n end
                end
                while #list > LUCK_KEEP do table.remove(list, 1) end
                r.last, r.lastT = list, at
                if ns.RefreshUI then ns.RefreshUI() end
            end
        end
    end
end

-- Ved synk: send dine seneste rolls og dine egne need-synder
function ns.SendPrankExtras(light)
    local db = DB()
    SendRecentRolls()
    SendMyLevel()
    -- Den lette synk (hvert 10. minut) springer historikken over: den sendes, når den sker
    if light then return end
    if ns.SendDuels then ns.SendDuels() end
    local sent = 0
    for i = #db.needShame, 1, -1 do
        local e = db.needShame[i]
        if e.friend == db.me and not e.demo then
            C.Send(SerializeShame(e))
            sent = sent + 1
            if sent >= 20 then break end
        end
    end
end

-- =============================================================================
-- UI: side 13 - drilleri
-- =============================================================================
local Txt, MakeBox, MakeButton = C.Txt, C.MakeBox, C.MakeButton
local COL_PANEL, COL_BORDER, COL_GOLD, COL_BTN = C.COL_PANEL, C.COL_BORDER, C.COL_GOLD, C.COL_BTN
local ui = {}

local function Header(box, text)
    local h = Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(text)
    h:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    return h
end

local function SubText(box, anchor, text)
    local s = Txt(box, "GameFontHighlightSmall")
    s:SetPoint("LEFT", anchor, "RIGHT", 8, -1)
    s:SetTextColor(0.5, 0.5, 0.56)
    s:SetText(text)
    return s
end

local function BuildPage(page)
    -- Venstre øverst: held-rangering
    local luck = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    luck:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    luck:SetSize(362, 44 + ns.MAX_MEMBERS * 26)
    SubText(luck, Header(luck, "Held-rangering"), "seneste " .. LUCK_KEEP .. " rolls")
    ui.luckRows = {}
    for i = 1, ns.MAX_MEMBERS do
        local row = MakeBox("Button", luck, COL_BTN, COL_BORDER)
        row:SetSize(342, 22)
        row:SetPoint("TOPLEFT", luck, "TOPLEFT", 10, -(40 + (i - 1) * 26))
        row.rank = C.Field(row, 4, 20, "CENTER", "GameFontHighlightSmall")
        row.name = C.Field(row, 26, 96, "LEFT", "GameFontNormal")
        row.barBG = row:CreateTexture(nil, "ARTWORK")
        C.BarFill(row.barBG, 0.22, 0.22, 0.27, 1)
        row.barBG:SetSize(130, 8)
        row.barBG:SetPoint("LEFT", row, "LEFT", 126, 0)
        row.bar = row:CreateTexture(nil, "OVERLAY")
        row.bar:SetHeight(8)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.pct = C.Field(row, 262, 40, "RIGHT", "GameFontHighlight")
        row.n = C.Field(row, 304, 34, "RIGHT", "GameFontHighlightSmall")
        row.n:SetTextColor(0.5, 0.5, 0.56)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Name(d.name), 1, 1, 1)
            local st = d.st
            if not st then
                GameTooltip:AddLine(string.format("Mindst %d rolls før der er en rating (har %d)", LUCK_MIN, d.n), 0.6, 0.6, 0.66)
            else
                GameTooltip:AddDoubleLine("Held", string.format("%d%%", math.floor(st.pct + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine("Snit", string.format("%.1f (forventet 50,5)", st.mean), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine("Bedste / værste", string.format("%d / %d", st.best, st.worst), 0.8, 0.8, 0.8, 1, 1, 1)
                local last = WastedCoastDB.rolls[d.name].last
                local parts = {}
                for k = #last, math.max(1, #last - 11), -1 do parts[#parts + 1] = tostring(last[k]) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Seneste: " .. table.concat(parts, ", "), 0.7, 0.7, 0.76, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Held 80% = de seneste rolls er bedre end 80% af, hvad rent held ville give. 50% er helt normalt.", 0.5, 0.8, 1, true)
            GameTooltip:AddLine("Need/greed-rolls og /roll 1-100 tæller med.", 0.5, 0.5, 0.56, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ui.luckRows[i] = row
    end

    -- Venstre nederst: Skammens hat
    local hat = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    hat:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    hat:SetSize(362, 144)
    local hh = Header(hat, "Skammens hat")
    hh:SetPoint("TOPLEFT", hat, "TOPLEFT", 38, -10)
    local icon = hat:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", hat, "TOPLEFT", 12, -8)
    icon:SetTexture(ns.HAT_ICON)
    ui.hatText = Txt(hat, "GameFontHighlightSmall")
    ui.hatText:SetPoint("TOPLEFT", hat, "TOPLEFT", 12, -36)
    ui.hatText:SetWidth(338)
    ui.hatText:SetSpacing(3)

    -- Højre øverst: emote-angreb
    local emo = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    emo:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    emo:SetSize(362, 62 + math.ceil(ns.MAX_MEMBERS / 2) * 28)
    SubText(emo, Header(emo, "Emote-angreb"), "en tilfældig fornærmelse")
    ui.emoteBtns = {}
    for i = 1, ns.MAX_MEMBERS do
        local b = MakeButton(emo, 166, 24, "", function(self) if self.friend then ns.EmoteAttack(self.friend) end end)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", emo, "TOPLEFT", 10 + col * 176, -40 - row * 28)
        ui.emoteBtns[i] = b
    end
    ui.emoteStats = Txt(emo, "GameFontHighlightSmall")
    ui.emoteStats:SetPoint("BOTTOMLEFT", emo, "BOTTOMLEFT", 12, 8)
    ui.emoteStats:SetWidth(338)
    ui.emoteStats:SetWordWrap(false)
    ui.emoteStats:SetTextColor(0.6, 0.6, 0.66)

    -- Højre nederst: Need-politiet
    local need = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    need:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    need:SetPoint("TOPRIGHT", emo, "BOTTOMRIGHT", 0, -8)
    need:SetWidth(362)
    SubText(need, Header(need, "Need-politiet"), "needet, men aldrig brugt")
    ui.needText = Txt(need, "GameFontHighlightSmall")
    ui.needText:SetPoint("TOPLEFT", need, "TOPLEFT", 12, -36)
    ui.needText:SetWidth(338)
    ui.needText:SetWordWrap(false)
    ui.needText:SetSpacing(4)
    ui.needNote = Txt(need, "GameFontHighlightSmall")
    ui.needNote:SetPoint("BOTTOMLEFT", need, "BOTTOMLEFT", 12, 8)
    ui.needNote:SetWidth(338)
    ui.needNote:SetTextColor(0.5, 0.5, 0.56)
end

local function RefreshPage()
    local db = DB()
    local classOf = {}
    for _, s in ipairs(C.BuildStats()) do classOf[s.name] = s.class end

    -- Held
    local list = {}
    for _, name in ipairs(ROSTER) do
        local r = db.rolls[name]
        list[#list + 1] = { name = name, st = LuckStats(name), n = (r and type(r.last) == "table") and #r.last or 0 }
    end
    table.sort(list, function(a, b)
        if (a.st ~= nil) ~= (b.st ~= nil) then return a.st ~= nil end
        if a.st and a.st.pct ~= b.st.pct then return a.st.pct > b.st.pct end
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    local rated = 0
    for _, d in ipairs(list) do if d.st then rated = rated + 1 end end
    ns.ShowFirst(ui.luckRows, #list)
    for i, d in ipairs(list) do
        local row = ui.luckRows[i]
        row.data = d
        local rr, gg, bb = C.ClassColor(classOf[d.name])
        row.rank:SetText(d.st and tostring(i) or "-")
        row.name:SetText(Name(d.name) .. (d.name == db.me and " (dig)" or ""))
        row.name:SetTextColor(rr, gg, bb)
        row.n:SetText(d.n > 0 and (d.n .. " r") or "")
        if d.st then
            local p = d.st.pct / 100
            row.bar:SetWidth(math.max(1, 130 * p))
            C.BarFill(row.bar, 1 - p * 0.75, 0.3 + p * 0.6, 0.3, 1)
            row.bar:Show()
            row.pct:SetText(string.format("%d%%", math.floor(d.st.pct + 0.5)))
        else
            row.bar:Hide()
            row.pct:SetText("|cff666666-|r")
        end
        if i == 1 and d.st and rated >= 2 then
            row:SetBackdropColor(0.08, 0.20, 0.10, 1)
            row.name:SetText(Name(d.name) .. "  |cffffd100Fætter Højben|r")
        elseif d.st and i == rated and rated >= 2 then
            row:SetBackdropColor(0.20, 0.08, 0.08, 1)
        elseif d.name == db.me then
            row:SetBackdropColor(0.13, 0.17, 0.26, 1)
        else
            row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end

    -- Skammens hat
    local holder, ev = LatestDeath()
    local lines = {}
    if not holder then
        lines[1] = "Ingen har båret hatten endnu. Den første, der dør, får den."
    else
        lines[1] = string.format("%s har båret hatten i |cffffd100%s|r.", C.ColorName(holder, classOf[holder]),
            Duration(time() - (ev.time or time())))
        local what = ev.killer or "?"
        if ev.ability and ev.ability ~= "" then what = what .. " (" .. ev.ability .. ")" end
        lines[2] = "|cff888888Død til " .. what .. " i " .. (ev.zone or "?") .. ".|r"
        lines[3] = "|cffbbbbbb\"" .. ns.Obituary(ev, holder) .. "\"|r"
        local times = HatTimes()
        local parts = {}
        for i = 1, math.min(3, #times) do parts[i] = Name(times[i].name) .. " " .. Duration(times[i].secs) end
        lines[4] = " "
        lines[5] = "|cffffd100Mest tid med hatten:|r " .. table.concat(parts, ", ")
    end
    ui.hatText:SetText(table.concat(lines, "\n"))

    -- Emote-knapper og statistik
    local now = GetTime()
    ns.ShowFirst(ui.emoteBtns, #ROSTER)
    for i, b in ipairs(ui.emoteBtns) do
        b.friend = ROSTER[i] or false
    end
    for _, b in ipairs(ui.emoteBtns) do
        local rr, gg, bb = C.ClassColor(classOf[b.friend])
        if not b.friend then
            -- tom plads
        elseif b.friend == db.me then
            b.text:SetText("|cff666666" .. Name(b.friend) .. " (dig)|r")
            b:Disable()
        else
            b:Enable()
            b.text:SetText(string.format("|cff%02x%02x%02x%s|r", math.floor(rr * 255), math.floor(gg * 255), math.floor(bb * 255), Name(b.friend)))
        end
        b:SetAlpha((now - lastAttack < EMOTE_COOLDOWN and b.friend ~= db.me) and 0.6 or 1)
    end
    local function top(map)
        local best, n = nil, 0
        for f, c in pairs(map) do
            if c > n or (c == n and best and f < best) then best, n = f, c end
        end
        return best, n
    end
    local bully, bn = top(db.emoteStats.sent)
    local victim, vn = top(db.emoteStats.recv)
    if bully then
        ui.emoteStats:SetText(string.format("Største bølle: %s (%d)   Mest mobbet: %s (%d)", Name(bully), bn, Name(victim), vn))
    else
        ui.emoteStats:SetText("Ingen angreb endnu. Vær den første.")
    end

    -- Need-politiet
    local shames = {}
    for _, e in ipairs(db.needShame) do shames[#shames + 1] = e end
    table.sort(shames, function(a, b) return (a.time or 0) > (b.time or 0) end)
    local nl = {}
    for i = 1, math.min(8, #shames) do
        local e = shames[i]
        nl[#nl + 1] = string.format("%s %s |cff888888- %s, %s|r", C.ColorName(e.friend, e.class), ItemLink(e),
            SHAME_SHORT[e.why] or "?", C.FormatAgo(e.time))
    end
    if #nl == 0 then nl[1] = "|cff888888Ingen need-synder endnu. Politiet holder øje.|r" end
    ui.needText:SetText(table.concat(nl, "\n"))
    local watching = 0
    for _ in pairs(db.needWatch) do watching = watching + 1 end
    ui.needNote:SetText(string.format("Need-gear, der ikke er taget på efter %d dage, eller som bliver solgt, kommer på listen. Du har %s under opsyn.",
        NEED_DAYS, C.Plural(watching, "item", "items")))
end

C.EXTRA_PAGES[13] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Demo, test, nulstilling og slash-kommandoer
-- =============================================================================
local DEMO_NEED = {
    { 28830, "Dragonspine Trophy", 4 }, { 27450, "Wrap of Unity", 3 }, { 28572, "Blade of the Unrequited", 4 },
    { 29434, "Initiate's Belt of the Sorcerer", 3 }, { 27497, "Doomplate Gauntlets", 3 },
}

function ns.MakePrankDemo()
    local db = DB()
    local now = time()
    for _, name in ipairs(ROSTER) do
        local r = db.rolls[name]
        if name ~= db.me and r and r.demo then
            local bias = math.random(-25, 25)
            r.last = {}
            for k = 1, math.random(3, LUCK_KEEP) do
                r.last[k] = math.max(1, math.min(100, math.random(1, 100) + bias))
            end
            r.lastT = now
        end
    end
    for _, s in ipairs(C.BuildStats()) do
        if s.name ~= db.me and s.maxLevel > 0 then
            db.levelAt[s.name] = { l = s.maxLevel, t = now - math.random(3600, 600000), d = true }
        end
    end
    for i = 1, 4 do
        local name = ROSTER[math.random(#ROSTER)]
        if name ~= db.me then
            local it = DEMO_NEED[math.random(#DEMO_NEED)]
            AddShame({ id = "demo-N-" .. i, friend = name, char = name, class = nil, item = "item:" .. it[1], name = it[2],
                       quality = it[3], why = (math.random() < 0.5) and "gone" or "unused",
                       time = now - math.random(600, 400000), demo = true })
        end
    end
    if ns.MakeDuelDemo then ns.MakeDuelDemo() end
    if ns.MakeBankDemo then ns.MakeBankDemo() end
end

function ns.ClearPrankDemo()
    local db = DB()
    if ns.ClearDuelDemo then ns.ClearDuelDemo() end
    if ns.ClearBankDemo then ns.ClearBankDemo() end
    for friend, e in pairs(db.levelAt) do
        if e.d then db.levelAt[friend] = nil end
    end
    for i = #db.needShame, 1, -1 do
        if db.needShame[i].demo then table.remove(db.needShame, i) end
    end
end

function ns.ResetPranks()
    local db = DB()
    wipe(db.needWatch)
    wipe(db.needShame)
    db.emoteStats = { sent = {}, recv = {} }
    wipe(db.levelAt)
    if ns.ResetDuels then ns.ResetDuels() end
    if ns.ResetBank then ns.ResetBank() end
end

-- Eksempler på de nye popups (gemmes og sendes ikke)
function ns.TestPrankToasts()
    local db = WastedCoastDB
    local me = db.me or "Nick"
    local class = select(2, UnitClass("player"))
    local fake = { id = "test-" .. math.random(1, 99999), name = UnitName("player"), class = class,
                   killer = "Murloc Forager", ability = "Nærkamp", klvl = 12, level = 31, zone = "Westfall", time = time() }
    ns.Toast({ kind = "obit", head = "DØDSANNONCE", title = Name(me) .. " (level 31)", text = ns.Obituary(fake, me),
               icon = OBIT_ICON, class = class, dur = 7, force = true })
    local e = { friend = me, item = "item:28830", name = "Dragonspine Trophy", quality = 4 }
    ns.Toast({ kind = "police", head = "NEED-POLITIET", title = Name(me) .. " needede " .. ItemLink(e), text = SHAME_TEXT.gone,
               icon = ItemIcon(28830), dur = 7, force = true })
    local idx = math.random(#ATTACKS)
    ns.Toast({ kind = "emote", head = "EMOTE-ANGREB", title = "Nick angriber dig!", text = AttackText(idx, "Nick", "dig"),
               icon = EMOTE_ICON, force = true })
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
function ns.PrankSlash(cmd, arg)
    local db = DB()
    if cmd == "angrib" or cmd == "emote" then
        local name = FindFriend(arg)
        if name then ns.EmoteAttack(name) else Print("Hvem? Skriv fx |cffffd100/wc4ever angrib nick|r.") end
        return true
    elseif cmd == "annonce" or cmd == "annoncer" then
        db.settings.obits = (db.settings.obits == false)
        Print("Dødsannoncer: " .. (db.settings.obits and "til" or "fra"))
        return true
    elseif cmd == "emotes" then
        db.settings.emotes = (db.settings.emotes == false)
        Print("Popups for emote-angreb mod dig: " .. (db.settings.emotes and "til" or "fra"))
        return true
    elseif cmd == "testannonce" then
        ns.TestPrankToasts()
        return true
    end
    return false
end

-- =============================================================================
-- Events
-- =============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event, ...)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        C_Timer.After(20, ns.CheckNeeds)
        C_Timer.NewTicker(60, ns.CheckNeeds)
    elseif event == "PLAYER_LEVEL_UP" then
        OnMyLevelUp(tonumber((...)))
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage((...))
    else
        ScheduleNeedCheck()
    end
end)
