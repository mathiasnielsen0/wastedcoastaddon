local addonName, ns = ...

-- =============================================================================
-- Wasted Coast Forever (WC4ever)
--   * Kort-overblik over vennerne
--   * Scoreboard (sorterbart)
--   * Karakterer: alle karakterer hver ven har været logget ind med
--   * Loot: alle rare+ loot wins (Need/Greed/Drop, dungeon/raid/verden)
--   * Dødstæller, titler og presence (hvem er online)
--   * v0.4: egne lyde, toasts, wipe- og bosstæller, trofæer og levelling-race
--   * v0.5: dødsstatistik, uheldsrating for rolls, guldgraf, professions, gear,
--           reputation og et indstillingsvindue i spillets Options
--   * v0.5.1: synk uden fælles guild (skjult kanal og whispers som reserve)
--   * v0.6: drillerier (dødsannoncer, Skammens hat, Need-politiet, emote-angreb og
--           held-rangering). De ligger i Drilleri.lua, som bruger ns.core herfra.
--   * v0.7: virker både på TBC Anniversary og WoW Forever (max level, instanser og API)
--   * v0.7.1: flottere UI (faner med ikoner, skygge, glans, statusbars og pænere toasts)
--   * v0.7.2: WC4L-logo ved minimappet (klik åbner vinduet)
--   * v0.8: kun fire faner (Venner, Rangliste, Loot & død, Sjov) med undersider
--   * v0.8.1: legacy points pr. ven på WoW Forever
--   * v0.9.1: honor points og honorable kills pr. ven
--   * v0.9.2: nyt navn: Wasted Coast Forever (WC4ever), /wc4ever (/wc4l virker stadig)
-- =============================================================================

local PREFIX = "WCOAST"   -- addon-besked prefix (max 16 tegn)
local SCHEMA = 5          -- version af dataformatet i SavedVariables

-- Vennerne. Rækkefølgen bestemmer rækkefølgen på kortene.
local ROSTER = { "Mikkel", "Mathias", "Nick", "Andreas", "Frode", "Søren", "Rasmus", "Jeppe" }
local ROSTER_SET = {}
for _, n in ipairs(ROSTER) do ROSTER_SET[n] = true end

-- Item-kvalitet (farvekoden i item-links afgør kvaliteten)
local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}
local HEX_QUALITY = {}
for q, h in pairs(QUALITY_HEX) do HEX_QUALITY[h] = q end
local QUALITY_NAME = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

-- Loot: hvor og hvordan
local LOOT_CONTEXTS = {
    { key = "all",     label = "Alle" },
    { key = "dungeon", label = "Dungeon" },
    { key = "raid",    label = "Raid" },
    { key = "world",   label = "Verden" },
    { key = "bg",      label = "PvP" },
}
local CTX_LABEL = { dungeon = "Dungeon", raid = "Raid", world = "Verden", bg = "PvP" }
local CTX_COLOR = { dungeon = "5ab0ff", raid = "ff8040", world = "9aa0a6", bg = "ff5050" }
local HOW_LABEL = { need = "Need", greed = "Greed", de = "Disenchant", roll = "Roll", drop = "Drop" }

local ENV_NAMES = {
    Falling  = "Faldskade",
    Drowning = "Drukning",
    Fatigue  = "Udmattelse",
    Fire     = "Ild",
    Lava     = "Lava",
    Slime    = "Slim",
}

-- =============================================================================
-- Spilversion: TBC Anniversary (2.5.x), Classic Era (1.15.x) eller WoW Forever (1.60.x).
-- Forever kører på den moderne (Midnight) motor: ingen combat log for addons,
-- "secret values" og C_-udgaver af mange gamle API-funktioner.
-- =============================================================================
local GAME = {}
do
    local toc = select(4, GetBuildInfo()) or 0
    GAME.toc = toc
    -- WOW_PROJECT_CAMELOT er Forevers interne navn; Blizzard har sagt, at det kan blive omdøbt,
    -- så interface-nummeret (16xxx) er reserven.
    local pid = WOW_PROJECT_ID
    GAME.isForever = (pid ~= nil and ((WOW_PROJECT_CAMELOT and pid == WOW_PROJECT_CAMELOT)
        or (WOW_PROJECT_FOREVER and pid == WOW_PROJECT_FOREVER))) or (toc >= 16000 and toc < 20000) or false
    GAME.isTBC = not GAME.isForever and toc >= 20000 and toc < 30000
    GAME.isEra = not GAME.isForever and toc < 16000
    GAME.label = GAME.isForever and "WoW Forever" or GAME.isTBC and "TBC Anniversary" or GAME.isEra and "Classic Era" or "WoW"
    GAME.maxLevel = (GAME.isForever or GAME.isEra) and 60 or GAME.isTBC and 70
        or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 70

    -- Secret values (Forever/Midnight) kan ikke sammenlignes eller testes; dem behandler vi som "ukendt"
    local isSecret = issecretvalue or function() return false end
    function GAME.Plain(v)
        if isSecret(v) then return nil end
        return v
    end

    -- Item-info: Forever har kun C_Item-udgaverne
    function GAME.ItemInfo(item)
        local fn = GetItemInfo or (C_Item and C_Item.GetItemInfo)
        if fn then return fn(item) end
    end
    function GAME.ItemInfoInstant(item)
        local fn = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
        if fn then return fn(item) end
    end
end

local MAX_LEVEL = GAME.maxLevel

local function Norm(s)
    return (tostring(s or ""):lower():gsub("[^%w]", ""))
end

-- Kendte instanser og deres bosser (engelske navne, som spillet bruger).
-- 'final' er den eller de bosser, der afslutter instancen (= en "clear").
-- Instanser der ikke står her tæller stadig wipes og bosskills, men aldrig clears.
local BOSSES = {}
local BOSS_BY_NORM = {}
local function Inst(name, final, ...)
    local info = { list = { ... }, last = {}, byNorm = {} }
    for _, b in ipairs(info.list) do info.byNorm[Norm(b)] = b end
    for f in final:gmatch("[^|]+") do
        info.last[Norm(f)] = true
        if not info.byNorm[Norm(f)] then
            info.list[#info.list + 1] = f
            info.byNorm[Norm(f)] = f
        end
    end
    BOSSES[name] = info
    BOSS_BY_NORM[Norm(name)] = info
end

-- TBC-instanser. Forever har sin egen "Hyjal Summit" (en anden raid), så de må ikke blandes.
if not GAME.isForever then
    Inst("Hellfire Ramparts", "Nazan|Vazruden the Herald", "Watchkeeper Gargolmar", "Omor the Unscarred", "Vazruden the Herald", "Nazan")
    Inst("The Blood Furnace", "Keli'dan the Breaker", "The Maker", "Broggok", "Keli'dan the Breaker")
    Inst("The Shattered Halls", "Warchief Kargath Bladefist", "Grand Warlock Nethekurse", "Blood Guard Porung", "Warbringer O'mrogg", "Warchief Kargath Bladefist")
    Inst("The Slave Pens", "Quagmirran", "Mennu the Betrayer", "Rokmar the Crackler", "Quagmirran")
    Inst("The Underbog", "The Black Stalker", "Hungarfen", "Ghaz'an", "Swamplord Musel'ek", "The Black Stalker")
    Inst("The Steamvault", "Warlord Kalithresh", "Hydromancer Thespia", "Mekgineer Steamrigger", "Warlord Kalithresh")
    Inst("Mana-Tombs", "Nexus-Prince Shaffar", "Pandemonius", "Tavarok", "Nexus-Prince Shaffar")
    Inst("Auchenai Crypts", "Exarch Maladaar", "Shirrak the Dead Watcher", "Exarch Maladaar")
    Inst("Sethekk Halls", "Talon King Ikiss", "Darkweaver Syth", "Talon King Ikiss")
    Inst("Shadow Labyrinth", "Murmur", "Ambassador Hellmaw", "Blackheart the Inciter", "Grandmaster Vorpil", "Murmur")
    Inst("Old Hillsbrad Foothills", "Epoch Hunter", "Lieutenant Drake", "Captain Skarloc", "Epoch Hunter")
    Inst("The Black Morass", "Aeonus", "Chrono Lord Deja", "Temporus", "Aeonus")
    Inst("The Mechanar", "Pathaleon the Calculator", "Mechano-Lord Capacitus", "Nethermancer Sepethrea", "Pathaleon the Calculator")
    Inst("The Botanica", "Warp Splinter", "Commander Sarannis", "High Botanist Freywinn", "Thorngrin the Tender", "Laj", "Warp Splinter")
    Inst("The Arcatraz", "Harbinger Skyriss", "Zereketh the Unbound", "Dalliah the Doomsayer", "Wrath-Scryer Soccothrates", "Harbinger Skyriss")
    Inst("Magisters' Terrace", "Kael'thas Sunstrider", "Selin Fireheart", "Vexallus", "Priestess Delrissa", "Kael'thas Sunstrider")
    Inst("Karazhan", "Prince Malchezaar", "Attumen the Huntsman", "Moroes", "Maiden of Virtue", "The Curator", "Terestian Illhoof", "Shade of Aran", "Netherspite", "Nightbane", "Prince Malchezaar")
    Inst("Gruul's Lair", "Gruul the Dragonkiller", "High King Maulgar", "Gruul the Dragonkiller")
    Inst("Magtheridon's Lair", "Magtheridon")
    Inst("Serpentshrine Cavern", "Lady Vashj", "Hydross the Unstable", "The Lurker Below", "Leotheras the Blind", "Fathom-Lord Karathress", "Morogrim Tidewalker", "Lady Vashj")
    Inst("Tempest Keep", "Kael'thas Sunstrider", "Al'ar", "High Astromancer Solarian", "Void Reaver", "Kael'thas Sunstrider")
    Inst("Hyjal Summit", "Archimonde", "Rage Winterchill", "Anetheron", "Kaz'rogal", "Azgalor", "Archimonde")
    Inst("Black Temple", "Illidan Stormrage", "High Warlord Naj'entus", "Supremus", "Shade of Akama", "Teron Gorefiend", "Gurtogg Bloodboil", "Reliquary of Souls", "Mother Shahraz", "The Illidari Council", "Illidan Stormrage")
    Inst("Zul'Aman", "Zul'jin", "Nalorakk", "Akil'zon", "Jan'alai", "Halazzi", "Hex Lord Malacrass", "Zul'jin")
    Inst("Sunwell Plateau", "Kil'jaeden", "Kalecgos", "Brutallus", "Felmyst", "Lady Sacrolash", "Grand Warlock Alythess", "M'uru", "Kil'jaeden")
end
-- Klassiske instanser: kun slutbossen er kendt
Inst("Ragefire Chasm", "Bazzalan")
Inst("The Deadmines", "Edwin VanCleef")
Inst("Wailing Caverns", "Mutanus the Devourer")
Inst("Shadowfang Keep", "Archmage Arugal")
Inst("Blackfathom Deeps", "Aku'mai")
Inst("Stormwind Stockade", "Bazil Thredd")
Inst("Gnomeregan", "Mekgineer Thermaplugg")
Inst("Razorfen Kraul", "Charlga Razorflank")
Inst("Razorfen Downs", "Amnennar the Coldbringer")
Inst("Uldaman", "Archaedas")
Inst("Zul'Farrak", "Chief Ukorz Sandscalp")
Inst("Maraudon", "Princess Theradras")
Inst("The Temple of Atal'Hakkar", "Shade of Eranikus")
Inst("Blackrock Depths", "Emperor Dagran Thaurissan")
Inst("Stratholme", "Baron Rivendare")
Inst("Scholomance", "Darkmaster Gandling")
Inst("Molten Core", "Ragnaros")
Inst("Blackwing Lair", "Nefarian")
Inst("Onyxia's Lair", "Onyxia")
Inst("Zul'Gurub", "Hakkar")
Inst("Ruins of Ahn'Qiraj", "Ossirian the Unscathed")
Inst("Temple of Ahn'Qiraj", "C'Thun")
Inst("Naxxramas", "Kel'Thuzad")

-- Forever har nye instanser og ombyggede gamle, så her henter vi bosserne fra spillets eget
-- Encounter Journal (rækkefølgen dér: den sidste boss er slutbossen). Findes journalen ikke,
-- bruges listen ovenfor.
local JournalBosses
do
    local index, cache = nil, {}
    local function Key(s) return (Norm(s):gsub("^the", "")) end

    local function BuildIndex()
        index = {}
        if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return end
        local oldTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
        for tier = 1, EJ_GetNumTiers() or 0 do
            EJ_SelectTier(tier)
            for _, isRaid in ipairs({ false, true }) do
                local i = 1
                while i < 200 do
                    local id, name = EJ_GetInstanceByIndex(i, isRaid)
                    if not id then break end
                    if name then index[Key(name)] = id end
                    i = i + 1
                end
            end
        end
        if oldTier then EJ_SelectTier(oldTier) end
    end

    function JournalBosses(inst)
        local key = Key(inst)
        if cache[key] ~= nil then return cache[key] or nil end
        if not index and not pcall(BuildIndex) then index = {} end
        local id = index[key]
        local info = false
        if id and EJ_GetEncounterInfoByIndex then
            local names = {}
            pcall(function()
                local i = 1
                while i < 40 do
                    local name = EJ_GetEncounterInfoByIndex(i, id)
                    if not name then break end
                    names[#names + 1] = name
                    i = i + 1
                end
            end)
            if #names > 0 then
                info = { list = names, last = { [Norm(names[#names])] = true }, byNorm = {} }
                for _, b in ipairs(names) do info.byNorm[Norm(b)] = b end
            end
        end
        cache[key] = info
        return info or nil
    end
end

local function BossInfo(inst)
    if not inst then return nil end
    if GAME.isForever then
        local info = JournalBosses(inst)
        if info then return info end
    end
    return BOSS_BY_NORM[Norm(inst)]
end

local SendMsg = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

local db            -- sættes i InitDB (= WastedCoastDB)
local lastDamage    -- { t = GetTime(), source = "...", ability = "..." }

-- =============================================================================
-- Hjælpefunktioner
-- =============================================================================
local function Print(msg)
    print("|cff33ff99WC4ever:|r " .. msg)
end

-- Beskeder bruger ";" som skilletegn, så det må ikke findes i felterne
local function Clean(s)
    return (tostring(s or ""):gsub(";", ","))
end

local function Round255(x)
    return math.floor(x * 255 + 0.5)
end

local function HexToRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.62, 0.62, 0.66
end

local function ColorName(name, class)
    local r, g, b = ClassColor(class)
    return string.format("|cff%02x%02x%02x%s|r", Round255(r), Round255(g), Round255(b), name)
end

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or class or "?"
end

local function FormatAgo(t)
    if not t then return "aldrig set" end
    local d = time() - t
    if d < 60 then return "lige nu" end
    if d < 3600 then return string.format("%d min siden", math.floor(d / 60)) end
    if d < 86400 then return string.format("%d t siden", math.floor(d / 3600)) end
    return string.format("%d d siden", math.floor(d / 86400))
end

local function FormatAgoShort(t)
    if not t then return "-" end
    local d = time() - t
    if d < 60 then return "nu" end
    if d < 3600 then return string.format("%dm", math.floor(d / 60)) end
    if d < 86400 then return string.format("%dt", math.floor(d / 3600)) end
    return string.format("%dd", math.floor(d / 86400))
end

local function FormatGold(copper)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    return string.format("%dg %ds", g, s)
end

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

-- =============================================================================
-- Lyd: egne lydklip (se Sounds.lua) med Blizzards lyd som reserve
-- =============================================================================
local SOUND_DIR = "Interface\\AddOns\\WastedCoast\\sounds\\"
local SOUND_EVENTS = { "death", "loot", "wipe", "online", "levelup", "achievement", "bosskill" }
-- Hvis der ikke er valgt en egen lyd, bruges disse (tal eller SOUNDKIT-navne). Events uden
-- reserve er tavse, indtil du selv vælger en lyd.
local FALLBACK_SOUND = {
    death = { "RAID_WARNING" },
    wipe = { "RAID_WARNING" },
    levelup = { "LEVELUP", 888 },
    achievement = { "LEVELUP", 888 },
}

local function PickSound(event, friend)
    local cfg = ns.sounds
    if type(cfg) ~= "table" then return nil end
    local per = friend and type(cfg.friends) == "table" and cfg.friends[friend]
    local list
    if type(per) == "table" and type(per[event]) == "table" and #per[event] > 0 then
        list = per[event]
    elseif type(cfg[event]) == "table" and #cfg[event] > 0 then
        list = cfg[event]
    end
    if not list then return nil end
    return list[math.random(#list)]
end

-- Afspiller lyden til et event. Returnerer ok, beskrivelse (bruges af /wc4ever sound <event>)
local function PlayEventSound(event, friend, force)
    if not db or (not db.settings.sound and not force) then return false, "lyd er slået fra" end
    local note
    local file = PickSound(event, friend)
    if file then
        local ok, willPlay = pcall(PlaySoundFile, SOUND_DIR .. tostring(file), "Master")
        if ok and willPlay then return true, file end
        note = "filen " .. tostring(file) .. " kunne ikke afspilles (findes den i sounds-mappen? Har du genstartet spillet?)"
    end
    for _, key in ipairs(FALLBACK_SOUND[event] or {}) do
        local id = type(key) == "number" and key or (SOUNDKIT and SOUNDKIT[key])
        if id then
            pcall(PlaySound, id)
            return true, "Blizzards egen lyd" .. (note and (" (" .. note .. ")") or "")
        end
    end
    return false, note or "ingen lyd valgt til dette event"
end

-- =============================================================================
-- Item-links
-- =============================================================================
local function ParseLink(text)
    if type(text) ~= "string" then return nil end
    local itemString = text:match("|H(item:[^|]+)|h")
    if not itemString then return nil end
    local id = tonumber(itemString:match("^item:(%d+)"))
    local name = text:match("|h%[(.-)%]|h")
    local color = text:match("|c%x%x(%x%x%x%x%x%x)")
    local quality = color and HEX_QUALITY[color:lower()]
    if not quality then
        local _, _, q = GAME.ItemInfo(itemString)
        quality = q
    end
    if not id or not name or not quality then return nil end
    return { id = id, itemString = itemString, name = name, quality = quality }
end

local function LootLink(ev)
    return string.format("|cff%s|H%s|h[%s]|h|r", QUALITY_HEX[ev.quality] or "ffffff", ev.item, ev.name)
end

local function LootItemID(ev)
    return tonumber((ev.item or ""):match("^item:(%d+)"))
end

-- =============================================================================
-- Database (SavedVariables)
-- =============================================================================
local function InitDB()
    WastedCoastDB = WastedCoastDB or {}
    db = WastedCoastDB
    db.events = db.events or {}      -- liste af dødsfald
    db.seen = db.seen or {}          -- id -> true, bruges til at fjerne dubletter
    db.loot = db.loot or {}          -- liste af loot wins
    db.lootSeen = db.lootSeen or {}
    db.settings = db.settings or {}
    db.chars = db.chars or {}        -- karakternavn -> ven
    db.friends = db.friends or {}    -- ven -> { chars = { karakter -> { class, level, gold, zone, seen } } }
    db.runs = db.runs or {}          -- ven -> instans -> { wipes, clears, boss = { navn = antal }, last }
    db.ach = db.ach or {}            -- ven -> trofæ-id -> tidspunkt
    db.demoAch = db.demoAch or {}    -- demo-trofæer (fjernes af /wc4ever demo slut)
    db.rolls = db.rolls or {}        -- ven -> { rolls, wins, sum, cnt, low, high }
    db.goldHist = db.goldHist or {}  -- ven -> { { tid, kobber }, ... } sorteret efter tid
    db.legacy = db.legacy or {}      -- ven -> { p = legacy points, c = klarede challenges, t } (kun WoW Forever)
    if db.settings.toasts == nil then db.settings.toasts = true end
    if db.settings.sound == nil then db.settings.sound = true end
    if db.settings.announce == nil then db.settings.announce = true end
    -- Standard: rare eller bedre (3). Ældre installationer havde epic (4) som standard og flyttes med.
    if db.settings.minQuality == nil or not db.settings.qualityV2 then db.settings.minQuality = 3 end
    db.settings.qualityV2 = true

    -- Migrering fra v0.2: ven-felter flyttes ind under karakterer, rating fjernes
    for _, info in pairs(db.friends) do
        if not info.chars then
            info.chars = {}
            if info.char then
                info.chars[info.char] = {
                    class = info.class, level = info.level, gold = info.gold,
                    zone = info.zone, seen = info.seen, demo = info.demo,
                }
            end
        end
        info.char, info.class, info.level, info.gold, info.zone, info.seen, info.demo = nil, nil, nil, nil, nil, nil, nil
    end
    db.ratings = nil
    db.schemaVersion = SCHEMA
    -- db.me = hvilken ven du er (sættes via identitetsvalget)
end

local function FriendOfChar(charName)
    if not charName then return nil end
    return db.chars[charName] or (ROSTER_SET[charName] and charName) or nil
end

local function EventFriend(ev)
    local f = ev.friend
    if f and f ~= "" and ROSTER_SET[f] then return f end
    return FriendOfChar(ev.name)
end

local function LootFriend(ev)
    local f = ev.friend
    if f and f ~= "" and ROSTER_SET[f] then return f end
    return FriendOfChar(ev.char)
end

-- Opret/opdater en karakter hos en ven. data = { class, level, gold, zone }
local function UpdateChar(friend, char, data, seenAt, soft)
    if not friend or not ROSTER_SET[friend] or not char or char == "" then return end
    local info = db.friends[friend]
    if not info then info = { chars = {} }; db.friends[friend] = info end
    info.chars = info.chars or {}
    local c = info.chars[char]
    if not c then c = {}; info.chars[char] = c end
    if data then
        for k, v in pairs(data) do
            if v ~= nil and v ~= "" and not (k == "level" and v <= 0) then
                if not soft or c[k] == nil then c[k] = v end
            end
        end
    end
    seenAt = seenAt or time()
    if not c.seen or seenAt > c.seen then c.seen = seenAt end
    c.demo = nil
    db.chars[char] = friend
    return c
end

local function IsNewer(nameA, a, nameB, b)
    local sa, sb = a.seen or 0, b.seen or 0
    if sa ~= sb then return sa > sb end
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la > lb end
    return nameA < nameB
end

local function LastSeen(friend)
    local info = db.friends[friend]
    local best
    if info and info.chars then
        for _, c in pairs(info.chars) do
            if c.seen and (not best or c.seen > best) then best = c.seen end
        end
    end
    return best
end

local function IsOnline(name)
    if name == db.me then return true end
    local seen = LastSeen(name)
    return (seen and (time() - seen) < 150) and true or false
end

-- =============================================================================
-- Statistik og titler
-- =============================================================================
local function DeathsByFriend()
    local counts = {}
    for _, ev in ipairs(db.events) do
        local f = EventFriend(ev)
        if f then counts[f] = (counts[f] or 0) + 1 end
    end
    return counts
end

local function LootByFriend()
    local counts = {}
    for _, ev in ipairs(db.loot) do
        local f = LootFriend(ev)
        if f then counts[f] = (counts[f] or 0) + 1 end
    end
    return counts
end

local function TopKiller(friend)
    local counts, best, bestN = {}, nil, 0
    for _, ev in ipairs(db.events) do
        if ev.killer and ev.killer ~= "" and ev.killer ~= "Ukendt" and EventFriend(ev) == friend then
            counts[ev.killer] = (counts[ev.killer] or 0) + 1
            if counts[ev.killer] > bestN then best, bestN = ev.killer, counts[ev.killer] end
        end
    end
    return best, bestN
end

local function LatestLoot(friend)
    local best
    for _, ev in ipairs(db.loot) do
        if LootFriend(ev) == friend and (not best or ev.time > best.time) then best = ev end
    end
    return best
end

-- Alle karakterer hos en ven, sorteret efter level og derefter senest set
local function CharList(friend)
    local list = {}
    local info = db.friends[friend]
    if not info or not info.chars then return list end

    local dBy, lBy = {}, {}
    for _, ev in ipairs(db.events) do
        if EventFriend(ev) == friend then dBy[ev.name] = (dBy[ev.name] or 0) + 1 end
    end
    for _, ev in ipairs(db.loot) do
        if LootFriend(ev) == friend then lBy[ev.char] = (lBy[ev.char] or 0) + 1 end
    end

    local now = time()
    for name, c in pairs(info.chars) do
        list[#list + 1] = {
            name = name, class = c.class, level = c.level or 0, zone = c.zone, gold = c.gold or 0,
            seen = c.seen, deaths = dBy[name] or 0, loot = lBy[name] or 0,
            online = (c.seen and (now - c.seen) < 150) and true or false,
        }
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if (a.seen or 0) ~= (b.seen or 0) then return (a.seen or 0) > (b.seen or 0) end
        return a.name < b.name
    end)
    return list
end


-- =============================================================================
-- Instans-statistik: db.runs[ven][instans] = { wipes, clears, boss = { navn = antal }, last }
-- =============================================================================
local function RunEntry(friend, inst, create)
    local fr = db.runs[friend]
    if not fr then
        if not create then return nil end
        fr = {}
        db.runs[friend] = fr
    end
    local e = fr[inst]
    if not e and create then
        e = { wipes = 0, clears = 0, boss = {}, last = 0 }
        fr[inst] = e
    end
    if e then e.boss = e.boss or {} end
    return e
end

-- Samlet antal wipes, clears og bosskills for en ven
local function RunTotals(friend)
    local w, c, k = 0, 0, 0
    for _, e in pairs(db.runs[friend] or {}) do
        w = w + (e.wipes or 0)
        c = c + (e.clears or 0)
        for _, n in pairs(e.boss or {}) do k = k + n end
    end
    return w, c, k
end

-- v0.5: dødsstatistik og roll-tal (i en blok pga. Luas grænse på 200 lokale variabler)
do
    -- =============================================================================
    -- Dødsstatistik: farligste mob, farligste zone og faldskade-kongen
    -- =============================================================================
    local function IsFall(ev)
        return (ev.killer == "Omgivelserne" and ev.ability == ENV_NAMES.Falling) or ev.killer == ENV_NAMES.Falling
    end

    local function IsEnvironment(ev)
        if ev.killer == "Omgivelserne" then return true end
        for _, n in pairs(ENV_NAMES) do
            if ev.killer == n then return true end
        end
        return false
    end

    -- Sorteret liste af { name, n, who = { ven = antal } }, flest først
    local function RankCounts(map)
        local list = {}
        for name, e in pairs(map) do list[#list + 1] = { name = name, n = e.n, who = e.who } end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
        return list
    end

    local function DeathStats()
        local mobs, zones, falls = {}, {}, {}
        local function bump(map, key, friend)
            local e = map[key]
            if not e then e = { n = 0, who = {} }; map[key] = e end
            e.n = e.n + 1
            e.who[friend] = (e.who[friend] or 0) + 1
        end
        for _, ev in ipairs(db.events) do
            local f = EventFriend(ev)
            if f then
                if ev.killer and ev.killer ~= "" and ev.killer ~= "Ukendt" and not IsEnvironment(ev) then
                    bump(mobs, ev.killer, f)
                end
                if ev.zone and ev.zone ~= "" then bump(zones, ev.zone, f) end
                if IsFall(ev) then falls[f] = (falls[f] or 0) + 1 end
            end
        end
        local fallList = {}
        for f, n in pairs(falls) do fallList[#fallList + 1] = { name = f, n = n } end
        table.sort(fallList, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
        return RankCounts(mobs), RankCounts(zones), fallList, falls
    end

    -- "Nick 4, Mathias 3"
    local function WhoText(who, max)
        local list = {}
        for f, n in pairs(who or {}) do list[#list + 1] = { f = f, n = n } end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.f < b.f
        end)
        local parts = {}
        for i = 1, math.min(#list, max or 3) do parts[i] = list[i].f .. " " .. list[i].n end
        return table.concat(parts, ", ")
    end

    -- =============================================================================
    -- Rolls: db.rolls[ven] = { rolls = deltaget, wins = vundet, sum/cnt = roll-tal, low, high }
    -- =============================================================================
    local ROLL_MIN = 5   -- færre rolls end dette giver ingen uheldsrating

    local function RollEntry(friend, create)
        local r = db.rolls[friend]
        if not r and create then
            r = { rolls = 0, wins = 0, sum = 0, cnt = 0 }
            db.rolls[friend] = r
        end
        return r
    end

    -- Andel tabte rolls (0-1), eller nil hvis der er for få rolls
    local function LossRate(r)
        if not r or (r.rolls or 0) < ROLL_MIN then return nil end
        return math.max(0, (r.rolls - (r.wins or 0))) / r.rolls
    end

    local function AvgRoll(r)
        if not r or (r.cnt or 0) == 0 then return nil end
        return r.sum / r.cnt
    end

    ns.DeathStats = DeathStats
    ns.WhoText = WhoText
    ns.ROLL_MIN = ROLL_MIN
    ns.RollEntry = RollEntry
    ns.LossRate = LossRate
    ns.AvgRoll = AvgRoll
end

-- Liste over alle venner i roster-rækkefølge
local function BuildStats()
    local deaths = DeathsByFriend()
    local loot = LootByFriend()
    local _, _, _, falls = ns.DeathStats()
    local list = {}
    for _, name in ipairs(ROSTER) do
        local info = db.friends[name] or {}
        local nChars, maxLevel, gold = 0, 0, 0
        local lastName, last
        for cn, c in pairs(info.chars or {}) do
            nChars = nChars + 1
            if (c.level or 0) > maxLevel then maxLevel = c.level end
            gold = gold + (c.gold or 0)
            if not last or IsNewer(cn, c, lastName, last) then lastName, last = cn, c end
        end
        local d, l = deaths[name] or 0, loot[name] or 0
        local rw, rc, rk = RunTotals(name)
        list[#list + 1] = {
            name = name, class = last and last.class, char = lastName,
            level = last and last.level or 0, maxLevel = maxLevel,
            zone = last and last.zone, seen = last and last.seen,
            chars = nChars, deaths = d, loot = l, gold = gold, wipes = rw, clears = rc, kills = rk,
            falls = falls[name] or 0,
            unluck = math.floor((ns.LossRate(db.rolls[name]) or 0) * 100 + 0.5),
            luck = ns.LuckPercent and ns.LuckPercent(name),
            online = IsOnline(name), isMe = (name == db.me),
            -- Wasted Coast-point: loot x 5 + højeste level - døde x 3
            points = l * 5 + maxLevel - d * 3,
        }
    end
    return list
end

-- Uddeler titler. Returnerer titles[ven] = { "Klovnen", ... } og holders[titel] = ven
local function ComputeTitles(list)
    local titles, holders = {}, {}
    local function award(key, title, min)
        local best, bestVal = nil, (min or 1) - 1
        for _, e in ipairs(list) do
            local v = e[key]
            if v and v > bestVal then best, bestVal = e.name, v end
        end
        if best then
            titles[best] = titles[best] or {}
            table.insert(titles[best], title)
            holders[title] = best
        end
    end
    award("deaths", "Klovnen")
    award("loot", "Lootgoblin")
    award("gold", "Rigmanden")
    award("maxLevel", "Højest level")
    award("chars", "Alt-junkie", 2)
    award("wipes", "Wipe-konge")
    award("falls", "Faldskade-konge")
    award("unluck", "Uheldsfuglen")
    award("luck", "Fætter Højben", 51)
    -- Skammens hat: den, der døde sidst, indtil en anden dør
    local hat = ns.HatHolder and ns.HatHolder()
    if hat then
        titles[hat] = titles[hat] or {}
        table.insert(titles[hat], 1, "Skammens hat")
        holders["Skammens hat"] = hat
    end
    -- Level-snegl: den, der er længst bagud i level
    local snail = ns.Snail and ns.Snail(list)
    if snail then
        titles[snail] = titles[snail] or {}
        table.insert(titles[snail], "Level-snegl")
        holders["Level-snegl"] = snail
    end
    return titles, holders
end

local TITLE_ORDER = { "Klovnen", "Lootgoblin", "Rigmanden", "Højest level", "Alt-junkie", "Wipe-konge",
                      "Faldskade-konge", "Uheldsfuglen", "Fætter Højben", "Skammens hat", "Level-snegl" }

-- =============================================================================
-- Netværk: kø, beskeder og synkronisering
-- =============================================================================
local queue = {}

-- Synk uden fælles guild: ud over party/raid og guild sendes alt i en skjult kanal,
-- som alle med addonet melder sig ind i. Virker kanalen ikke (eller er I på hver sin
-- side af den), går beskederne som usynlige whispers til vennens karakter.
-- (Samlet i én tabel: hovedfilen er tæt på Luas grænse på 200 lokale variabler.)
local route = {
    CHANNEL = "WC4Lsync",   -- beholdt fra WC4L-tiden, så gamle og nye versioner finder hinanden
    PASSWORD = "wastedcoast",
    TTL = 180,          -- sekunder: så længe en ven regnes for at kunne nås ad en vej
    shared = {},        -- ven -> { t, via }: sidst hørt i guild, gruppe eller kanal
    whisper = {},       -- ven -> { t, char }: sidst hørt via whisper, og fra hvilken karakter
    probed = {},        -- karakter (små bogstaver) -> GetTime() for seneste whisper derhen
    channelOK = true,   -- falsk, hvis klienten ikke kan sende addon-beskeder i en kanal
}
ns.route = route

do
    local function FallbackOn()
        return db and db.settings.fallbackSync ~= false
    end

    local function ChannelId()
        if not route.channelOK or not FallbackOn() then return 0 end
        return (GetChannelName(route.CHANNEL)) or 0
    end
    route.ChannelId = ChannelId

    local function Recent(r)
        return r and (time() - r.t) < route.TTL
    end
    route.Recent = Recent

    -- Alle de veje, en besked skal sendes ad lige nu
    function route.Targets()
        local ch = {}
        if IsInRaid() then ch[#ch + 1] = { "RAID" } elseif IsInGroup() then ch[#ch + 1] = { "PARTY" } end
        if IsInGuild() then ch[#ch + 1] = { "GUILD" } end
        if ChannelId() > 0 then ch[#ch + 1] = { "CHANNEL" } end
        -- Venner, der kun kan nås via whisper: karakteren, de sidst whisperede fra
        if FallbackOn() and db.me then
            for _, friend in ipairs(ROSTER) do
                if friend ~= db.me and not Recent(route.shared[friend]) and Recent(route.whisper[friend]) then
                    ch[#ch + 1] = { "WHISPER", route.whisper[friend].char }
                end
            end
        end
        return ch
    end

    function route.SendItem(item)
        local msg, chatType, target = item[1], item[2], item[3]
        if chatType == "CHANNEL" then
            target = ChannelId()
            if target == 0 then return end
            -- Ældre klienter kender ikke addon-beskeder i kanaler: så klarer whispers det
            local ok, res = pcall(SendMsg, PREFIX, msg, chatType, target)
            if not ok then route.channelOK = false end
            return res
        end
        if chatType == "WHISPER" then route.probed[target:lower()] = GetTime() end
        return SendMsg(PREFIX, msg, chatType, target)
    end

    -- Online karakterer på vennelisten i spillet (så I kan finde hinanden første gang)
    local function OnlineFriendList()
        local out = {}
        if C_FriendList and C_FriendList.GetNumFriends then
            for i = 1, C_FriendList.GetNumFriends() or 0 do
                local f = C_FriendList.GetFriendInfoByIndex(i)
                if f and f.connected and f.name then out[#out + 1] = f.name end
            end
        elseif GetNumFriends and GetFriendInfo then
            for i = 1, GetNumFriends() or 0 do
                local name, _, _, _, connected = GetFriendInfo(i)
                if name and connected then out[#out + 1] = name end
            end
        end
        return out
    end

    -- Send en besked (en sync-forespørgsel) som whisper til venner, vi ikke kan nå på anden vis:
    -- deres seneste karakterer og de online karakterer på vennelisten. Den, der er online og
    -- har addonet, svarer, og derefter går beskederne den vej. "No player named"-fejlene skjules.
    function route.Probe(msg)
        if not FallbackOn() or not db.me then return end
        local me = UnitName("player")
        local targets, added = {}, {}
        local function add(char)
            if char and char ~= "" and char ~= me and not added[char] then
                added[char] = true
                targets[#targets + 1] = char
            end
        end
        local function reachable(friend)
            return friend and (friend == db.me or Recent(route.shared[friend]) or Recent(route.whisper[friend]))
        end
        for _, friend in ipairs(ROSTER) do
            if not reachable(friend) then
                local list = {}
                for name, c in pairs((db.friends[friend] and db.friends[friend].chars) or {}) do
                    if not c.demo then list[#list + 1] = { name, c } end
                end
                table.sort(list, function(a, b) return IsNewer(a[1], a[2], b[1], b[2]) end)
                for i = 1, math.min(#list, 6) do add(list[i][1]) end
            end
        end
        local n = 0
        for _, char in ipairs(OnlineFriendList()) do
            if n < 20 and not reachable(FriendOfChar(char)) then
                add(char)
                n = n + 1
            end
        end
        for _, char in ipairs(targets) do queue[#queue + 1] = { msg, "WHISPER", char } end
    end

    -- Hvem har sendt beskeden, og ad hvilken vej? Bruges til at vælge, hvor vi sender hen
    function route.Note(t, chatType, sender)
        if not chatType or not sender or not db.me then return end
        local char = (Ambiguate and Ambiguate(sender, "none")) or sender:match("^[^%-]+") or sender
        local friend = (ROSTER_SET[t[2]] and t[2]) or FriendOfChar(char)
        if not friend or friend == db.me then return end
        if chatType == "WHISPER" then
            route.whisper[friend] = { t = time(), char = char }
        elseif chatType ~= "CHANNEL" or ChannelId() > 0 then
            -- Kun en vej, vi også selv sender ad, tæller (ellers hører vennen os ikke)
            route.shared[friend] = { t = time(), via = chatType }
        end
    end

    function route.Join()
        if not FallbackOn() or not route.channelOK then return end
        if ((GetChannelName(route.CHANNEL)) or 0) == 0 then
            local join = JoinTemporaryChannel or JoinChannelByName
            if join then pcall(join, route.CHANNEL, route.PASSWORD) end
        end
        -- Kanalen skal ikke vises i chatvinduerne
        C_Timer.After(2, function()
            if not ChatFrame_RemoveChannel then return end
            for i = 1, NUM_CHAT_WINDOWS or 10 do
                local f = _G["ChatFrame" .. i]
                if f then pcall(ChatFrame_RemoveChannel, f, route.CHANNEL) end
            end
        end)
    end

    function ns.SetFallbackSync(on)
        db.settings.fallbackSync = on and true or false
        if on then
            route.channelOK = true
            route.Join()
        else
            if ((GetChannelName(route.CHANNEL)) or 0) > 0 and LeaveChannelByName then
                pcall(LeaveChannelByName, route.CHANNEL)
            end
            wipe(route.whisper)
        end
    end
end

local function Send(msg, priority)
    for _, c in ipairs(route.Targets()) do
        local item = { msg, c[1], c[2] }
        if priority then table.insert(queue, 1, item) else queue[#queue + 1] = item end
    end
    while #queue > 500 do table.remove(queue, 1) end
end

local function StartPump()
    local pauseUntil = 0
    C_Timer.NewTicker(0.3, function()
        if GetTime() < pauseUntil then return end
        local item = table.remove(queue, 1)
        if not item then return end
        -- På Forever kan addon-beskeder være spærret (fx under en boss). Så venter vi og prøver igen.
        local ok, res = pcall(route.SendItem, item)
        local R = Enum and Enum.SendAddonMessageResult
        if ok and R and res ~= nil and (res == R.AddOnMessageLockdown or res == R.AddonMessageThrottle
                or res == R.ChannelThrottle) then
            item.tries = (item.tries or 0) + 1
            if item.tries < 20 then table.insert(queue, 1, item) end
            pauseUntil = GetTime() + 5
        end
    end)
end

local function SerializeDeath(ev)
    return table.concat({
        "D", ev.id, ev.name, ev.class or "", ev.killer, ev.ability,
        ev.level, ev.zone, ev.time, ev.friend or "", ev.klvl or "",
    }, ";")
end

local function DeserializeDeath(t)
    if #t < 9 then return nil end
    local f = t[10]
    if f and not ROSTER_SET[f] then f = nil end
    return {
        id = t[2], name = t[3], class = t[4], killer = t[5], ability = t[6],
        level = tonumber(t[7]) or 0, zone = t[8], time = tonumber(t[9]) or 0,
        friend = f, klvl = tonumber(t[11]),
    }
end

local function SerializeLoot(ev)
    return table.concat({
        "L", ev.id, ev.friend or "", ev.char, ev.class or "", ev.item,
        ev.quality, ev.how, ev.ctx, ev.zone, ev.time, ev.name,
    }, ";")
end

local function DeserializeLoot(t)
    if #t < 12 then return nil end
    local q = tonumber(t[7])
    local item = t[6]
    if not q or q < 0 or q > 7 or not item:match("^item:%d+") then return nil end
    if not HOW_LABEL[t[8]] or not CTX_LABEL[t[9]] then return nil end
    local f = t[3]
    if not ROSTER_SET[f] then f = nil end
    return {
        id = t[2], friend = f, char = t[4], class = t[5], item = item, quality = q,
        how = t[8], ctx = t[9], zone = t[10], time = tonumber(t[11]) or 0, name = t[12],
    }
end

local function MyXP()
    local max = UnitXPMax and UnitXPMax("player") or 0
    if max and max > 0 then return math.floor(((UnitXP and UnitXP("player")) or 0) / max * 100) end
    return 0
end

local function SendHeartbeat()
    if not db.me then return end
    local _, class = UnitClass("player")
    local char = UnitName("player")
    local level = UnitLevel("player")
    local gold = GetMoney()
    local zone = Clean(GetZoneText())
    local xp = MyXP()
    UpdateChar(db.me, char, { class = class, level = level, gold = gold, zone = zone, xp = xp }, time())
    Send(table.concat({ "H", db.me, char, class or "", level, gold, zone, xp }, ";"))
    if ns.AfterEvent then ns.AfterEvent() end
end

-- Opdaterer kun din egen karakter lokalt (fx ved XP), uden at sende noget
local lastLocalTouch = 0
local function TouchMe()
    if not db or not db.me then return end
    local now = GetTime()
    if now - lastLocalTouch < 5 then return end
    lastLocalTouch = now
    UpdateChar(db.me, UnitName("player"), { level = UnitLevel("player"), xp = MyXP() }, time())
    if ns.RefreshUI then ns.RefreshUI() end
end

-- force = true: vennerne svarer, selvom de har svaret for nylig (knappen "Opdater" og /wc4ever sync)
local function RequestSync(force)
    if not db.me then return end
    local msg = "Q;" .. db.me .. (force and ";1" or "")
    Send(msg)
    route.Probe(msg)
end

local function IsLocalOnly(id)
    return id:find("^test%-") or id:find("^demo%-")
end

-- Svar på en sync-forespørgsel: send MINE egne karakterer, dødsfald og loot
local function RespondToSync()
    if not db.me then return end
    SendHeartbeat()

    local info = db.friends[db.me]
    if info and info.chars then
        for name, c in pairs(info.chars) do
            Send(table.concat({
                "C", db.me, name, c.class or "", c.level or 0, c.gold or 0, Clean(c.zone), c.seen or 0, c.xp or 0,
            }, ";"))
        end
    end

    local sent = 0
    for i = #db.events, 1, -1 do
        local ev = db.events[i]
        if EventFriend(ev) == db.me and not IsLocalOnly(ev.id) then
            Send(SerializeDeath(ev))
            sent = sent + 1
            if sent >= 60 then break end
        end
    end

    sent = 0
    for i = #db.loot, 1, -1 do
        local ev = db.loot[i]
        if LootFriend(ev) == db.me and not IsLocalOnly(ev.id) then
            Send(SerializeLoot(ev))
            sent = sent + 1
            if sent >= 60 then break end
        end
    end

    if ns.SendMyExtras then ns.SendMyExtras() end
end

-- =============================================================================
-- Dødsfald
-- =============================================================================
local function AddDeath(ev)
    if db.seen[ev.id] then return false end   -- allerede set
    db.seen[ev.id] = true
    table.insert(db.events, ev)

    if ev.friend and ROSTER_SET[ev.friend] then
        UpdateChar(ev.friend, ev.name, { class = ev.class, level = ev.level }, ev.time, true)
    end
    local f = EventFriend(ev)

    -- Chat og lyd kun for nye dødsfald (ikke historik fra synk)
    if (time() - (ev.time or 0)) < 120 then
        if db.settings.announce then
            local shown = f or ev.name
            local what = ev.killer
            if ev.ability ~= "" then what = what .. " (" .. ev.ability .. ")" end
            local extra = (f and ev.name ~= f) and (" (" .. ev.name .. ")") or ""
            Print(string.format("%s%s døde til %s i %s.", ColorName(shown, ev.class), extra, what, ev.zone))
        end
        PlayEventSound("death", f)
        if ns.OnFreshDeath then ns.OnFreshDeath(ev, f) end
    end

    if ns.AfterEvent then ns.AfterEvent() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function OnCombatLog()
    local _, sub, _, _, sourceName, _, _, destGUID, destName, _, _, a12, a13 = CombatLogGetCurrentEventInfo()
    if sub == "UNIT_DIED" then
        if ns.CheckBossDeath then ns.CheckBossDeath(destName) end
        return
    end
    if destGUID ~= UnitGUID("player") then return end

    if sub == "SWING_DAMAGE" then
        lastDamage = { t = GetTime(), source = sourceName or "Ukendt", ability = "Nærkamp" }
    elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        lastDamage = { t = GetTime(), source = sourceName or "Ukendt", ability = a13 or "" }
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        lastDamage = { t = GetTime(), source = "Omgivelserne", ability = ENV_NAMES[a12] or tostring(a12) }
    end
end

local function OnPlayerDead()
    local killer, ability = "Ukendt", ""
    if lastDamage and (GetTime() - lastDamage.t) < 15 then
        killer, ability = lastDamage.source, lastDamage.ability
    elseif GAME.isForever then
        -- Uden combat log er vores bedste bud den fjende, vi havde i target
        local P = GAME.Plain
        if P(UnitExists("target")) and P(UnitCanAttack("player", "target")) then
            local t = P(UnitName("target"))
            if type(t) == "string" and t ~= "" then killer = t end
        end
    end

    local name = UnitName("player")
    local _, class = UnitClass("player")
    local ev = {
        id      = name .. "-" .. time(),
        name    = name,
        class   = class,
        killer  = Clean(killer),
        ability = Clean(ability),
        level   = UnitLevel("player"),
        zone    = Clean(GetZoneText()),
        time    = time(),
        friend  = db.me,
        klvl    = ns.KillerLevel and ns.KillerLevel(killer) or nil,
    }
    if AddDeath(ev) then
        Send(SerializeDeath(ev), true)
        if ns.OnMyDeath then ns.OnMyDeath(ev) end
    end
end

-- =============================================================================
-- Loot
-- =============================================================================
local function AddLoot(ev)
    if db.lootSeen[ev.id] then return false end
    db.lootSeen[ev.id] = true
    table.insert(db.loot, ev)

    if ev.friend and ROSTER_SET[ev.friend] then
        UpdateChar(ev.friend, ev.char, { class = ev.class }, ev.time, true)
    end
    local f = LootFriend(ev)

    if db.settings.announce and (time() - (ev.time or 0)) < 120 then
        local who = ColorName(f or ev.char, ev.class)
        if f and ev.char ~= f then who = who .. " (" .. ev.char .. ")" end
        Print(string.format("%s vandt %s (%s) - %s.", who, LootLink(ev), HOW_LABEL[ev.how] or ev.how, ev.zone))
    end
    if (time() - (ev.time or 0)) < 120 then PlayEventSound("loot", f) end

    if ns.AfterEvent then ns.AfterEvent() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    -- Tekster med nummererede felter (%1$s) bliver til ugyldige mønstre, så dem springer vi over
    if fmt:find("%%%d") then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- Bygges fra spillets egne tekster, så det virker på alle sprog
local LOOT_PATTERNS = {}
local function BuildLootPatterns()
    local function add(kind, how, globalName)
        local pat = FormatToPattern(_G[globalName])
        if pat then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = { kind = kind, how = how, pattern = pat } end
    end
    add("won", "need", "LOOT_ROLL_YOU_WON_NO_SPAM_NEED")
    add("won", "greed", "LOOT_ROLL_YOU_WON_NO_SPAM_GREED")
    add("won", "de", "LOOT_ROLL_YOU_WON_NO_SPAM_DE")
    add("won", nil, "LOOT_ROLL_YOU_WON")
    add("choice", "need", "LOOT_ROLL_NEED_SELF")
    add("choice", "greed", "LOOT_ROLL_GREED_SELF")
    add("choice", "de", "LOOT_ROLL_DISENCHANT_SELF")
    add("rolled", "need", "LOOT_ROLL_ROLLED_NEED")
    add("rolled", "greed", "LOOT_ROLL_ROLLED_GREED")
    add("rolled", "de", "LOOT_ROLL_ROLLED_DE")
    add("drop", "drop", "LOOT_ITEM_SELF_MULTIPLE")
    add("drop", "drop", "LOOT_ITEM_SELF")
end

local function InstanceContext()
    local inInstance, kind = IsInInstance()
    if inInstance then
        local name
        if GetInstanceInfo then name = GetInstanceInfo() end
        name = name or GetZoneText()
        if kind == "party" then return "dungeon", name end
        if kind == "raid" then return "raid", name end
        if kind == "pvp" or kind == "arena" then return "bg", name end
        return "world", name
    end
    return "world", GetZoneText()
end

local lootSeq = 0
local rollChoice = {}   -- itemID -> { how, t }
local recentRoll = {}   -- itemID -> tidspunkt for roll-sejr

local function RecordLoot(it, how, isDrop)
    if it.quality < (db.settings.minQuality or 4) then return end
    if isDrop then
        -- Spring crafting-materialer over (fx Void Crystals fra disenchant)
        local _, _, _, _, _, classID = GAME.ItemInfoInstant(it.id)
        if classID == 7 then return end
    end

    local ctx, place = InstanceContext()
    local _, class = UnitClass("player")
    local char = UnitName("player")
    lootSeq = lootSeq + 1
    local ev = {
        id      = string.format("L-%s-%d-%d-%d", char, time(), it.id, lootSeq),
        friend  = db.me,
        char    = char,
        class   = class,
        item    = it.itemString,
        name    = Clean(it.name):sub(1, 40),
        quality = it.quality,
        how     = how,
        ctx     = ctx,
        zone    = Clean(place):sub(1, 30),
        time    = time(),
    }
    if AddLoot(ev) and db.me then Send(SerializeLoot(ev), true) end
end

do
    -- Roll-tal: deltagelse, sejre og selve tallene. Sendes samlet lidt efter, så en
    -- hel bunke rolls fra én boss kun giver én besked.
    local rollSendPending = false
    local function SendRollSummary()
        local r = db.me and ns.RollEntry(db.me)
        if r then
            Send(string.format("R;%s;%d;%d;%d;%d;%d;%d", db.me, r.rolls, r.wins, r.sum, r.cnt, r.low or 0, r.high or 0))
        end
    end

    local function RollChanged()
        if ns.AfterEvent then ns.AfterEvent() end
        if ns.RefreshUI then ns.RefreshUI() end
        if rollSendPending then return end
        rollSendPending = true
        C_Timer.After(15, function()
            rollSendPending = false
            SendRollSummary()
        end)
    end

    local lastRollWin = {}   -- itemID -> tidspunkt, så samme sejr ikke tælles to gange
    local function CountRollWin(it)
        if not db.me then return end
        local now = GetTime()
        if lastRollWin[it.id] and now - lastRollWin[it.id] < 3 then return end
        lastRollWin[it.id] = now
        local r = ns.RollEntry(db.me, true)
        r.wins = r.wins + 1
        if r.rolls < r.wins then r.rolls = r.wins end
        RollChanged()
    end

    local function CountRollChoice()
        if not db.me then return end
        local r = ns.RollEntry(db.me, true)
        r.rolls = r.rolls + 1
        RollChanged()
    end

    local function CountRollValue(value, who)
        if not db.me or not value then return end
        if who ~= UnitName("player") and who ~= YOU and who ~= "You" then return end
        if value < 1 or value > 100 then return end
        local r = ns.RollEntry(db.me, true)
        r.sum = r.sum + value
        r.cnt = r.cnt + 1
        if not r.low or value < r.low then r.low = value end
        if not r.high or value > r.high then r.high = value end
        if ns.AddRecentRoll then ns.AddRecentRoll(value) end
        RollChanged()
    end

    ns.SendRollSummary = SendRollSummary
    ns.CountRollWin = CountRollWin
    ns.CountRollChoice = CountRollChoice
    ns.CountRollValue = CountRollValue
end

local function OnLootMessage(msg)
    msg = GAME.Plain(msg)
    if type(msg) ~= "string" then return end
    for _, p in ipairs(LOOT_PATTERNS) do
        if msg:find(p.pattern) then
            if p.kind == "rolled" then
                -- "Need Roll - 54 for [item] by Navn"
                local value, _, who = msg:match(p.pattern)
                ns.CountRollValue(tonumber(value), who)
                return
            end
            local it = ParseLink(msg)
            if not it then return end
            if p.kind == "choice" then
                rollChoice[it.id] = { how = p.how, t = GetTime() }
                ns.CountRollChoice()
            elseif p.kind == "won" then
                local how = p.how
                if not how then
                    local ch = rollChoice[it.id]
                    how = (ch and (GetTime() - ch.t) < 180) and ch.how or "roll"
                end
                recentRoll[it.id] = GetTime()
                ns.CountRollWin(it)
                if how == "need" and ns.WatchNeed then ns.WatchNeed(it) end
                RecordLoot(it, how, false)
            else
                -- "You receive loot" kommer også lige efter en roll-sejr: vent lidt og tjek
                C_Timer.After(2, function()
                    local t = recentRoll[it.id]
                    if t and (GetTime() - t) < 20 then return end
                    RecordLoot(it, "drop", true)
                end)
            end
            return
        end
    end
end

-- =============================================================================
-- Instanser: wipes, bosser og clears
-- =============================================================================
local curInst = { name = nil, kind = nil, enteredAt = 0 }
local sessionWipes = 0
local bossSeen, clearSeen, wipeToastAt = {}, {}, {}
local wipeLatch = false
local lastCombat = 0

local function InstanceNow()
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then
        local name = GetInstanceInfo and GetInstanceInfo() or nil
        if not name or name == "" then name = GetZoneText() end
        return Clean(name):sub(1, 40), kind
    end
    return nil
end

local function SendRunSummary(inst)
    local e = db.me and RunEntry(db.me, inst)
    if e then Send(string.format("S;%s;%s;%d;%d;%d", db.me, inst, e.wipes or 0, e.clears or 0, e.last or 0)) end
end

local function SendBossCount(inst, boss)
    local e = db.me and RunEntry(db.me, inst)
    if e and e.boss[boss] then Send(string.format("B;%s;%s;%s;%d", db.me, inst, boss, e.boss[boss])) end
end

local function CanonBoss(inst, raw)
    local info = BossInfo(inst)
    local n = Norm(raw)
    if info and info.byNorm[n] then return info.byNorm[n] end
    return Clean(raw):sub(1, 40)
end

local function RecordBossKill(raw)
    if not db.me or not raw or raw == "" then return end
    local inst = InstanceNow()
    if not inst then return end
    local boss = CanonBoss(inst, raw)
    local key = inst .. "|" .. boss
    local now = GetTime()
    if bossSeen[key] and (now - bossSeen[key]) < 60 then return end   -- samme kill meldt to gange
    bossSeen[key] = now

    local e = RunEntry(db.me, inst, true)
    e.boss[boss] = (e.boss[boss] or 0) + 1
    e.last = time()

    local info = BossInfo(inst)
    local cleared = false
    if info and info.last[Norm(boss)] and not (clearSeen[inst] and (now - clearSeen[inst]) < 600) then
        clearSeen[inst] = now
        e.clears = (e.clears or 0) + 1
        cleared = true
    end
    SendBossCount(inst, boss)
    SendRunSummary(inst)

    PlayEventSound("bosskill", db.me)
    if cleared then
        ns.Toast({ kind = "boss", title = inst .. " klaret!", text = string.format("%s er død. Det er din %d. clear her.", boss, e.clears),
                   icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", friend = db.me })
    else
        ns.Toast({ kind = "boss", title = boss .. " er død", text = string.format("%s - %d. gang.", inst, e.boss[boss]),
                   icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", friend = db.me })
    end
    if db.settings.announce then
        Print(string.format("%s nedlagt i %s (%d. gang)%s", boss, inst, e.boss[boss], cleared and " - |cffffd100instance klaret!|r" or ""))
    end
    ns.AfterEvent()
    if ns.RefreshUI then ns.RefreshUI() end
end

local function CheckBossDeath(destName)
    if not destName or destName == "" then return end
    local inst = InstanceNow()
    local info = BossInfo(inst)
    if info and info.byNorm[Norm(destName)] then RecordBossKill(destName) end
end

-- Wipe: alle (tilkoblede) i gruppen er døde eller spøgelser
local function GroupDeadCount()
    local total, dead = 0, 0
    local function count(unit)
        local P = GAME.Plain
        if P(UnitExists(unit)) and (not UnitIsConnected or P(UnitIsConnected(unit)) ~= false) then
            total = total + 1
            if P(UnitIsDeadOrGhost(unit)) then dead = dead + 1 end
        end
    end
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do count("raid" .. i) end
    else
        count("player")
        for i = 1, 4 do count("party" .. i) end
    end
    return total, dead
end

local function ShowWipeToast(friend, inst, t)
    local last = wipeToastAt[inst]
    if last and math.abs(t - last) < 90 then return end   -- hele partyet melder det samme wipe
    wipeToastAt[inst] = t
    ns.Toast({
        kind = "wipe", title = "WIPE",
        text = string.format("Hvad FAaanden laver healer mand, kraftedme hele %s party er død i %s", friend, inst),
        icon = "Interface\\Icons\\Spell_Holy_Heal", sound = "wipe", friend = friend,
    })
end
ns.ShowWipeToast = ShowWipeToast

local function OnWipe()
    local inst = InstanceNow()
    if not inst or not db.me then return end
    local e = RunEntry(db.me, inst, true)
    e.wipes = (e.wipes or 0) + 1
    e.last = time()
    sessionWipes = sessionWipes + 1
    SendRunSummary(inst)
    local now = time()
    Send(string.format("W;%s;%s;%d", db.me, inst, now), true)
    ShowWipeToast(db.me, inst, now)
    if sessionWipes >= 3 then ns.Unlock("healer_gone") end
    ns.AfterEvent()
    if ns.RefreshUI then ns.RefreshUI() end
end

local function CheckWipe()
    local inst, kind = InstanceNow()
    if not inst or not db.me or not IsInGroup() then wipeLatch = false; return end
    local total, dead = GroupDeadCount()
    if total < 2 then return end
    local need = (kind == "raid" and total >= 10) and math.ceil(total * 0.9) or total
    if dead >= need then
        local recentFight = (UnitAffectingCombat and GAME.Plain(UnitAffectingCombat("player"))) or (GetTime() - lastCombat) < 90
        if not wipeLatch and recentFight then
            wipeLatch = true
            OnWipe()
        end
    elseif dead <= total * 0.5 then
        wipeLatch = false
    end
end

local function OnZoneChanged()
    local inst, kind = InstanceNow()
    if inst then
        if curInst.name ~= inst then
            curInst = { name = inst, kind = kind, enteredAt = time() }
            sessionWipes = 0
            wipeLatch = false
        end
    else
        curInst = { name = nil, kind = nil, enteredAt = 0 }
        wipeLatch = false
    end
end

local function OnEncounterEnd(_, name, _, _, success)
    if success == 1 then RecordBossKill(name) end
end

local function OnBossKillEvent(_, name)
    RecordBossKill(name)
end

-- v0.5: guld, professions, gear og reputation. Ligger i en blok, så hovedfilen holder sig
-- under Luas grænse på 200 lokale variabler. Det, der bruges udefra, ligger på ns.
do
    -- =============================================================================
    -- Guld over tid: db.goldHist[ven] = { { tid, kobber }, ... }
    -- =============================================================================
    local GOLD_KEEP = 300   -- så mange målinger gemmes pr. ven

    -- Tilføjer en måling. Returnerer true, hvis den var ny.
    local function AddGoldSample(friend, t, copper, demo)
        if not ROSTER_SET[friend] or not t or t <= 0 or not copper or copper < 0 then return false end
        local h = db.goldHist[friend]
        if not h then h = {}; db.goldHist[friend] = h end
        for _, smp in ipairs(h) do
            if smp[1] == t then return false end
        end
        h[#h + 1] = { t, copper, d = demo or nil }
        table.sort(h, function(a, b) return a[1] < b[1] end)
        while #h > GOLD_KEEP do table.remove(h, 1) end
        return true
    end

    -- Summen af guld på alle dine karakterer, med den aktuelle karakter opdateret
    local function MyTotalGold()
        if not db.me then return nil end
        UpdateChar(db.me, UnitName("player"), { gold = GetMoney() }, time())
        local total = 0
        for _, c in pairs((db.friends[db.me] and db.friends[db.me].chars) or {}) do
            if not c.demo then total = total + (c.gold or 0) end
        end
        return total
    end

    -- Måles når du logger ud (og første gang, så grafen ikke er tom)
    local function SampleMyGold()
        local total = MyTotalGold()
        if not total then return end
        local h = db.goldHist[db.me]
        local last = h and h[#h]
        if last and not last.d and last[2] == total and (time() - last[1]) < 6 * 3600 then return end
        AddGoldSample(db.me, time(), total)
    end

    -- Måles også mens du spiller: højst hvert 10. minut og kun når guldet har ændret sig.
    -- Den nye måling sendes med det samme, så grafen ikke venter på logout.
    local GOLD_EVERY = 600
    local function CheckGold()
        local total = MyTotalGold()
        if not total then return end
        local h = db.goldHist[db.me]
        local last = h and h[#h]
        if last and not last.d and (last[2] == total or (time() - last[1]) < GOLD_EVERY) then return end
        local t = time()
        if AddGoldSample(db.me, t, total) then
            Send(string.format("G;%s;%d:%d", db.me, t, total))
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end
    ns.CheckGold = CheckGold

    -- Sender dine seneste målinger, pakket ~10 pr. besked
    local function SendGoldHistory(max)
        local h = db.me and db.goldHist[db.me]
        if not h then return end
        local list = {}
        for i = #h, 1, -1 do
            if not h[i].d then list[#list + 1] = h[i] end
            if #list >= (max or 30) then break end
        end
        local parts = {}
        local function flush()
            if #parts > 0 then Send("G;" .. db.me .. ";" .. table.concat(parts, ",")) end
            parts = {}
        end
        for _, smp in ipairs(list) do
            parts[#parts + 1] = smp[1] .. ":" .. smp[2]
            if #parts >= 10 then flush() end
        end
        flush()
    end

    -- =============================================================================
    -- Professions: c.prof = "Alchemy=375/375,Herbalism=300/375"
    -- =============================================================================
    local PROFS = {
        { name = "Alchemy",        icon = "Trade_Alchemy" },
        { name = "Blacksmithing",  icon = "Trade_BlackSmithing" },
        { name = "Enchanting",     icon = "Trade_Engraving" },
        { name = "Engineering",    icon = "Trade_Engineering" },
        { name = "Jewelcrafting",  icon = "INV_Misc_Gem_01" },
        { name = "Leatherworking", icon = "Trade_LeatherWorking" },
        { name = "Tailoring",      icon = "Trade_Tailoring" },
        { name = "Herbalism",      icon = "Trade_Herbalism" },
        { name = "Mining",         icon = "Trade_Mining" },
        { name = "Skinning",       icon = "INV_Misc_Pelt_Wolf_01" },
        { name = "Cooking",        icon = "INV_Misc_Food_15" },
        { name = "First Aid",      icon = "Spell_Holy_SealOfSacrifice" },
        { name = "Fishing",        icon = "Trade_Fishing" },
    }
    local PROF_BY_NAME = {}
    for _, pr in ipairs(PROFS) do PROF_BY_NAME[pr.name] = pr end

    local function ScanProfessions()
        local parts = {}
        -- Forever (moderne motor) har ikke skill-listen, men GetProfessions()
        if not (GetNumSkillLines and GetSkillLineInfo) and GetProfessions and GetProfessionInfo then
            for _, idx in pairs({ GetProfessions() }) do
                local name, _, rank, maxRank = GetProfessionInfo(idx)
                if name and PROF_BY_NAME[name] and rank then
                    parts[#parts + 1] = string.format("%s=%d/%d", name, rank, maxRank or rank)
                end
            end
            table.sort(parts)
            return table.concat(parts, ",")
        end
        if not GetNumSkillLines or not GetSkillLineInfo then return nil end
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not isHeader and PROF_BY_NAME[name] and rank then
                parts[#parts + 1] = string.format("%s=%d/%d", name, rank, maxRank or rank)
            end
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end

    -- "Alchemy=375/375,..." -> { Alchemy = { 375, 375 }, ... }
    local function ParseProf(str)
        local res = {}
        for name, rank, max in tostring(str or ""):gmatch("([^,=]+)=(%d+)/(%d+)") do
            res[name] = { tonumber(rank), tonumber(max) }
        end
        return res
    end

    local function SendProf(char, c)
        if c and c.prof then Send(string.format("P;%s;%s;%s", db.me, char, c.prof)) end
    end

    local function UpdateMyProfessions()
        if not db.me then return end
        local str = ScanProfessions()
        if not str then return end
        local char = UnitName("player")
        local c = UpdateChar(db.me, char, nil, time())
        if c and c.prof ~= str then
            c.prof = str
            SendProf(char, c)
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end

    -- =============================================================================
    -- Gear: c.gear = { il = snit item level, me = "1,7" (slots uden enchant), mg = manglende gems, t }
    -- =============================================================================
    local SLOT_NAME = {
        [1] = "Hoved", [2] = "Hals", [3] = "Skuldre", [5] = "Bryst", [6] = "Bælte", [7] = "Ben", [8] = "Fødder",
        [9] = "Håndled", [10] = "Hænder", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket",
        [15] = "Kappe", [16] = "Våben", [17] = "Off-hand", [18] = "Ranged",
    }
    local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
    -- Slots der kan enchantes for alle (ringe kun for enchantere, så dem tæller vi ikke)
    local ENCHANT_SLOTS = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true,
                            [10] = true, [15] = true, [16] = true, [17] = true }
    local OFFHAND_ENCHANTABLE = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true }

    local function ItemLevel(link)
        local ok, il = pcall(function()
            if C_Item and C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(link) end
            if GetDetailedItemLevelInfo then return GetDetailedItemLevelInfo(link) end
        end)
        if ok and il and il > 0 then return il end
        local _, _, _, base = GAME.ItemInfo(link)
        return base
    end

    local function EquipLoc(link)
        local _, _, _, loc = GAME.ItemInfoInstant(link)
        if loc then return loc end
        return select(9, GAME.ItemInfo(link))
    end

    local function SocketCount(link)
        local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
        if not fn then return 0 end
        local ok, stats = pcall(fn, link)
        if not ok or type(stats) ~= "table" then return 0 end
        local n = 0
        for k, v in pairs(stats) do
            if type(k) == "string" and k:find("^EMPTY_SOCKET_") then n = n + (tonumber(v) or 0) end
        end
        return n
    end

    -- Returnerer gear-tabellen, eller nil hvis spillet ikke har item-info klar endnu
    local function ScanGear()
        if not GetInventoryItemLink then return nil end
        local sum, n, missE, missG = 0, 0, {}, 0
        for _, slot in ipairs(GEAR_SLOTS) do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local il = ItemLevel(link)
                if not il then return nil end
                sum, n = sum + il, n + 1
                local fields = {}
                for v in ((link:match("item:([%-%d:]*)") or "") .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = tonumber(v) or 0 end
                local enchant = fields[2] or 0
                if ENCHANT_SLOTS[slot] and enchant == 0 then
                    if slot ~= 17 or OFFHAND_ENCHANTABLE[EquipLoc(link) or ""] then missE[#missE + 1] = slot end
                end
                local gems = 0
                for i = 3, 6 do if (fields[i] or 0) > 0 then gems = gems + 1 end end
                missG = missG + math.max(0, SocketCount(link) - gems)
            end
        end
        if n == 0 then return nil end
        return { il = math.floor(sum / n * 10 + 0.5) / 10, me = table.concat(missE, ","), mg = missG, t = time() }
    end

    local function SendGear(char, c)
        local g = c and c.gear
        if g then
            Send(string.format("E;%s;%s;%d;%s;%d;%d", db.me, char, math.floor((g.il or 0) * 10 + 0.5), g.me or "", g.mg or 0, g.t or 0))
        end
    end

    local gearRetry = 0
    local function UpdateMyGear()
        if not db.me then return end
        local g = ScanGear()
        if not g then
            -- Item-info er ikke hentet endnu: prøv igen om lidt
            if gearRetry < 5 then
                gearRetry = gearRetry + 1
                C_Timer.After(5, UpdateMyGear)
            end
            return
        end
        gearRetry = 0
        local char = UnitName("player")
        local c = UpdateChar(db.me, char, nil, time())
        local old = c.gear
        c.gear = g
        if not old or old.il ~= g.il or old.me ~= g.me or old.mg ~= g.mg then
            SendGear(char, c)
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end

    -- =============================================================================
    -- Reputation: c.rep = { [fraktion] = "standing:fremskridt:max" }
    -- Vi gemmer kun Friendly og bedre, plus nøgle-fraktionerne.
    -- =============================================================================
    local KEY_FACTIONS = {
        { key = "hfp", label = "Hellfire", names = { "Honor Hold", "Thrallmar" }, item = "Flamewrought Key", what = "Hellfire Citadel heroic" },
        { key = "ce",  label = "Cenarion", names = { "Cenarion Expedition" }, item = "Reservoir Key", what = "Coilfang Reservoir heroic" },
        { key = "lc",  label = "Lower City", names = { "Lower City" }, item = "Auchenai Key", what = "Auchindoun heroic" },
        { key = "sha", label = "Sha'tar", names = { "The Sha'tar" }, item = "Warpforged Key", what = "Tempest Keep heroic" },
        { key = "kot", label = "Keepers", names = { "Keepers of Time" }, item = "Key of Time", what = "Caverns of Time heroic" },
    }
    -- Nøglerne til heroics findes kun i TBC
    if not GAME.isTBC then KEY_FACTIONS = {} end
    local KEY_FACTION_NAME = {}
    for _, k in ipairs(KEY_FACTIONS) do
        for _, n in ipairs(k.names) do KEY_FACTION_NAME[n] = true end
    end
    local KEY_STANDING = 7   -- Revered

    local function RepName(name)
        return (tostring(name or ""):gsub("[,;=:]", " "):sub(1, 40))
    end

    -- Forever har kun C_Reputation; her pakkes det om, så det svarer til den gamle GetFactionInfo
    local NumFactions, FactionInfo = GetNumFactions, GetFactionInfo
    local ExpandHeader, CollapseHeader = ExpandFactionHeader, CollapseFactionHeader
    if not (NumFactions and FactionInfo) and C_Reputation and C_Reputation.GetFactionDataByIndex then
        NumFactions = C_Reputation.GetNumFactions
        ExpandHeader, CollapseHeader = C_Reputation.ExpandFactionHeader, C_Reputation.CollapseFactionHeader
        FactionInfo = function(i)
            local d = C_Reputation.GetFactionDataByIndex(i)
            if not d then return nil end
            return d.name, nil, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold,
                d.currentStanding, nil, nil, d.isHeader, d.isCollapsed, d.isHeaderWithRep
        end
    end

    local scanningRep, repScannedAt = false, 0
    local function ScanReputation()
        if not NumFactions or not FactionInfo or scanningRep then return nil end
        scanningRep = true
        -- Fold lukkede overskrifter ud, så vi ser alt, og fold dem sammen igen bagefter
        local opened = {}
        if ExpandHeader then
            local i = 1
            while i <= NumFactions() and i < 400 do
                local name, _, _, _, _, _, _, _, isHeader, isCollapsed = FactionInfo(i)
                if isHeader and isCollapsed then
                    opened[name or ""] = true
                    ExpandHeader(i)
                end
                i = i + 1
            end
        end
        local res = {}
        for i = 1, NumFactions() do
            local name, _, standing, barMin, barMax, barValue, _, _, isHeader, _, hasRep = FactionInfo(i)
            if name and standing and (not isHeader or hasRep) and (standing >= 5 or KEY_FACTION_NAME[name]) then
                res[RepName(name)] = string.format("%d:%d:%d", standing, (barValue or 0) - (barMin or 0), (barMax or 0) - (barMin or 0))
            end
        end
        if CollapseHeader then
            for i = NumFactions(), 1, -1 do
                local name, _, _, _, _, _, _, _, isHeader, isCollapsed = FactionInfo(i)
                if isHeader and not isCollapsed and opened[name or ""] then CollapseHeader(i) end
            end
        end
        scanningRep = false
        repScannedAt = GetTime()
        return res
    end

    -- "7:1200:21000" -> 7, 1200, 21000
    local function ParseRep(v)
        local s, p, m = tostring(v or ""):match("^(%d+):(%-?%d+):(%d+)$")
        return tonumber(s) or 0, tonumber(p) or 0, tonumber(m) or 0
    end

    -- Sender fraktioner, pakket så hver besked holder sig under 250 tegn
    local function SendRep(char, entries)
        local head = string.format("F;%s;%s;", db.me, char)
        local parts, len = {}, #head
        local function flush()
            if #parts > 0 then Send(head .. table.concat(parts, ",")) end
            parts, len = {}, #head
        end
        local names = {}
        for name in pairs(entries) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local item = name .. "=" .. entries[name]
            if len + #item + 1 > 245 then flush() end
            parts[#parts + 1] = item
            len = len + #item + 1
        end
        flush()
    end

    local function UpdateMyRep()
        if not db.me then return end
        local res = ScanReputation()
        if not res then return end
        local char = UnitName("player")
        local c = UpdateChar(db.me, char, nil, time())
        c.rep = c.rep or {}
        local changed = {}
        for name, v in pairs(res) do
            if c.rep[name] ~= v then changed[name] = v end
        end
        c.rep = res
        if next(changed) then
            SendRep(char, changed)
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end

    -- Samler hyppige events (rep, skills, gear) til ét tjek lidt efter
    local scanPending = {}
    local function ScheduleScan(kind, delay)
        if scanPending[kind] then return end
        scanPending[kind] = true
        C_Timer.After(delay or 5, function()
            scanPending[kind] = nil
            if kind == "prof" then UpdateMyProfessions()
            elseif kind == "gear" then UpdateMyGear()
            elseif kind == "rep" then UpdateMyRep() end
        end)
    end
    -- At folde overskrifter ud og ind udløser selv UPDATE_FACTION, så dem lytter vi ikke på
    ns.IsScanningRep = function() return scanningRep or (GetTime() - repScannedAt) < 3 end

    ns.AddGoldSample = AddGoldSample
    ns.SampleMyGold = SampleMyGold
    ns.SendGoldHistory = SendGoldHistory
    ns.ScheduleScan = ScheduleScan
    ns.PROFS = PROFS
    ns.ParseProf = ParseProf
    ns.SendProf = SendProf
    ns.SLOT_NAME = SLOT_NAME
    ns.SendGear = SendGear
    ns.KEY_FACTIONS = KEY_FACTIONS
    ns.KEY_STANDING = KEY_STANDING
    ns.ParseRep = ParseRep
    ns.SendRep = SendRep
end

-- =============================================================================
-- Achievements (trofæer)
-- =============================================================================
local function IC(name) return "Interface\\Icons\\" .. name end

local ACH = {
    -- Døden
    { id = "first_death", name = "Første blod", desc = "Dø for første gang.", icon = IC("Spell_Shadow_AnimateDead"), pts = 5,
      test = function(S) return S.deaths >= 1 end },
    { id = "deaths10", name = "Fast gæst på kirkegården", desc = "Dø 10 gange.", icon = IC("INV_Misc_Bone_HumanSkull_01"), pts = 10,
      test = function(S) return S.deaths >= 10 end },
    { id = "deaths50", name = "Kirkegårdsgænger", desc = "Dø 50 gange.", icon = IC("INV_Misc_Bone_HumanSkull_01"), pts = 25,
      test = function(S) return S.deaths >= 50 end },
    { id = "deaths100", name = "Professionelt lig", desc = "Dø 100 gange. Respekt.", icon = IC("Ability_Rogue_FeignDeath"), pts = 50,
      test = function(S) return S.deaths >= 100 end },
    { id = "first_to_die", name = "Første til at dø", desc = "Vær den første i gruppen, der dør i en dungeon.", icon = IC("Spell_Shadow_AnimateDead"), pts = 10 },
    { id = "fall", name = "Tyngdekraften vinder", desc = "Dø af at falde ned fra en klippe.", icon = IC("Ability_Rogue_FeignDeath"), pts = 10 },
    { id = "lava", name = "Gulvet er lava", desc = "Dø i lava, ild eller slim.", icon = IC("Spell_Fire_Fire"), pts = 10 },
    { id = "drown", name = "Glemte at svømme", desc = "Drukn eller dø af udmattelse.", icon = IC("Spell_Frost_FrostBolt02"), pts = 10 },
    { id = "afk_pull", name = "AFK midt i en pull", desc = "Gå AFK, mens gruppen er i kamp, eller dø, mens du er AFK.", icon = IC("INV_Drink_05"), pts = 15 },
    { id = "nemesis", name = "Ærkefjenden", desc = "Bliv dræbt af den samme fjende 5 gange.", icon = IC("Spell_Magic_PolymorphChicken"), pts = 15,
      test = function(S) return S.nemesis >= 5 end },
    { id = "triple", name = "Hat-trick", desc = "Dø 3 gange på 10 minutter.", icon = IC("INV_Misc_PocketWatch_01"), pts = 10 },
    { id = "quick_exit", name = "Hurtig exit", desc = "Dø inden for et minut efter du er gået ind i en dungeon.", icon = IC("INV_Misc_PocketWatch_01"), pts = 10 },
    -- Gruppen
    { id = "wipe_first", name = "Første wipe", desc = "Vær med i dit første wipe.", icon = IC("Spell_Holy_Heal"), pts = 5,
      test = function(S) return S.wipes >= 1 end },
    { id = "wipe10", name = "Wipe-veteran", desc = "Vær med i 10 wipes.", icon = IC("Spell_Holy_Heal"), pts = 25,
      test = function(S) return S.wipes >= 10 end },
    { id = "healer_gone", name = "Healeren er ikke hjemme", desc = "Wipe 3 gange i samme dungeon-besøg.", icon = IC("Spell_Holy_Heal"), pts = 15 },
    { id = "boss_first", name = "Første boss", desc = "Dræb din første boss.", icon = IC("INV_Sword_27"), pts = 5,
      test = function(S) return S.kills >= 1 end },
    { id = "boss25", name = "Bossjæger", desc = "Dræb 25 bosser.", icon = IC("INV_Sword_27"), pts = 25,
      test = function(S) return S.kills >= 25 end },
    { id = "clear_first", name = "Instance klaret", desc = "Klar en hel instance.", icon = IC("INV_Misc_Head_Dragon_01"), pts = 10,
      test = function(S) return S.clears >= 1 end },
    { id = "clear10", name = "Dungeon-diva", desc = "Klar 10 instances.", icon = IC("INV_Misc_Head_Dragon_01"), pts = 25,
      test = function(S) return S.clears >= 10 end },
    -- Loot
    { id = "epic_first", name = "Lilla fingre", desc = "Vind dit første epic.", icon = IC("INV_Misc_Gem_Amethyst_02"), pts = 10,
      test = function(S) return S.epic >= 1 end },
    { id = "epic10", name = "Lootgoblin", desc = "Vind 10 epics.", icon = IC("INV_Misc_Gem_Amethyst_02"), pts = 25,
      test = function(S) return S.epic >= 10 end },
    { id = "legend", name = "Gylden dag", desc = "Vind et legendary item.", icon = IC("INV_Misc_Gem_Amethyst_02"), pts = 50,
      test = function(S) return S.legend >= 1 end },
    { id = "need5", name = "Need before greed", desc = "Vind 5 items med Need.", icon = IC("INV_Misc_Bag_08"), pts = 10,
      test = function(S) return S.need >= 5 end },
    -- Rejsen
    { id = "lvl60", name = MAX_LEVEL > 60 and "Klar til Outland" or "Max level", desc = "Nå level 60.",
      icon = IC("INV_Misc_Note_01"), pts = MAX_LEVEL > 60 and 10 or 25,
      test = function(S) return S.maxLevel >= 60 end },
    { id = "lvl70", name = "Max level", desc = "Nå level 70.", icon = IC("INV_Misc_Note_01"), pts = 25, minMax = 70,
      test = function(S) return S.maxLevel >= 70 end },
    { id = "alts5", name = "Alt-junkie", desc = "Spil med 5 forskellige karakterer.", icon = IC("INV_Misc_Bag_08"), pts = 15,
      test = function(S) return S.chars >= 5 end },
    { id = "gold1000", name = "Rigmanden", desc = "Eje 1000 guld på tværs af dine karakterer.", icon = IC("INV_Misc_Coin_01"), pts = 15,
      test = function(S) return S.gold >= 1000 * 10000 end },
    { id = "night", name = "Nattergalen", desc = "Log ind mellem klokken 02 og 05 om natten.", icon = IC("INV_Misc_PocketWatch_01"), pts = 10 },
}
-- Trofæer over max level (fx level 70 på Forever) giver ingen mening i denne spilversion
for i = #ACH, 1, -1 do
    if ACH[i].minMax and MAX_LEVEL < ACH[i].minMax then table.remove(ACH, i) end
end
local ACH_BY_ID = {}
for _, a in ipairs(ACH) do ACH_BY_ID[a.id] = a end

local function AchStats()
    local S = { deaths = 0, loot = 0, epic = 0, legend = 0, need = 0, wipes = 0, clears = 0, kills = 0,
                chars = 0, maxLevel = 0, gold = 0, nemesis = 0 }
    local me = db.me
    if not me then return S end
    local killers = {}
    for _, ev in ipairs(db.events) do
        if EventFriend(ev) == me and not IsLocalOnly(ev.id) then
            S.deaths = S.deaths + 1
            local k = ev.killer
            if k and k ~= "" and k ~= "Ukendt" and k ~= "Omgivelserne" then
                killers[k] = (killers[k] or 0) + 1
                if killers[k] > S.nemesis then S.nemesis = killers[k] end
            end
        end
    end
    for _, ev in ipairs(db.loot) do
        if LootFriend(ev) == me and not IsLocalOnly(ev.id) then
            S.loot = S.loot + 1
            if (ev.quality or 0) >= 4 then S.epic = S.epic + 1 end
            if (ev.quality or 0) >= 5 then S.legend = S.legend + 1 end
            if ev.how == "need" then S.need = S.need + 1 end
        end
    end
    S.wipes, S.clears, S.kills = RunTotals(me)
    for _, c in pairs((db.friends[me] and db.friends[me].chars) or {}) do
        if not c.demo then
            S.chars = S.chars + 1
            S.gold = S.gold + (c.gold or 0)
            if (c.level or 0) > S.maxLevel then S.maxLevel = c.level end
        end
    end
    return S
end

local function AchCount(friend)
    local n, pts = 0, 0
    for id in pairs(db.ach[friend] or {}) do
        local a = ACH_BY_ID[id]
        if a then n = n + 1; pts = pts + a.pts end
    end
    return n, pts
end

function ns.Unlock(id, silent)
    local a = ACH_BY_ID[id]
    if not a or not db or not db.me then return false end
    db.ach[db.me] = db.ach[db.me] or {}
    if db.ach[db.me][id] then return false end
    local t = time()
    db.ach[db.me][id] = t
    Send(string.format("A;%s;%s;%d", db.me, id, t), true)
    if not silent then
        if db.settings.announce then Print("Trofæ låst op: |cffffd100" .. a.name .. "|r - " .. a.desc) end
        ns.Toast({ kind = "achievement", head = "TROFÆ LÅST OP", title = a.name, text = a.desc, icon = a.icon,
                   pts = a.pts, sound = "achievement", friend = db.me, force = true })
    end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

function ns.CheckAchievements(silent)
    if not db or not db.me then return end
    local S = AchStats()
    for _, a in ipairs(ACH) do
        if a.test and a.test(S) then ns.Unlock(a.id, silent) end
    end
end

-- Samler mange ændringer til ét tjek
local achPending = false
function ns.AfterEvent()
    if achPending or not db or not db.me then return end
    achPending = true
    C_Timer.After(0.5, function()
        achPending = false
        ns.CheckAchievements(false)
    end)
end

-- Første gang: lås det op, du allerede har opnået, uden en byge af popups
function ns.InitAchievements()
    if not db or not db.me then return end
    if not db.achInit then
        ns.CheckAchievements(true)
        db.achInit = true
    else
        ns.CheckAchievements(false)
    end
    local h = tonumber(date("%H"))
    if h and h >= 2 and h < 5 then ns.Unlock("night") end
end

-- Situationsbestemte trofæer, når DU dør
function ns.OnMyDeath(ev)
    local me = db.me
    if not me then return end
    if ev.killer == "Omgivelserne" then
        local a = ev.ability
        if a == ENV_NAMES.Falling then
            ns.Unlock("fall")
        elseif a == ENV_NAMES.Lava or a == ENV_NAMES.Fire or a == ENV_NAMES.Slime then
            ns.Unlock("lava")
        elseif a == ENV_NAMES.Drowning or a == ENV_NAMES.Fatigue then
            ns.Unlock("drown")
        end
    end

    local inst, kind = InstanceNow()
    if inst and kind == "party" and IsInGroup() then
        local total, dead = GroupDeadCount()
        if total >= 2 and dead <= 1 then ns.Unlock("first_to_die") end
    end
    if inst and (curInst.enteredAt or 0) > 0 and (time() - curInst.enteredAt) <= 60 then ns.Unlock("quick_exit") end

    local recent, now = 0, time()
    for _, e in ipairs(db.events) do
        if EventFriend(e) == me and not IsLocalOnly(e.id) and (now - (e.time or 0)) <= 600 then recent = recent + 1 end
    end
    if recent >= 3 then ns.Unlock("triple") end
    if UnitIsAFK and UnitIsAFK("player") then ns.Unlock("afk_pull") end
end

-- Går AFK, mens gruppen kæmper
function ns.OnFlags(unit)
    if unit ~= "player" or not db or not db.me then return end
    if not (UnitIsAFK and UnitIsAFK("player")) then return end
    if not InstanceNow() or not IsInGroup() then return end
    local combat = false
    local function chk(u)
        if UnitExists(u) and UnitAffectingCombat and UnitAffectingCombat(u) then combat = true end
    end
    chk("player")
    for i = 1, 4 do chk("party" .. i) end
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do chk("raid" .. i) end
    end
    if combat then ns.Unlock("afk_pull") end
end

-- =============================================================================
-- Indkommende ekstra-beskeder (S, B, W, A, R, G, P, E, F) og toasts for venner
-- =============================================================================
local startedAt = GetTime()
local toastedAt = {}

function ns.OnFriendHeartbeat(friend, char, class, level, zone, wasOnline, prevLevel)
    local now = GetTime()
    if now - startedAt < 70 then          -- lige efter login lander alles livstegn på én gang
        toastedAt[friend] = now
        return
    end
    if not wasOnline then
        if not toastedAt[friend] or now - toastedAt[friend] > 600 then
            toastedAt[friend] = now
            ns.Toast({
                kind = "online", title = friend .. " er online",
                text = string.format("%s (level %s) - %s", char or "?", tostring(level or "?"), (zone and zone ~= "") and zone or "ukendt sted"),
                class = class, sound = "online", friend = friend,
            })
        end
    elseif prevLevel and level and level == prevLevel + 1
        and not (ns.LevelToasted and ns.LevelToasted(friend, char, level)) then
        ns.Toast({ kind = "levelup", title = friend .. " nåede level " .. level, text = char, class = class,
                   sound = "levelup", friend = friend })
    end
end

-- =============================================================================
-- Legacy points (kun WoW Forever): hver Legacy Challenge er et achievement, der giver
-- points i trait-valutaen 4225. Points tjenes på hele Battle.net-kontoen, så de hører til
-- vennen og ikke til en karakter.
-- =============================================================================
do
    local LEGACY_CURRENCY = 4225

    local function ScanLegacy()
        if not GAME.isForever or not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then
            return nil
        end
        local forAch = C_Traits and C_Traits.GetTraitCurrencyForAchievement
        local points, done, seen = 0, 0, {}
        if forAch then
            for _, cat in ipairs(GetCategoryList() or {}) do
                for i = 1, GetCategoryNumAchievements(cat, true) or 0 do
                    local id, _, _, completed = GetAchievementInfo(cat, i)
                    if id and completed and not seen[id] then
                        seen[id] = true
                        local p = tonumber(forAch(LEGACY_CURRENCY, id)) or 0
                        if p > 0 then
                            points = points + p
                            done = done + 1
                        end
                    end
                end
            end
        end
        -- Reserve: selve valutaen, hvis achievements ikke siger noget
        if points == 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(LEGACY_CURRENCY)
            if info then points = tonumber(info.totalEarned) or tonumber(info.quantity) or 0 end
        end
        return points, done
    end

    local function SendLegacy()
        local e = db.me and db.legacy[db.me]
        if e then Send(string.format("LP;%s;%d;%d;%d", db.me, e.p or 0, e.c or 0, e.t or 0)) end
    end
    ns.SendLegacy = SendLegacy

    function ns.UpdateMyLegacy()
        if not db.me then return end
        local ok, points, done = pcall(ScanLegacy)
        if not ok or not points then return end
        local e = db.legacy[db.me]
        if e and e.p == points and e.c == done then return end
        db.legacy[db.me] = { p = points, c = done, t = time() }
        SendLegacy()
        if ns.RefreshUI then ns.RefreshUI() end
    end

    function ns.OnLegacyMessage(t)
        local friend, points, done, at = t[2], tonumber(t[3]), tonumber(t[4]) or 0, tonumber(t[5]) or 0
        if not ROSTER_SET[friend] or friend == db.me or not points then return end
        local e = db.legacy[friend]
        if e and at < (e.t or 0) then return end
        if e and points > (e.p or 0) and db.settings.announce and (time() - at) < 300 then
            Print(string.format("%s har nu |cffffd100%d legacy points|r.", friend, points))
        end
        db.legacy[friend] = { p = points, c = done, t = at }
        if ns.RefreshUI then ns.RefreshUI() end
    end

    -- Teksten til kort og venneside, eller nil når den ikke skal vises (TBC, eller intet kendt)
    function ns.LegacyText(friend)
        if not GAME.isForever then return nil end
        local e = db.legacy[friend]
        if not e then return nil end
        return string.format("%d legacy points", e.p or 0), e
    end
end

-- =============================================================================
-- Honor: c.honor = { h = honor points nu, k = honorable kills i alt, t } pr. karakter
-- =============================================================================
do
    local P = GAME.Plain

    local function ScanHonor()
        local h
        if GetHonorCurrency then
            h = P(GetHonorCurrency())
        elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            -- Classic-honor og den moderne honor-valuta (Forever kører på den moderne motor)
            local CC = Constants and Constants.CurrencyConsts
            for _, id in ipairs({ CC and CC.CLASSIC_HONOR_CURRENCY_ID or 1901, CC and CC.HONOR_CURRENCY_ID or 1792 }) do
                local info = C_CurrencyInfo.GetCurrencyInfo(id)
                if info and info.name and info.name ~= "" then
                    h = P(info.quantity)
                    break
                end
            end
        end
        local k = GetPVPLifetimeStats and P((GetPVPLifetimeStats()))
        h, k = tonumber(h), tonumber(k)
        if not h and not k then return nil end
        return h or 0, k or 0
    end

    local function SendHonor(char, c)
        if c and c.honor then
            Send(string.format("HP;%s;%s;%d;%d;%d", db.me, char, c.honor.h or 0, c.honor.k or 0, c.honor.t or 0))
        end
    end
    ns.SendHonor = SendHonor

    local pending = false
    function ns.UpdateMyHonor()
        pending = false
        if not db.me then return end
        local ok, h, k = pcall(ScanHonor)
        if not ok or not h then return end
        local char = UnitName("player")
        local c = UpdateChar(db.me, char, nil, time())
        if not c or (c.honor and c.honor.h == h and c.honor.k == k) then return end
        c.honor = { h = h, k = k, t = time() }
        SendHonor(char, c)
        if ns.RefreshUI then ns.RefreshUI() end
    end

    -- Honor-events kommer i stimer under en BG, så vi venter lidt og måler én gang
    function ns.ScheduleHonor()
        if pending or not db or not db.me then return end
        pending = true
        C_Timer.After(5, ns.UpdateMyHonor)
    end

    function ns.OnHonorMessage(t)
        local friend, char, h, k, at = t[2], t[3], tonumber(t[4]), tonumber(t[5]) or 0, tonumber(t[6]) or 0
        if not ROSTER_SET[friend] or friend == db.me or not char or char == "" or not h then return end
        local c = UpdateChar(friend, char, nil, 1)
        if c and (not c.honor or at >= (c.honor.t or 0)) then
            c.honor = { h = h, k = k, t = at }
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end

    -- Samlet honor og honorable kills på tværs af vennens karakterer (nil hvis intet kendt)
    function ns.HonorTotals(friend)
        local info = db.friends[friend]
        local h, k, any = 0, 0, false
        for _, c in pairs((info and info.chars) or {}) do
            if c.honor and not c.demo then
                h, k, any = h + (c.honor.h or 0), k + (c.honor.k or 0), true
            end
        end
        if not any then return nil end
        return h, k
    end
end

-- Honor og (på Forever) legacy points. Kort form til vennekortet, hvor der er trangt.
function ns.CardExtraText(friend, short)
    local parts = {}
    local h = ns.HonorTotals(friend)
    if h then
        local n = (short and h >= 10000) and string.format("%dk", math.floor(h / 1000)) or tostring(h)
        parts[#parts + 1] = n .. " honor"
    end
    local legacy, le = ns.LegacyText(friend)
    if legacy then parts[#parts + 1] = short and ((le.p or 0) .. " LP") or legacy end
    if #parts == 0 then return nil end
    return table.concat(parts, short and "  " or "  -  ")
end

local function HandleExtraMessage(kind, t)
    if kind == "S" then
        local friend, inst = t[2], t[3]
        if ROSTER_SET[friend] and friend ~= db.me and inst and inst ~= "" then
            local e = RunEntry(friend, inst:sub(1, 40), true)
            e.demo = nil
            local w, c = tonumber(t[4]) or 0, tonumber(t[5]) or 0
            if w > (e.wipes or 0) then e.wipes = w end
            if c > (e.clears or 0) then e.clears = c end
            e.last = math.max(e.last or 0, tonumber(t[6]) or 0)
            if ns.RefreshUI then ns.RefreshUI() end
        end
    elseif kind == "B" then
        local friend, inst, boss, n = t[2], t[3], t[4], tonumber(t[5])
        if ROSTER_SET[friend] and friend ~= db.me and inst and inst ~= "" and boss and boss ~= "" and n and n > 0 then
            local e = RunEntry(friend, inst:sub(1, 40), true)
            e.demo = nil
            if n > (e.boss[boss:sub(1, 40)] or 0) then e.boss[boss:sub(1, 40)] = n end
            if ns.RefreshUI then ns.RefreshUI() end
        end
    elseif kind == "W" then
        local friend, inst, at = t[2], t[3], tonumber(t[4])
        if ROSTER_SET[friend] and inst and inst ~= "" and at and math.abs(time() - at) < 120 then
            ShowWipeToast(friend, inst:sub(1, 40), at)
        end
    elseif kind == "A" then
        local friend, id, at = t[2], t[3], tonumber(t[4]) or 0
        if ROSTER_SET[friend] and friend ~= db.me and ACH_BY_ID[id] then
            db.ach[friend] = db.ach[friend] or {}
            if not db.ach[friend][id] then
                db.ach[friend][id] = at > 0 and at or time()
                local a = ACH_BY_ID[id]
                if at > 0 and (time() - at) < 120 then
                    ns.Toast({ kind = "trophy", head = friend .. " låste et trofæ op", title = a.name, text = a.desc,
                               icon = a.icon, sound = "achievement", friend = friend })
                end
                if ns.RefreshUI then ns.RefreshUI() end
            end
        end

    elseif kind == "R" then
        -- Roll-tal: tallene vokser kun, så den største version vinder
        local friend, rolls = t[2], tonumber(t[3])
        if ROSTER_SET[friend] and friend ~= db.me and rolls then
            local r = ns.RollEntry(friend, true)
            if r.demo or rolls >= (r.rolls or 0) then
                r.rolls, r.wins = rolls, tonumber(t[4]) or 0
                r.sum, r.cnt = tonumber(t[5]) or 0, tonumber(t[6]) or 0
                local low, high = tonumber(t[7]) or 0, tonumber(t[8]) or 0
                r.low = low > 0 and low or nil
                r.high = high > 0 and high or nil
                r.demo = nil
                if ns.RefreshUI then ns.RefreshUI() end
            end
        end

    elseif kind == "G" then
        local friend = t[2]
        if ROSTER_SET[friend] and friend ~= db.me and t[3] then
            local h = db.goldHist[friend]
            if h then
                for i = #h, 1, -1 do if h[i].d then table.remove(h, i) end end
            end
            for ts, copper in t[3]:gmatch("(%d+):(%d+)") do
                ns.AddGoldSample(friend, tonumber(ts), tonumber(copper))
            end
            if ns.RefreshUI then ns.RefreshUI() end
        end

    elseif kind == "P" then
        local friend, char = t[2], t[3]
        if ROSTER_SET[friend] and friend ~= db.me and char and char ~= "" then
            local c = UpdateChar(friend, char, nil, 1)
            if c then c.prof = t[4] or "" end
            if ns.RefreshUI then ns.RefreshUI() end
        end

    elseif kind == "E" then
        local friend, char, il = t[2], t[3], tonumber(t[4])
        if ROSTER_SET[friend] and friend ~= db.me and char and char ~= "" and il then
            local c = UpdateChar(friend, char, nil, 1)
            local at = tonumber(t[7]) or 0
            if c and (not c.gear or at >= (c.gear.t or 0)) then
                c.gear = { il = il / 10, me = t[5] or "", mg = tonumber(t[6]) or 0, t = at }
            end
            if ns.RefreshUI then ns.RefreshUI() end
        end

    elseif kind == "F" then
        local friend, char = t[2], t[3]
        if ROSTER_SET[friend] and friend ~= db.me and char and char ~= "" and t[4] then
            local c = UpdateChar(friend, char, nil, 1)
            if c then
                c.rep = c.rep or {}
                for name, v in t[4]:gmatch("([^,=]+)=([%d:%-]+)") do c.rep[name] = v end
            end
            if ns.RefreshUI then ns.RefreshUI() end
        end
    end
end

-- Ved sync: send MINE instans-tal og trofæer
function ns.SendMyExtras()
    if not db.me then return end
    local n = 0
    for inst, e in pairs(db.runs[db.me] or {}) do
        if not e.demo then
            Send(string.format("S;%s;%s;%d;%d;%d", db.me, inst, e.wipes or 0, e.clears or 0, e.last or 0))
            n = n + 1
            for boss, cnt in pairs(e.boss or {}) do
                if n < 120 then
                    Send(string.format("B;%s;%s;%s;%d", db.me, inst, boss, cnt))
                    n = n + 1
                end
            end
            if n >= 120 then break end
        end
    end
    for id, at in pairs(db.ach[db.me] or {}) do
        if ACH_BY_ID[id] and not (db.demoAch[db.me] and db.demoAch[db.me][id]) then
            Send(string.format("A;%s;%s;%d", db.me, id, at))
        end
    end

    -- v0.5: rolls, guld, professions, gear og reputation
    ns.SendRollSummary()
    ns.SendGoldHistory(30)
    ns.SendLegacy()
    for char, c in pairs((db.friends[db.me] and db.friends[db.me].chars) or {}) do
        if not c.demo then
            ns.SendProf(char, c)
            ns.SendGear(char, c)
            ns.SendHonor(char, c)
            if c.rep and next(c.rep) then ns.SendRep(char, c.rep) end
        end
    end
    if ns.SendPrankExtras then ns.SendPrankExtras() end
end

ns.CheckBossDeath = CheckBossDeath

-- =============================================================================
-- Indkommende beskeder
-- =============================================================================
local lastSyncReply = {}

local function OnAddonMessage(prefix, message, chatType, sender)
    prefix, message, sender = GAME.Plain(prefix), GAME.Plain(message), GAME.Plain(sender)
    if prefix ~= PREFIX or type(message) ~= "string" then return end
    local t = { strsplit(";", message) }
    local kind = t[1]
    route.Note(t, chatType, sender)

    if kind == "D" then
        local ev = DeserializeDeath(t)
        if ev then AddDeath(ev) end   -- dubletter (inkl. vores egne) filtreres fra via id

    elseif kind == "L" then
        local ev = DeserializeLoot(t)
        if ev then AddLoot(ev) end

    elseif kind == "H" then
        local friend = t[2]
        if ROSTER_SET[friend] and friend ~= db.me then
            local char = t[3]
            local wasOnline = IsOnline(friend)
            local prev = db.friends[friend] and db.friends[friend].chars and db.friends[friend].chars[char]
            local prevLevel = prev and prev.level
            local level = tonumber(t[5])
            UpdateChar(friend, char, {
                class = t[4], level = level, gold = tonumber(t[6]), zone = t[7], xp = tonumber(t[8]),
            }, time())
            ns.OnFriendHeartbeat(friend, char, t[4], level, t[7], wasOnline, prevLevel)
            if ns.RefreshUI then ns.RefreshUI() end
        end

    elseif kind == "C" then
        -- En karakter (kan være offline): behold dens eget "sidst set"-tidspunkt
        local friend = t[2]
        if ROSTER_SET[friend] and friend ~= db.me then
            local seen = tonumber(t[8])
            UpdateChar(friend, t[3], {
                class = t[4], level = tonumber(t[5]), gold = tonumber(t[6]), zone = t[7], xp = tonumber(t[9]),
            }, (seen and seen > 0) and seen or 1)
            if ns.RefreshUI then ns.RefreshUI() end
        end

    elseif kind == "LP" then
        ns.OnLegacyMessage(t)

    elseif kind == "HP" then
        ns.OnHonorMessage(t)

    elseif kind == "S" or kind == "B" or kind == "W" or kind == "A"
        or kind == "R" or kind == "G" or kind == "P" or kind == "E" or kind == "F" then
        HandleExtraMessage(kind, t)

    elseif kind and kind:sub(1, 1) == "X" then
        -- v0.6: drillerier (XE emote-angreb, XN need-politi, XK seneste rolls)
        if ns.HandlePrankMessage then ns.HandlePrankMessage(kind, t) end

    elseif kind == "Q" then
        local friend = t[2]
        if db.me and ROSTER_SET[friend] and friend ~= db.me then
            local now = time()
            local wait = (t[3] == "1") and 30 or 600
            if not lastSyncReply[friend] or now - lastSyncReply[friend] > wait then
                lastSyncReply[friend] = now
                C_Timer.After(1 + math.random() * 6, RespondToSync)
            end
        end
    end
end

-- =============================================================================
-- Identitet: hvilken ven er du?
-- =============================================================================
-- Når vi ved, hvem du er: mål guld, professions, gear og rep, og send dine seneste guldtal
function ns.AfterIdentity()
    if not db.me then return end
    if not db.goldHist[db.me] or #db.goldHist[db.me] == 0 then ns.SampleMyGold() end
    ns.SendGoldHistory(10)
    ns.ScheduleScan("prof", 2)
    ns.ScheduleScan("gear", 4)
    ns.ScheduleScan("rep", 6)
    C_Timer.After(8, ns.UpdateMyLegacy)
    C_Timer.After(10, ns.UpdateMyHonor)
end

-- Knappen "Opdater": mål og send dine egne data, og bed vennerne sende deres med det samme
local lastRefreshNow = -100
function ns.RefreshNow()
    if not db.me then
        Print("Vælg først, hvem du er (|cffffd100/wc4ever jeg|r).")
        return
    end
    if GetTime() - lastRefreshNow < 15 then
        Print("Opdaterer allerede. Vent et øjeblik.")
        return
    end
    lastRefreshNow = GetTime()
    SendHeartbeat()
    ns.CheckGold()
    ns.ScheduleScan("prof", 1)
    ns.ScheduleScan("gear", 1)
    ns.ScheduleScan("rep", 1)
    RequestSync(true)
    Print("Henter friske data fra vennerne. Det tager op til et halvt minut.")
end

local function SetMe(friend)
    db.me = friend
    local cname = UnitName("player")
    -- Tidligere registreringer fra denne karakter hører nu til dig
    for _, ev in ipairs(db.events) do
        if not ev.friend and ev.name == cname then ev.friend = friend end
    end
    for _, ev in ipairs(db.loot) do
        if not ev.friend and ev.char == cname then ev.friend = friend end
    end
    -- Hvis du skifter identitet, skal karakteren ikke stå hos den gamle
    for name, info in pairs(db.friends) do
        if name ~= friend and info.chars then info.chars[cname] = nil end
    end
    SendHeartbeat()
    RequestSync()
    ns.InitAchievements()
    ns.AfterIdentity()
    Print("Du er nu registreret som |cffffd100" .. friend .. "|r.")
    if ns.RefreshUI then ns.RefreshUI() end
end

-- =============================================================================
-- UI: byggeklodser
-- =============================================================================
local FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"

local COL_BG     = { 0.06, 0.06, 0.08, 0.97 }
local COL_PANEL  = { 0.11, 0.11, 0.14, 1 }
local COL_BORDER = { 0.24, 0.24, 0.30, 1 }
local COL_GOLD   = { 0.95, 0.78, 0.25, 1 }
local COL_BTN    = { 0.14, 0.14, 0.18, 1 }
local COL_SELECT = { 0.20, 0.38, 0.62, 1 }
local COL_EPIC   = { 0.64, 0.21, 0.93, 1 }
local COL_MUTED  = { 0.6, 0.6, 0.66, 1 }

-- (i en blok for sig: Luas grænse på 200 lokale variabler)
local Gradient, BarFill, SafeIcon, AddShadow
local WHITE = "Interface\\Buttons\\WHITE8X8"
do
    local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

    -- Farveovergang, der virker med både den gamle (SetGradientAlpha) og nye (SetGradient + CreateColor) API.
    -- "VERTICAL": første farve er bunden, anden er toppen. "HORIZONTAL": venstre, så højre.
    function Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
        tex:SetTexture(WHITE)
        if tex.SetGradientAlpha then
            tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
        elseif CreateColor then
            tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
        else
            tex:SetColorTexture(r2, g2, b2, a2)
        end
    end

    -- Statusbar-tekstur (den med lidt glans) i en given farve
    function BarFill(tex, r, g, b, a)
        tex:SetTexture(BAR_TEX)
        tex:SetVertexColor(r, g, b, a or 1)
    end

    -- Ikoner fra spillets egne filer; findes en sti ikke i denne spilversion, bruges spørgsmålstegnet
    function SafeIcon(tex, path)
        if path and GetFileIDFromPath and not GetFileIDFromPath(path) then
            path = "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        tex:SetTexture(path)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Blød skygge under et vindue (et par lag sort, der bliver svagere udad)
    function AddShadow(f, size)
        if (f:GetFrameLevel() or 0) < 2 then f:SetFrameLevel(2) end
        local sh = CreateFrame("Frame", nil, f)
        sh:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
        for i = 1, (size or 6) do
            local t = sh:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(0, 0, 0, 0.09)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", -i, i - 2)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i, -i - 2)
        end
        f.shadow = sh
        return sh
    end
end

local function MakeBox(frameType, parent, bg, border, name)
    local f = CreateFrame(frameType, name, parent, "BackdropTemplate")
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    -- Svag glans foroven, så flader ikke ser helt flade ud
    f.sheen = f:CreateTexture(nil, "BORDER")
    f.sheen:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.sheen:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    Gradient(f.sheen, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, 0.05)
    if frameType == "Button" then
        -- Lys op, når musen er over (HIGHLIGHT-laget vises kun ved hover)
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        hl:SetColorTexture(1, 0.85, 0.45, 0.06)
        hl:SetBlendMode("ADD")
    end
    return f
end

local function Txt(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return fs
end

-- Tekstfelt placeret fra venstre kant af en række
local function Field(parent, x, w, justify, template)
    local fs = Txt(parent, template)
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetWidth(w)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function MakeButton(parent, w, h, label, onClick)
    local b = MakeBox("Button", parent, COL_BTN, COL_BORDER)
    b:SetSize(w, h)
    b.text = Txt(b, "GameFontHighlight")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1) end)
    -- Teksten trykkes lidt ned, mens man klikker
    b:SetScript("OnMouseDown", function(self)
        local pt, rel, rp, x, y = self.text:GetPoint(1)
        if not pt then return end
        self.textPt = { pt, rel, rp, x, y }
        self.text:SetPoint(pt, rel, rp, x + 1, y - 1)
    end)
    b:SetScript("OnMouseUp", function(self)
        local tp = self.textPt
        if tp then self.text:SetPoint(tp[1], tp[2], tp[3], tp[4], tp[5]) self.textPt = nil end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function SetClassIcon(tex, class)
    local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then
        tex:SetTexture(ICON_TEX)
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetColorTexture(0.16, 0.16, 0.2, 1)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function SetItemIcon(tex, ev)
    local id = LootItemID(ev)
    local path
    if id then
        local ok, res = pcall(function()
            if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
            if GetItemIcon then return GetItemIcon(id) end
        end)
        if ok then path = res end
    end
    if path then
        tex:SetTexture(path)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        local r, g, b = HexToRGB(QUALITY_HEX[ev.quality] or "ffffff")
        tex:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 1)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function AgoOrOnline(s)
    return s.online and "|cff40e060Online|r" or ("|cff888888" .. (s.seen and FormatAgo(s.seen) or "aldrig set") .. "|r")
end

-- =============================================================================
-- UI: side 1 - overblik (kort)
-- =============================================================================
local CARD_W, CARD_H, GAP = 174, 158, 12
local BAR_W = CARD_W - 20

local function BuildCard(parent, index, friend)
    local card = MakeBox("Button", parent, COL_PANEL, COL_BORDER)
    card:SetSize(CARD_W, CARD_H)
    local col = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (CARD_W + GAP), -row * (CARD_H + GAP))
    card.friend = friend

    card.bar = card:CreateTexture(nil, "ARTWORK")
    card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
    card.bar:SetHeight(3)

    -- Klassefarvet skær øverst på kortet (farven sættes i RefreshOverview)
    card.wash = card:CreateTexture(nil, "BORDER", nil, 1)
    card.wash:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -4)
    card.wash:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -4)
    card.wash:SetHeight(52)

    card.iconFrame = card:CreateTexture(nil, "ARTWORK", nil, -1)
    card.iconFrame:SetSize(44, 44)
    card.iconFrame:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -12)
    card.iconFrame:SetColorTexture(0, 0, 0, 1)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -14)

    card.name = Txt(card, "GameFontNormalLarge")
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -2)
    card.name:SetText(friend)

    card.char = Txt(card, "GameFontHighlightSmall")
    card.char:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.char:SetTextColor(0.7, 0.7, 0.76)

    card.hat = card:CreateTexture(nil, "OVERLAY")
    card.hat:SetSize(22, 22)
    card.hat:SetPoint("CENTER", card.icon, "TOPLEFT", 4, -2)
    card.hat:SetTexture(ns.HAT_ICON or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    card.hat:Hide()

    card.dot = card:CreateTexture(nil, "OVERLAY")
    card.dot:SetSize(9, 9)
    card.dot:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -12)

    card.info1 = Txt(card, "GameFontHighlightSmall")
    card.info1:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -62)
    card.info1:SetWidth(BAR_W)
    card.info1:SetWordWrap(false)

    card.info2 = Txt(card, "GameFontHighlightSmall")
    card.info2:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -75)
    card.info2:SetWidth(BAR_W)
    card.info2:SetWordWrap(false)
    card.info2:SetTextColor(0.6, 0.6, 0.66)

    card.divider = card:CreateTexture(nil, "ARTWORK")
    card.divider:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -89)
    card.divider:SetSize(BAR_W, 1)
    Gradient(card.divider, "HORIZONTAL", 1, 1, 1, 0.12, 1, 1, 1, 0)

    card.deaths = Txt(card, "GameFontNormal")
    card.deaths:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -96)

    card.lootText = Txt(card, "GameFontNormal")
    card.lootText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -96)
    card.lootText:SetJustifyH("RIGHT")

    card.barBG = card:CreateTexture(nil, "ARTWORK")
    BarFill(card.barBG, 0.22, 0.22, 0.27, 1)
    card.barBG:SetSize(BAR_W, 6)
    card.barBG:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -116)

    card.barFill = card:CreateTexture(nil, "OVERLAY")
    card.barFill:SetHeight(6)
    card.barFill:SetPoint("TOPLEFT", card.barBG, "TOPLEFT", 0, 0)

    card.charsText = Txt(card, "GameFontHighlightSmall")
    card.charsText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -128)
    card.charsText:SetTextColor(0.7, 0.7, 0.76)

    card.legacy = Txt(card, "GameFontHighlightSmall")
    card.legacy:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -128)
    card.legacy:SetJustifyH("RIGHT")
    card.legacy:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

    card.titles = Txt(card, "GameFontNormalSmall")
    card.titles:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -142)
    card.titles:SetWidth(BAR_W)
    card.titles:SetWordWrap(false)
    card.titles:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

    card:SetScript("OnClick", function(self) ns.SelectTarget(self.friend) end)
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.friend, 1, 1, 1)

        local chars = CharList(self.friend)
        if #chars == 0 then
            GameTooltip:AddLine("Ingen karakterer set endnu", 0.7, 0.7, 0.76)
        else
            GameTooltip:AddLine(Plural(#chars, "karakter", "karakterer"), 0.7, 0.7, 0.76)
            for i = 1, math.min(#chars, 8) do
                local c = chars[i]
                local r, g, b = ClassColor(c.class)
                GameTooltip:AddDoubleLine(c.name, c.level > 0 and ("Level " .. c.level) or "-", r, g, b, 0.8, 0.8, 0.8)
            end
            if #chars > 8 then GameTooltip:AddLine("... og " .. (#chars - 8) .. " flere", 0.5, 0.5, 0.56) end
        end

        local killer, n = TopKiller(self.friend)
        if killer then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Værste fjende: " .. killer .. " (" .. n .. "x)", 1, 0.5, 0.5)
        end
        local last = LatestLoot(self.friend)
        if last then
            GameTooltip:AddLine("Seneste loot: " .. LootLink(last), 1, 1, 1)
        end
        local snail = ns.SnailText and ns.SnailText(self.friend)
        if snail then GameTooltip:AddLine(snail, 0.9, 0.8, 0.4) end
        local honor, hk = ns.HonorTotals(self.friend)
        if honor then
            GameTooltip:AddLine(string.format("Honor: %d (%d honorable kills)", honor, hk), 0.85, 0.75, 0.45)
        end
        local legacy, le = ns.LegacyText(self.friend)
        if legacy then
            GameTooltip:AddLine(string.format("Legacy: %s (%s)", legacy, Plural(le.c or 0, "challenge", "challenges")),
                COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Klik for at se alle karakterer", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
        GameTooltip:Hide()
    end)
    return card
end

local function BuildOverview(page)
    ns.cards = {}
    for i, name in ipairs(ROSTER) do
        ns.cards[i] = BuildCard(page, i, name)
    end
    local y = -(2 * (CARD_H + GAP) + 4)
    ns.deathTicker = Txt(page, "GameFontHighlightSmall")
    ns.deathTicker:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    ns.deathTicker:SetWidth(360)
    -- Flere linjer: med SetWordWrap(false) viser spillet kun den første
    ns.deathTicker:SetHeight(58)
    ns.deathTicker:SetJustifyV("TOP")
    ns.deathTicker:SetSpacing(3)

    ns.lootTicker = Txt(page, "GameFontHighlightSmall")
    ns.lootTicker:SetPoint("TOPLEFT", page, "TOPLEFT", 372, y)
    ns.lootTicker:SetWidth(360)
    -- Flere linjer: med SetWordWrap(false) viser spillet kun den første
    ns.lootTicker:SetHeight(58)
    ns.lootTicker:SetJustifyV("TOP")
    ns.lootTicker:SetSpacing(3)
end

local function TitleText(list)
    if not list or #list == 0 then return "" end
    local shown = {}
    for i = 1, math.min(2, #list) do shown[i] = list[i] end
    local text = table.concat(shown, "  /  ")
    if #list > 2 then text = text .. "  +" .. (#list - 2) end
    return text
end

local function RefreshOverview()
    local list = BuildStats()
    local titles = ComputeTitles(list)
    local maxLoot = 0
    for _, s in ipairs(list) do if s.loot > maxLoot then maxLoot = s.loot end end

    for i, s in ipairs(list) do
        local card = ns.cards[i]
        local r, g, b = ClassColor(s.class)
        card.bar:SetColorTexture(r, g, b, 1)
        Gradient(card.wash, "VERTICAL", r, g, b, 0, r, g, b, s.online and 0.22 or 0.10)
        card.iconFrame:SetColorTexture(r * 0.5, g * 0.5, b * 0.5, 1)
        card.name:SetTextColor(r, g, b)
        card.name:SetText(s.name .. ((ns.snailHolder == s.name) and (" " .. ns.SNAIL_ICON) or ""))
        SetClassIcon(card.icon, s.class)
        card.char:SetText(s.char or "ukendt karakter")

        if s.online then card.dot:SetColorTexture(0.25, 0.9, 0.35, 1) else card.dot:SetColorTexture(0.35, 0.35, 0.4, 1) end

        if s.class then
            card.info1:SetText(string.format("Level %d  %s", s.level, ClassName(s.class)))
        else
            card.info1:SetText("Ikke set endnu")
        end
        if s.online then
            card.info2:SetText(s.zone or "")
        else
            card.info2:SetText("Offline - " .. FormatAgo(s.seen))
        end

        card.deaths:SetText("Døde: " .. s.deaths)
        card.lootText:SetText("|cffa335eeLoot: " .. s.loot .. "|r")
        if s.loot > 0 and maxLoot > 0 then
            BarFill(card.barFill, COL_EPIC[1], COL_EPIC[2], COL_EPIC[3], 1)
            card.barFill:SetWidth(math.max(1, BAR_W * (s.loot / maxLoot)))
            card.barFill:Show()
        else
            card.barFill:Hide()
        end
        card.charsText:SetText(s.chars > 0 and Plural(s.chars, "karakter", "karakterer") or "Ingen karakterer endnu")
        card.legacy:SetText(ns.CardExtraText(s.name, true) or "")
        card.titles:SetText(TitleText(titles[s.name]))
        card.hat:SetShown(titles[s.name] ~= nil and titles[s.name][1] == "Skammens hat")
    end

    -- Seneste dødsfald
    local lines = { "|cffffd100Seneste dødsfald|r" }
    local total = #db.events
    if total == 0 then
        lines[#lines + 1] = "Ingen er døde endnu. Det varer ikke ved."
    else
        local sorted = {}
        for _, ev in ipairs(db.events) do sorted[#sorted + 1] = ev end
        table.sort(sorted, function(a, b) return (a.time or 0) > (b.time or 0) end)
        for i = 1, math.min(2, #sorted) do
            local ev = sorted[i]
            local who = EventFriend(ev) or ev.name
            local what = ev.killer
            if ev.ability ~= "" then what = what .. " (" .. ev.ability .. ")" end
            lines[#lines + 1] = string.format("%s døde til %s - %s", ColorName(who, ev.class), what, FormatAgo(ev.time))
        end
    end
    ns.deathTicker:SetText(table.concat(lines, "\n"))

    -- Seneste loot
    local ll = { "|cffffd100Seneste loot|r" }
    if #db.loot == 0 then
        ll[#ll + 1] = "Ingen " .. (QUALITY_NAME[db.settings.minQuality or 3] or "rare"):lower() .. " loot endnu."
    else
        local sorted = {}
        for _, ev in ipairs(db.loot) do sorted[#sorted + 1] = ev end
        table.sort(sorted, function(a, b) return (a.time or 0) > (b.time or 0) end)
        for i = 1, math.min(2, #sorted) do
            local ev = sorted[i]
            local who = LootFriend(ev) or ev.char
            ll[#ll + 1] = string.format("%s: %s - %s", ColorName(who, ev.class), LootLink(ev), FormatAgo(ev.time))
        end
    end
    ns.lootTicker:SetText(table.concat(ll, "\n"))
end

-- =============================================================================
-- UI: side 2 - scoreboard
-- =============================================================================
local SCORE_COLS = {
    { label = "#",      w = 36 },
    { label = "Navn",   w = 160, sort = "name" },
    { label = "Level",  w = 60,  sort = "maxLevel" },
    { label = "Chars",  w = 60,  sort = "chars" },
    { label = "Døde",   w = 60,  sort = "deaths" },
    { label = "Loot",   w = 60,  sort = "loot" },
    { label = "Point",  w = 70,  sort = "points" },
    { label = "Guld",   w = 110, sort = "gold" },
    { label = "Status", w = 116 },
}

local function BuildScoreboard(page)
    local x = 0
    for _, col in ipairs(SCORE_COLS) do col.x = x; x = x + col.w end

    ns.headers = {}
    for i, col in ipairs(SCORE_COLS) do
        local h = MakeButton(page, col.w - 2, 26, col.label, function()
            if not col.sort then return end
            if ns.sortKey == col.sort then
                ns.sortDesc = not ns.sortDesc
            else
                ns.sortKey = col.sort
                ns.sortDesc = (col.sort ~= "name")
            end
            ns.RefreshUI()
        end)
        h:SetPoint("TOPLEFT", page, "TOPLEFT", col.x, 0)
        ns.headers[i] = h
    end

    ns.scoreRows = {}
    for i = 1, #ROSTER do
        local row = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        row:SetSize(732, 32)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(32 + (i - 1) * 36))

        local c = SCORE_COLS
        row.rank = Field(row, c[1].x, c[1].w - 6, "CENTER")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row, "LEFT", c[2].x + 6, 0)
        row.name = Field(row, c[2].x + 34, c[2].w - 40, "LEFT", "GameFontNormal")
        row.level = Field(row, c[3].x, c[3].w - 6, "CENTER")
        row.chars = Field(row, c[4].x, c[4].w - 6, "CENTER")
        row.deaths = Field(row, c[5].x, c[5].w - 6, "CENTER")
        row.loot = Field(row, c[6].x, c[6].w - 6, "CENTER")
        row.points = Field(row, c[7].x, c[7].w - 6, "CENTER")
        row.gold = Field(row, c[8].x, c[8].w - 6, "CENTER")
        row.status = Field(row, c[9].x + 6, c[9].w - 8, "LEFT")
        ns.scoreRows[i] = row
    end

    ns.scoreInfo = Txt(page, "GameFontHighlightSmall")
    ns.scoreInfo:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(32 + #ROSTER * 36 + 2))
    ns.scoreInfo:SetWidth(732)

    local note = Txt(page, "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", ns.scoreInfo, "BOTTOMLEFT", 0, -4)
    note:SetTextColor(0.5, 0.5, 0.56)
    note:SetText("Point = loot x 5 + højeste level - døde x 3.  Klik på en kolonne for at sortere.")
end

local function RefreshScoreboard()
    local list = BuildStats()
    local titles, holders = ComputeTitles(list)

    local key = ns.sortKey or "points"
    local desc = ns.sortDesc
    if desc == nil then desc = true end
    table.sort(list, function(a, b)
        local va, vb = a[key], b[key]
        if va == vb then return a.name < b.name end
        if desc then return va > vb end
        return va < vb
    end)

    for i, col in ipairs(SCORE_COLS) do
        local arrow = ""
        if col.sort and col.sort == key then arrow = desc and " v" or " ^" end
        ns.headers[i].text:SetText(col.label .. arrow)
    end

    local maxDeaths = 0
    for _, s in ipairs(list) do if s.deaths > maxDeaths then maxDeaths = s.deaths end end

    for i, s in ipairs(list) do
        local row = ns.scoreRows[i]
        local r, g, b = ClassColor(s.class)
        row.rank:SetText(tostring(i))
        SetClassIcon(row.icon, s.class)
        row.name:SetText(s.name .. (s.isMe and "  (dig)" or ""))
        row.name:SetTextColor(r, g, b)
        row.level:SetText(s.maxLevel > 0 and tostring(s.maxLevel) or "-")
        row.chars:SetText(s.chars > 0 and tostring(s.chars) or "-")

        row.deaths:SetText(tostring(s.deaths))
        if s.deaths > 0 and s.deaths == maxDeaths then
            row.deaths:SetTextColor(1, 0.35, 0.35)
        else
            row.deaths:SetTextColor(1, 1, 1)
        end

        row.loot:SetText(tostring(s.loot))
        if s.loot > 0 then row.loot:SetTextColor(0.75, 0.4, 1) else row.loot:SetTextColor(0.6, 0.6, 0.66) end

        row.points:SetText(tostring(s.points))
        row.gold:SetText(s.gold > 0 and FormatGold(s.gold) or "-")
        row.status:SetText(AgoOrOnline(s))

        -- Highlight: førstepladsen får guld-kant, dig selv får blå baggrund
        if i == 1 then
            row:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        else
            row:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
        end
        if s.isMe then
            row:SetBackdropColor(0.13, 0.17, 0.26, 1)
        else
            row:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
        end
    end

    local parts = {}
    for _, title in ipairs(TITLE_ORDER) do
        if holders[title] then
            parts[#parts + 1] = "|cffffd100" .. title .. ":|r " .. holders[title]
        end
    end
    ns.scoreInfo:SetText(#parts > 0 and table.concat(parts, "     ") or "Ingen titler endnu - dø lidt og vind noget loot.")
end

-- =============================================================================
-- UI: side 3 - karakterer
-- =============================================================================
local CHAR_ROWS = 9

local function BuildCharsPage(page)
    ns.charList = {}
    for i, name in ipairs(ROSTER) do
        local b = MakeButton(page, 170, 34, name, function() ns.PickFriend(name) end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(i - 1) * 38)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
        b.text:SetJustifyH("LEFT")
        b.score = Txt(b, "GameFontNormal")
        b.score:SetPoint("RIGHT", b, "RIGHT", -10, 0)
        b.score:SetJustifyH("RIGHT")
        b.score:SetTextColor(0.7, 0.7, 0.76)
        ns.charList[i] = b
    end

    local panel = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", 182, 0)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        ns.charOffset = (ns.charOffset or 0) - delta
        ns.RefreshUI()
    end)
    ns.charPanel = panel

    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(44, 44)
    panel.icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)

    panel.name = Txt(panel, "GameFontNormalLarge")
    panel.name:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 10, -2)

    panel.sub = Txt(panel, "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -4)
    panel.sub:SetTextColor(0.7, 0.7, 0.76)

    panel.big = Txt(panel, "GameFontNormal")
    panel.big:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
    panel.big:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -10)
    panel.big:SetJustifyH("RIGHT")

    panel.bigLabel = Txt(panel, "GameFontHighlightSmall")
    panel.bigLabel:SetPoint("TOPRIGHT", panel.big, "BOTTOMRIGHT", 0, -2)
    panel.bigLabel:SetJustifyH("RIGHT")
    panel.bigLabel:SetTextColor(0.6, 0.6, 0.66)
    panel.bigLabel:SetText("karakterer")

    -- Kolonneoverskrifter
    local heads = { { "Karakter", 44, 136, "LEFT" }, { "Lvl", 184, 40, "CENTER" }, { "Døde", 228, 46, "CENTER" },
                    { "Loot", 278, 46, "CENTER" }, { "Sidst set", 330, 200, "LEFT" } }
    for _, h in ipairs(heads) do
        local fs = Txt(panel, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", h[2], -80)
        fs:SetWidth(h[3])
        fs:SetJustifyH(h[4])
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(h[1])
    end

    ns.charRows = {}
    for i = 1, CHAR_ROWS do
        local row = MakeBox("Button", panel, COL_BTN, COL_BORDER)
        row:SetSize(526, 28)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(96 + (i - 1) * 30))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name = Field(row, 32, 136, "LEFT", "GameFontNormal")
        row.level = Field(row, 172, 40, "CENTER")
        row.deaths = Field(row, 216, 46, "CENTER")
        row.loot = Field(row, 266, 46, "CENTER")
        row.seen = Field(row, 318, 204, "LEFT")
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local r, g, b = ClassColor(d.class)
            GameTooltip:AddLine(d.name, r, g, b)
            GameTooltip:AddLine(string.format("Level %d %s", d.level, ClassName(d.class)), 0.8, 0.8, 0.8)
            if d.zone then GameTooltip:AddLine(d.zone, 0.6, 0.6, 0.66) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Guld", d.gold > 0 and FormatGold(d.gold) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Dødsfald", tostring(d.deaths), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Rare+ loot", tostring(d.loot), 0.8, 0.8, 0.8, 0.75, 0.4, 1)
            GameTooltip:AddDoubleLine("Sidst set", d.online and "Online nu" or FormatAgo(d.seen), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ns.charRows[i] = row
    end

    panel.empty = Txt(panel, "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -110)
    panel.empty:SetWidth(500)
    panel.empty:SetTextColor(0.6, 0.6, 0.66)

    panel.legend = Txt(panel, "GameFontHighlightSmall")
    panel.legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
    panel.legend:SetTextColor(0.5, 0.5, 0.56)

    panel.lootBtn = MakeButton(panel, 110, 22, "Se loot >", function()
        ns.lootFriend = ns.target
        ns.lootOffset = 0
        ns.ShowTab(4)
    end)
    panel.lootBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 8)
end

local function RefreshChars()
    if not ns.target then ns.target = ROSTER[1] end
    local list = BuildStats()
    local cur
    for i, s in ipairs(list) do
        local btn = ns.charList[i]
        local r, g, b = ClassColor(s.class)
        btn.text:SetText(s.name .. (s.isMe and "  (dig)" or ""))
        btn.text:SetTextColor(r, g, b)
        btn.score:SetText(s.chars > 0 and tostring(s.chars) or "-")
        if s.name == ns.target then
            btn:SetBackdropColor(COL_SELECT[1], COL_SELECT[2], COL_SELECT[3], 1)
            cur = s
        else
            btn:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end
    if not cur then return end

    local panel = ns.charPanel
    local r, g, b = ClassColor(cur.class)
    SetClassIcon(panel.icon, cur.class)
    panel.name:SetText(cur.name)
    panel.name:SetTextColor(r, g, b)
    local extra = ns.CardExtraText(cur.name)
    panel.sub:SetText(string.format("%s  -  %d dødsfald  -  %d rare+ loot%s",
        Plural(cur.chars, "karakter", "karakterer"), cur.deaths, cur.loot, extra and ("  -  " .. extra) or ""))
    panel.big:SetText(tostring(cur.chars))
    panel.big:SetTextColor(1, 1, 1)

    local chars = CharList(cur.name)
    local total = #chars
    local maxOffset = math.max(0, total - CHAR_ROWS)
    local offset = math.max(0, math.min(ns.charOffset or 0, maxOffset))
    ns.charOffset = offset

    for i, row in ipairs(ns.charRows) do
        local d = chars[offset + i]
        row.data = d
        if d then
            local cr, cg, cb = ClassColor(d.class)
            SetClassIcon(row.icon, d.class)
            row.name:SetText(d.name)
            row.name:SetTextColor(cr, cg, cb)
            row.level:SetText(d.level > 0 and tostring(d.level) or "-")
            row.deaths:SetText(tostring(d.deaths))
            row.deaths:SetTextColor(d.deaths > 0 and 1 or 0.6, d.deaths > 0 and 0.5 or 0.6, d.deaths > 0 and 0.5 or 0.66)
            row.loot:SetText(tostring(d.loot))
            if d.loot > 0 then row.loot:SetTextColor(0.75, 0.4, 1) else row.loot:SetTextColor(0.6, 0.6, 0.66) end
            local where = d.zone and (" - " .. d.zone) or ""
            if d.online then
                row.seen:SetText("|cff40e060Online|r" .. where)
            else
                row.seen:SetText("|cff888888" .. FormatAgo(d.seen) .. where .. "|r")
            end
            row:Show()
        else
            row:Hide()
        end
    end

    if total == 0 then
        panel.empty:SetText(cur.name .. " er ikke set endnu. Karakterer dukker op, når " .. cur.name ..
            " logger ind med addonet, og du er i samme guild eller gruppe.")
        panel.legend:SetText("")
    else
        panel.empty:SetText("")
        if total > CHAR_ROWS then
            panel.legend:SetText(string.format("Viser %d-%d af %d  -  rul med musehjulet", offset + 1,
                math.min(offset + CHAR_ROWS, total), total))
        else
            panel.legend:SetText("Alle karakterer " .. cur.name .. " har været logget ind med")
        end
    end
end

-- =============================================================================
-- UI: side 4 - loot
-- =============================================================================
local LOOT_ROWS = 12
local LC = { icon = 4, item = 26, winner = 252, how = 394, ctx = 466, zone = 530, time = 672 }

local function FilteredLoot()
    local res = {}
    for _, ev in ipairs(db.loot) do
        if (ns.lootCtx == "all" or ev.ctx == ns.lootCtx)
            and (not ns.lootFriend or LootFriend(ev) == ns.lootFriend) then
            res[#res + 1] = ev
        end
    end
    table.sort(res, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
        return a.id > b.id
    end)
    return res
end

local function BuildLootPage(page)
    ns.lootCtx = "all"
    ns.lootFriend = nil
    ns.lootOffset = 0

    ns.ctxButtons = {}
    for i, c in ipairs(LOOT_CONTEXTS) do
        local btn = MakeButton(page, 90, 26, c.label, function()
            ns.lootCtx = c.key
            ns.lootOffset = 0
            ns.RefreshUI()
        end)
        btn:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 94, 0)
        ns.ctxButtons[i] = btn
    end

    ns.friendFilter = MakeButton(page, 180, 26, "Ven: Alle", function()
        local idx = 0
        for i, n in ipairs(ROSTER) do if n == ns.lootFriend then idx = i end end
        ns.lootFriend = ROSTER[idx + 1]   -- efter sidste ven kommer "Alle" (nil)
        ns.lootOffset = 0
        ns.RefreshUI()
    end)
    ns.friendFilter:SetPoint("TOPLEFT", page, "TOPLEFT", 480, 0)

    local prev = MakeButton(page, 30, 26, "<", function()
        ns.lootOffset = (ns.lootOffset or 0) - LOOT_ROWS
        ns.RefreshUI()
    end)
    prev:SetPoint("TOPLEFT", page, "TOPLEFT", 668, 0)
    local nxt = MakeButton(page, 30, 26, ">", function()
        ns.lootOffset = (ns.lootOffset or 0) + LOOT_ROWS
        ns.RefreshUI()
    end)
    nxt:SetPoint("TOPLEFT", page, "TOPLEFT", 702, 0)

    local heads = { { "Item", LC.item, 220 }, { "Vinder", LC.winner, 140 }, { "Hvordan", LC.how, 70 },
                    { "Type", LC.ctx, 62 }, { "Hvor", LC.zone, 140 }, { "Tid", LC.time, 56 } }
    for _, h in ipairs(heads) do
        local fs = Txt(page, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", h[2], -34)
        fs:SetWidth(h[3])
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(h[1])
    end

    ns.lootRows = {}
    for i = 1, LOOT_ROWS do
        local row = MakeBox("Button", page, COL_PANEL, COL_BORDER)
        row:SetSize(732, 24)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(52 + (i - 1) * 26))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", LC.icon, 0)
        row.item = Field(row, LC.item, 222)
        row.winner = Field(row, LC.winner, 140)
        row.how = Field(row, LC.how, 70)
        row.ctx = Field(row, LC.ctx, 62)
        row.zone = Field(row, LC.zone, 138)
        row.time = Field(row, LC.time, 56)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local ev = self.ev
            if not ev then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ev.item)
            if not ok then GameTooltip:AddLine(ev.name, HexToRGB(QUALITY_HEX[ev.quality] or "ffffff")) end
            GameTooltip:AddLine(" ")
            local f = LootFriend(ev)
            local r, g, b = ClassColor(ev.class)
            GameTooltip:AddDoubleLine("Vundet af", (f and (f .. " (" .. ev.char .. ")")) or ev.char, 0.8, 0.8, 0.8, r, g, b)
            GameTooltip:AddDoubleLine("Hvordan", HOW_LABEL[ev.how] or ev.how, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Hvor", (CTX_LABEL[ev.ctx] or "") .. " - " .. ev.zone, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Hvornår", FormatAgo(ev.time) .. "  (" .. date("%d/%m %H:%M", ev.time) .. ")", 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddLine("Shift-klik for at sende linket i chatten", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if self.ev and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                ChatEdit_InsertLink(LootLink(self.ev))
            end
        end)
        ns.lootRows[i] = row
    end

    ns.lootInfo = Txt(page, "GameFontHighlightSmall")
    ns.lootInfo:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(52 + LOOT_ROWS * 26 + 4))
    ns.lootInfo:SetWidth(732)
    ns.lootInfo:SetTextColor(0.5, 0.5, 0.56)

    ns.lootEmpty = Txt(page, "GameFontHighlight")
    ns.lootEmpty:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -64)
    ns.lootEmpty:SetWidth(700)
    ns.lootEmpty:SetTextColor(0.6, 0.6, 0.66)

    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        ns.lootOffset = (ns.lootOffset or 0) - delta * 3
        ns.RefreshUI()
    end)
end

local function RefreshLoot()
    for i, c in ipairs(LOOT_CONTEXTS) do
        local btn = ns.ctxButtons[i]
        local sel = (c.key == ns.lootCtx)
        local col = sel and COL_SELECT or COL_BTN
        btn:SetBackdropColor(col[1], col[2], col[3], 1)
    end
    ns.friendFilter.text:SetText("Ven: " .. (ns.lootFriend or "Alle"))

    local list = FilteredLoot()
    local total = #list
    local maxOffset = math.max(0, total - LOOT_ROWS)
    local offset = math.max(0, math.min(ns.lootOffset or 0, maxOffset))
    ns.lootOffset = offset

    for i, row in ipairs(ns.lootRows) do
        local ev = list[offset + i]
        row.ev = ev
        if ev then
            SetItemIcon(row.icon, ev)
            row.item:SetText(string.format("|cff%s%s|r", QUALITY_HEX[ev.quality] or "ffffff", ev.name))
            local f = LootFriend(ev)
            local who = ColorName(f or ev.char, ev.class)
            if f and ev.char ~= f then who = who .. " |cff888888" .. ev.char .. "|r" end
            row.winner:SetText(who)
            row.how:SetText(HOW_LABEL[ev.how] or ev.how)
            row.ctx:SetText(string.format("|cff%s%s|r", CTX_COLOR[ev.ctx] or "ffffff", CTX_LABEL[ev.ctx] or ev.ctx))
            row.zone:SetText(ev.zone)
            row.time:SetText(FormatAgoShort(ev.time))
            row:Show()
        else
            row:Hide()
        end
    end

    local minName = QUALITY_NAME[db.settings.minQuality or 3] or "Rare"
    if total == 0 then
        if #db.loot == 0 then
            ns.lootEmpty:SetText("Ingen loot endnu. Vind noget " .. minName:lower() .. " eller bedre, så dukker det op her.")
        else
            ns.lootEmpty:SetText("Intet loot matcher filteret.")
        end
        ns.lootInfo:SetText(minName .. " eller bedre registreres  -  /wc4ever loot uncommon|rare|epic|legendary ændrer grænsen")
    else
        ns.lootEmpty:SetText("")
        ns.lootInfo:SetText(string.format("Viser %d-%d af %d  -  %s eller bedre  -  rul med musehjulet  -  /wc4ever loot uncommon|rare|epic|legendary",
            offset + 1, math.min(offset + LOOT_ROWS, total), total, minName))
    end
end

-- =============================================================================
-- Toasts (små popups øverst på skærmen) og trofæ-popup
-- =============================================================================
local TOAST_STYLE = {
    online      = { border = { 0.25, 0.88, 0.38 }, bg = { 0.06, 0.09, 0.07 } },
    levelup     = { border = { 0.40, 0.70, 1.00 }, bg = { 0.06, 0.08, 0.11 } },
    wipe        = { border = { 0.95, 0.25, 0.25 }, bg = { 0.12, 0.05, 0.05 } },
    boss        = { border = { 0.95, 0.55, 0.15 }, bg = { 0.11, 0.08, 0.05 } },
    trophy      = { border = { 0.95, 0.78, 0.25 }, bg = { 0.10, 0.08, 0.04 } },
    achievement = { border = { 1.00, 0.82, 0.20 }, bg = { 0.14, 0.10, 0.04 } },
    info        = { border = { 0.60, 0.60, 0.66 }, bg = { 0.07, 0.07, 0.09 } },
    obit        = { border = { 0.55, 0.55, 0.60 }, bg = { 0.02, 0.02, 0.03 } },
    police      = { border = { 0.25, 0.45, 1.00 }, bg = { 0.04, 0.05, 0.12 } },
    emote       = { border = { 1.00, 0.45, 0.75 }, bg = { 0.10, 0.04, 0.08 } },
}

local toast = { queue = {}, frame = nil, active = nil }

local function ToastFrame()
    if toast.frame then return toast.frame end
    local f = MakeBox("Button", UIParent, COL_BG, COL_GOLD, "WastedCoastToast")
    f:SetSize(430, 72)
    f:SetPoint("TOP", UIParent, "TOP", 0, -130)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()
    AddShadow(f, 6)

    -- Farvet stribe i venstre side og et skær, der toner ud mod højre (farven følger toast-typen)
    f.stripe = f:CreateTexture(nil, "ARTWORK")
    f.stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.stripe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    f.stripe:SetWidth(3)
    f.wash = f:CreateTexture(nil, "BORDER", nil, 1)
    f.wash:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -1)
    f.wash:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 1)
    f.wash:SetWidth(220)

    f.iconFrame = f:CreateTexture(nil, "ARTWORK", nil, -1)
    f.iconFrame:SetSize(52, 52)
    f.iconFrame:SetPoint("LEFT", f, "LEFT", 12, 0)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(48, 48)
    f.icon:SetPoint("CENTER", f.iconFrame, "CENTER", 0, 0)

    f.head = Txt(f, "GameFontNormalSmall")
    f.head:SetTextColor(1, 0.82, 0.2)
    f.title = Txt(f, "GameFontNormal")
    f.title:SetWidth(300)
    f.title:SetWordWrap(false)
    f.text = Txt(f, "GameFontHighlightSmall")
    f.text:SetWidth(300)
    f.text:SetWordWrap(true)
    f.text:SetTextColor(0.8, 0.8, 0.84)

    f.pts = Txt(f, "GameFontNormalLarge")
    f.pts:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.pts:SetTextColor(1, 0.82, 0.2)

    f:SetScript("OnClick", function(self) self.t = math.max(self.t or 0, self.dur or 0) end)
    f:SetScript("OnUpdate", function(self, dt)
        if not toast.active then return end
        self.t = (self.t or 0) + dt
        local dur = self.dur or 5
        if self.t < 0.3 then
            local k = self.t / 0.3
            self:SetAlpha(k)
            -- Glider lidt ned på plads
            self:SetPoint("TOP", UIParent, "TOP", 0, -130 + 14 * (1 - k) * (1 - k))
        elseif self.t < dur then
            self:SetAlpha(1)
        elseif self.t < dur + 0.6 then
            self:SetAlpha(1 - (self.t - dur) / 0.6)
        else
            toast.active = nil
            self:Hide()
            ns.ToastNext()
        end
    end)
    toast.frame = f
    return f
end

function ns.ToastNext()
    if toast.active then return end
    local opts = table.remove(toast.queue, 1)
    if not opts then return end
    local f = ToastFrame()
    local st = TOAST_STYLE[opts.kind] or TOAST_STYLE.info

    f:SetBackdropColor(st.bg[1], st.bg[2], st.bg[3], 0.97)
    f:SetBackdropBorderColor(st.border[1], st.border[2], st.border[3], 1)
    local br, bgc, bb = st.border[1], st.border[2], st.border[3]
    f.stripe:SetColorTexture(br, bgc, bb, 1)
    Gradient(f.wash, "HORIZONTAL", br, bgc, bb, 0.16, br, bgc, bb, 0)
    f.iconFrame:SetColorTexture(br * 0.6, bgc * 0.6, bb * 0.6, 1)

    if opts.icon then
        f.icon:SetTexture(opts.icon)
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
        SetClassIcon(f.icon, opts.class)
    end

    f.head:ClearAllPoints()
    f.title:ClearAllPoints()
    f.text:ClearAllPoints()
    if opts.head then
        f.head:SetText(opts.head)
        f.head:Show()
        f.head:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 2)
        f.title:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -2)
    else
        f.head:Hide()
        f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -2)
    end
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)

    f.title:SetText(opts.title or "")
    if opts.kind == "wipe" then
        f.title:SetTextColor(1, 0.35, 0.35)
    elseif opts.kind == "achievement" then
        f.title:SetTextColor(1, 1, 1)
    else
        local r, g, b = ClassColor(opts.class)
        if opts.class then f.title:SetTextColor(r, g, b) else f.title:SetTextColor(1, 0.82, 0.2) end
    end
    f.text:SetText(opts.text or "")
    f.pts:SetText(opts.pts and tostring(opts.pts) or "")

    toast.active = opts
    f.t = 0
    f.dur = opts.dur or ((opts.kind == "achievement") and 7 or 5.5)
    f:SetAlpha(0)
    f:Show()
    if opts.sound then PlayEventSound(opts.sound, opts.friend) end
end

-- opts: kind, title, text, icon | class, head, pts, sound, friend, dur, force
function ns.Toast(opts)
    if not db or type(opts) ~= "table" then return end
    if not opts.force and not db.settings.toasts then return end
    local q = toast.queue
    if #q >= 8 then
        for i, o in ipairs(q) do
            if o.kind ~= "achievement" then table.remove(q, i); break end
        end
    end
    q[#q + 1] = opts
    ns.ToastNext()
end

-- =============================================================================
-- UI: side 5 - instanser (wipes, bosser, clears)
-- =============================================================================
local RUN_ROWS = 9

local function MakeFriendButtons(page, store, onPick)
    for i, name in ipairs(ROSTER) do
        local b = MakeButton(page, 170, 34, name, function() onPick(name) end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(i - 1) * 38)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
        b.text:SetJustifyH("LEFT")
        b.score = Txt(b, "GameFontNormal")
        b.score:SetPoint("RIGHT", b, "RIGHT", -10, 0)
        b.score:SetJustifyH("RIGHT")
        b.score:SetTextColor(0.7, 0.7, 0.76)
        store[i] = b
    end
end

local RUN_COLS = {
    { x = 10,  w = 220, j = "LEFT" },
    { x = 234, w = 56,  j = "CENTER" },
    { x = 292, w = 56,  j = "CENTER" },
    { x = 350, w = 80,  j = "CENTER" },
    { x = 434, w = 88,  j = "LEFT" },
}

local function RunList(friend)
    local list = {}
    for inst, e in pairs(db.runs[friend] or {}) do
        local kills, distinct = 0, 0
        for _, n in pairs(e.boss or {}) do
            kills = kills + n
            if n > 0 then distinct = distinct + 1 end
        end
        local info = BossInfo(inst)
        list[#list + 1] = {
            name = inst, wipes = e.wipes or 0, clears = e.clears or 0, kills = kills, distinct = distinct,
            known = info and #info.list or 0, last = e.last or 0, e = e,
        }
    end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return list
end

-- Alle bosser i en instans: de kendte (også dem med 0 kills) plus evt. andre registrerede
local function BossRows(inst, e)
    local rows, seen = {}, {}
    local info = BossInfo(inst)
    if info then
        for _, b in ipairs(info.list) do
            rows[#rows + 1] = { name = b, kills = (e.boss or {})[b] or 0, final = info.last[Norm(b)] and true or false }
            seen[b] = true
        end
    end
    local extra = {}
    for b, n in pairs(e.boss or {}) do
        if not seen[b] then extra[#extra + 1] = { name = b, kills = n, final = false } end
    end
    table.sort(extra, function(a, b) return a.name < b.name end)
    for _, r in ipairs(extra) do rows[#rows + 1] = r end
    return rows
end

local function BuildRunsPage(page)
    ns.runList = {}
    MakeFriendButtons(page, ns.runList, function(name)
        ns.runTarget = name
        ns.runInst = nil
        ns.runOffset = 0
        ns.RefreshUI()
    end)

    local panel = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", 182, 0)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        ns.runOffset = (ns.runOffset or 0) - delta
        ns.RefreshUI()
    end)
    ns.runPanel = panel

    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(44, 44)
    panel.icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    panel.name = Txt(panel, "GameFontNormalLarge")
    panel.name:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 10, -2)
    panel.sub = Txt(panel, "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -4)
    panel.sub:SetTextColor(0.7, 0.7, 0.76)

    panel.big = Txt(panel, "GameFontNormal")
    panel.big:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
    panel.big:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -10)
    panel.big:SetJustifyH("RIGHT")
    panel.bigLabel = Txt(panel, "GameFontHighlightSmall")
    panel.bigLabel:SetPoint("TOPRIGHT", panel.big, "BOTTOMRIGHT", 0, -2)
    panel.bigLabel:SetJustifyH("RIGHT")
    panel.bigLabel:SetTextColor(0.6, 0.6, 0.66)

    panel.heads = {}
    for i, c in ipairs(RUN_COLS) do
        local fs = Txt(panel, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", c.x + 12, -80)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.j)
        fs:SetTextColor(0.5, 0.5, 0.56)
        panel.heads[i] = fs
    end

    ns.runRows = {}
    for i = 1, RUN_ROWS do
        local row = MakeBox("Button", panel, COL_BTN, COL_BORDER)
        row:SetSize(526, 28)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(96 + (i - 1) * 30))
        row.f = {}
        for k, c in ipairs(RUN_COLS) do
            row.f[k] = Field(row, c.x, c.w, c.j, k == 1 and "GameFontNormal" or "GameFontHighlight")
        end
        row:SetScript("OnClick", function(self)
            if self.data and not ns.runInst and self.data.name then
                ns.runInst = self.data.name
                ns.runOffset = 0
                ns.RefreshUI()
            end
        end)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
            local d = self.data
            if not d or ns.runInst or not d.e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.name, 1, 0.82, 0.2)
            GameTooltip:AddDoubleLine("Clears", tostring(d.clears), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Wipes", tostring(d.wipes), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            for _, b in ipairs(BossRows(d.name, d.e)) do
                GameTooltip:AddDoubleLine(b.name, tostring(b.kills), 0.8, 0.8, 0.8, b.kills > 0 and 1 or 0.5, b.kills > 0 and 1 or 0.5, b.kills > 0 and 1 or 0.5)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Klik for at se alle bosser", 0.5, 0.5, 0.56)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            GameTooltip:Hide()
        end)
        ns.runRows[i] = row
    end

    panel.empty = Txt(panel, "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -110)
    panel.empty:SetWidth(500)
    panel.empty:SetTextColor(0.6, 0.6, 0.66)

    panel.legend = Txt(panel, "GameFontHighlightSmall")
    panel.legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
    panel.legend:SetTextColor(0.5, 0.5, 0.56)

    panel.back = MakeButton(panel, 110, 22, "< Tilbage", function()
        ns.runInst = nil
        ns.runOffset = 0
        ns.RefreshUI()
    end)
    panel.back:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 8)
end

local function RefreshRuns()
    if not ns.runTarget then ns.runTarget = db.me or ROSTER[1] end
    local list = BuildStats()
    local cur
    for i, s in ipairs(list) do
        local btn = ns.runList[i]
        local r, g, b = ClassColor(s.class)
        btn.text:SetText(s.name .. (s.isMe and "  (dig)" or ""))
        btn.text:SetTextColor(r, g, b)
        btn.score:SetText(s.clears > 0 and tostring(s.clears) or "-")
        if s.name == ns.runTarget then
            btn:SetBackdropColor(COL_SELECT[1], COL_SELECT[2], COL_SELECT[3], 1)
            cur = s
        else
            btn:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end
    if not cur then return end

    local panel = ns.runPanel
    local r, g, b = ClassColor(cur.class)
    SetClassIcon(panel.icon, cur.class)
    panel.name:SetText(cur.name)
    panel.name:SetTextColor(r, g, b)
    panel.sub:SetText(string.format("%s  -  %s  -  %s", Plural(cur.clears, "clear", "clears"),
        Plural(cur.wipes, "wipe", "wipes"), Plural(cur.kills, "bosskill", "bosskills")))
    panel.big:SetText(tostring(cur.clears))
    panel.big:SetTextColor(1, 1, 1)
    panel.bigLabel:SetText("instances klaret")

    local runs = RunList(cur.name)
    local selected
    if ns.runInst then
        for _, rr in ipairs(runs) do if rr.name == ns.runInst then selected = rr end end
        if not selected then ns.runInst = nil end
    end

    local rows, total
    if selected then
        rows = BossRows(selected.name, selected.e)
        panel.heads[1]:SetText(selected.name)
        panel.heads[2]:SetText("Dræbt")
        panel.heads[3]:SetText("")
        panel.heads[4]:SetText("")
        panel.heads[5]:SetText("")
    else
        rows = runs
        panel.heads[1]:SetText("Instance")
        panel.heads[2]:SetText("Clear")
        panel.heads[3]:SetText("Wipes")
        panel.heads[4]:SetText("Bosser")
        panel.heads[5]:SetText("Sidst")
    end
    total = #rows
    local offset = math.max(0, math.min(ns.runOffset or 0, math.max(0, total - RUN_ROWS)))
    ns.runOffset = offset

    for i, row in ipairs(ns.runRows) do
        local d = rows[offset + i]
        row.data = d
        if d then
            if selected then
                row.f[1]:SetText((d.final and "|cffffd100* |r" or "") .. d.name)
                row.f[1]:SetTextColor(d.kills > 0 and 1 or 0.55, d.kills > 0 and 1 or 0.55, d.kills > 0 and 1 or 0.6)
                row.f[2]:SetText(tostring(d.kills))
                row.f[2]:SetTextColor(d.kills > 0 and 0.4 or 0.55, d.kills > 0 and 0.9 or 0.55, d.kills > 0 and 0.5 or 0.6)
                row.f[3]:SetText("")
                row.f[4]:SetText("")
                row.f[5]:SetText("")
            else
                row.f[1]:SetText(d.name)
                row.f[1]:SetTextColor(1, 0.82, 0.2)
                row.f[2]:SetText(tostring(d.clears))
                row.f[2]:SetTextColor(d.clears > 0 and 0.4 or 0.55, d.clears > 0 and 0.9 or 0.55, d.clears > 0 and 0.5 or 0.6)
                row.f[3]:SetText(tostring(d.wipes))
                row.f[3]:SetTextColor(d.wipes > 0 and 1 or 0.55, d.wipes > 0 and 0.45 or 0.55, d.wipes > 0 and 0.45 or 0.6)
                row.f[4]:SetText(d.known > 0 and string.format("%d/%d", d.distinct, d.known) or tostring(d.distinct))
                if d.known > 0 and d.distinct >= d.known then row.f[4]:SetTextColor(1, 0.82, 0.2) else row.f[4]:SetTextColor(1, 1, 1) end
                row.f[5]:SetText("|cff888888" .. FormatAgo(d.last > 0 and d.last or nil) .. "|r")
            end
            row:Show()
        else
            row:Hide()
        end
    end

    panel.back:SetShown(selected and true or false)
    if total == 0 then
        panel.empty:SetText(cur.name .. " har ikke været i en dungeon eller raid med addonet endnu. " ..
            "Wipes, bosser og clears tæller fra den nye version.")
        panel.legend:SetText("")
    else
        panel.empty:SetText("")
        local hint = selected and "* = slutboss (den der giver en clear)" or "Klik på en instance for at se hver boss"
        if total > RUN_ROWS then
            hint = string.format("Viser %d-%d af %d  -  rul med musehjulet", offset + 1, math.min(offset + RUN_ROWS, total), total)
        end
        panel.legend:SetText(hint)
    end
end

-- =============================================================================
-- UI: side 6 - trofæer
-- =============================================================================
local ACH_ROWS = 6   -- synlige rækker (2 trofæer pr. række)

local function BuildTrophyPage(page)
    ns.trophyTitle = Txt(page, "GameFontNormalLarge")
    ns.trophyTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -2)
    ns.trophySub = Txt(page, "GameFontHighlightSmall")
    ns.trophySub:SetPoint("TOPLEFT", ns.trophyTitle, "BOTTOMLEFT", 0, -2)
    ns.trophySub:SetTextColor(0.6, 0.6, 0.66)

    ns.trophyPick = MakeButton(page, 200, 24, "", function()
        local cur = ns.trophyFriend or db.me or ROSTER[1]
        for i, n in ipairs(ROSTER) do
            if n == cur then cur = ROSTER[(i % #ROSTER) + 1]; break end
        end
        ns.trophyFriend = cur
        ns.trophyOffset = 0
        ns.RefreshUI()
    end)
    ns.trophyPick:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        ns.trophyOffset = (ns.trophyOffset or 0) - delta
        ns.RefreshUI()
    end)

    ns.trophyCards = {}
    for i = 1, ACH_ROWS * 2 do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local c = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        c:SetSize(360, 56)
        c:SetPoint("TOPLEFT", page, "TOPLEFT", col * 372, -(40 + row * 60))
        c:EnableMouse(true)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(40, 40)
        c.icon:SetPoint("LEFT", c, "LEFT", 8, 0)
        c.name = Txt(c, "GameFontNormal")
        c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 56, -8)
        c.name:SetWidth(240)
        c.name:SetWordWrap(false)
        c.desc = Txt(c, "GameFontHighlightSmall")
        c.desc:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
        c.desc:SetWidth(250)
        c.desc:SetWordWrap(true)
        c.pts = Txt(c, "GameFontNormalLarge")
        c.pts:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -8)
        c.pts:SetJustifyH("RIGHT")
        c.when = Txt(c, "GameFontHighlightSmall")
        c.when:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 6)
        c.when:SetJustifyH("RIGHT")
        c:SetScript("OnEnter", function(self)
            local a = self.ach
            if not a then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(a.name, 1, 0.82, 0.2)
            GameTooltip:AddLine(a.desc, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(" ")
            local who = {}
            for _, n in ipairs(ROSTER) do
                if db.ach[n] and db.ach[n][a.id] then who[#who + 1] = n end
            end
            if #who == 0 then
                GameTooltip:AddLine("Ingen har låst det op endnu", 0.5, 0.5, 0.56)
            else
                GameTooltip:AddLine("Låst op af: " .. table.concat(who, ", "), 0.4, 0.9, 0.5)
            end
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ns.trophyCards[i] = c
    end
end

local function RefreshTrophies()
    local friend = ns.trophyFriend or db.me or ROSTER[1]
    ns.trophyFriend = friend
    local n, pts = AchCount(friend)
    ns.trophyTitle:SetText("Trofæer")
    ns.trophyTitle:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
    ns.trophySub:SetText(string.format("%s har låst %d af %d op  -  %d trofæpoint", friend, n, #ACH, pts))
    ns.trophyPick.text:SetText("Se trofæer for: " .. friend)

    local rowsTotal = math.ceil(#ACH / 2)
    local offset = math.max(0, math.min(ns.trophyOffset or 0, math.max(0, rowsTotal - ACH_ROWS)))
    ns.trophyOffset = offset

    for i, c in ipairs(ns.trophyCards) do
        local a = ACH[offset * 2 + i]
        c.ach = a
        if a then
            local at = db.ach[friend] and db.ach[friend][a.id]
            c.icon:SetTexture(a.icon)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            c.name:SetText(a.name)
            c.desc:SetText(a.desc)
            c.pts:SetText(tostring(a.pts))
            if at then
                c:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                c:SetBackdropColor(0.14, 0.11, 0.05, 1)
                c.icon:SetVertexColor(1, 1, 1)
                c.name:SetTextColor(1, 1, 1)
                c.desc:SetTextColor(0.8, 0.8, 0.84)
                c.pts:SetTextColor(1, 0.82, 0.2)
                c.when:SetText("|cff40e060" .. FormatAgo(at) .. "|r")
            else
                c:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                c:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
                c.icon:SetVertexColor(0.35, 0.35, 0.35)
                c.name:SetTextColor(0.6, 0.6, 0.66)
                c.desc:SetTextColor(0.45, 0.45, 0.5)
                c.pts:SetTextColor(0.4, 0.4, 0.45)
                c.when:SetText("|cff666666Låst|r")
            end
            c:Show()
        else
            c:Hide()
        end
    end
end

-- =============================================================================
-- UI: side 7 - levelling-race
-- =============================================================================
local RACE_TRACK_X, RACE_TRACK_W = 166, 350

local function BuildRacePage(page)
    -- Skala over baren: 10, 20, ... 70
    for lvl = 10, MAX_LEVEL, 10 do
        local fs = Txt(page, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", RACE_TRACK_X + 1 + math.floor((RACE_TRACK_W - 2) * lvl / MAX_LEVEL) - 12, 0)
        fs:SetWidth(24)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(0.5, 0.5, 0.56)
        fs:SetText(tostring(lvl))
    end

    ns.raceRows = {}
    for i = 1, #ROSTER do
        local row = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        row:SetSize(732, 38)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(18 + (i - 1) * 42))
        row.rank = Field(row, 0, 24, "CENTER")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row, "LEFT", 30, 0)
        row.name = Field(row, 60, 100, "LEFT", "GameFontNormal")

        row.track = MakeBox("Frame", row, { 0.04, 0.04, 0.06, 1 }, COL_BORDER)
        row.track:SetSize(RACE_TRACK_W, 18)
        row.track:SetPoint("LEFT", row, "LEFT", RACE_TRACK_X, 0)
        row.fill = row.track:CreateTexture(nil, "ARTWORK")
        row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT", 1, -1)
        row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 1, 1)
        row.fill:SetWidth(1)

        row.info = Txt(row, "GameFontNormal")
        row.info:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -5)
        row.info:SetWidth(200)
        row.info:SetJustifyH("RIGHT")
        row.sub = Txt(row, "GameFontHighlightSmall")
        row.sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 5)
        row.sub:SetWidth(200)
        row.sub:SetJustifyH("RIGHT")
        row.sub:SetTextColor(0.6, 0.6, 0.66)
        ns.raceRows[i] = row
    end

    ns.raceNote = Txt(page, "GameFontHighlightSmall")
    ns.raceNote:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(18 + #ROSTER * 42 + 2))
    ns.raceNote:SetWidth(732)
    ns.raceNote:SetTextColor(0.5, 0.5, 0.56)
end

-- Hver vens bedste karakter: højeste level og derefter mest XP
local function RaceList()
    local list = {}
    for _, name in ipairs(ROSTER) do
        local best, bestName
        for cn, c in pairs((db.friends[name] and db.friends[name].chars) or {}) do
            local lv, xp = c.level or 0, c.xp or 0
            if not best or lv > (best.level or 0) or (lv == (best.level or 0) and xp > (best.xp or 0)) then
                best, bestName = c, cn
            end
        end
        local lv = best and best.level or 0
        local xp = (best and lv < MAX_LEVEL) and (best.xp or 0) or 0
        list[#list + 1] = {
            name = name, char = bestName, class = best and best.class, level = lv, xp = xp,
            progress = lv + xp / 100, online = IsOnline(name), isMe = (name == db.me),
        }
    end
    table.sort(list, function(a, b)
        if a.progress ~= b.progress then return a.progress > b.progress end
        return a.name < b.name
    end)
    return list
end

local function RefreshRace()
    local list = RaceList()
    local leader = list[1] and list[1].progress or 0
    for i, s in ipairs(list) do
        local row = ns.raceRows[i]
        local r, g, b = ClassColor(s.class)
        row.rank:SetText(tostring(i))
        SetClassIcon(row.icon, s.class)
        row.name:SetText(s.name .. (s.isMe and " (dig)" or ""))
        row.name:SetTextColor(r, g, b)

        local frac = math.min(1, math.max(0, s.progress / MAX_LEVEL))
        row.fill:SetWidth(math.max(1, math.floor((RACE_TRACK_W - 2) * frac)))
        if s.level >= MAX_LEVEL then
            BarFill(row.fill, COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        else
            BarFill(row.fill, r, g, b, 0.9)
        end

        if s.level > 0 then
            if s.level >= MAX_LEVEL then
                row.info:SetText("|cffffd100Level " .. MAX_LEVEL .. " - i mål!|r")
            else
                row.info:SetText(string.format("Level %d  (%d%%)", s.level, s.xp))
            end
            local gap = leader - s.progress
            local tail = (i == 1) and "|cffffd100forrest|r" or string.format("-%.1f level", gap)
            row.sub:SetText(string.format("%s%s  -  %s", s.char or "?", s.online and "  |cff40e060online|r" or "", tail))
        else
            row.info:SetText("|cff888888ikke set endnu|r")
            row.sub:SetText("")
        end

        if i == 1 and s.level > 0 then
            row:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        else
            row:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
        end
        if s.isMe then
            row:SetBackdropColor(0.13, 0.17, 0.26, 1)
        else
            row:SetBackdropColor(COL_PANEL[1], COL_PANEL[2], COL_PANEL[3], 1)
        end
    end
    ns.raceNote:SetText("Hver vens karakter med højest level tæller. XP-procenten opdateres, mens vennen er online.")
end

-- v0.5-sider og indstillinger ligger i en blok for sig, så hovedfilen holder sig under
-- Luas grænse på 200 lokale variabler. Hver side er sin egen blok og bruges udefra via
-- EXTRA_PAGES (og indstillingerne via ns.BuildOptions).
local EXTRA_PAGES = {}   -- fane-nummer -> { build, refresh }
do
    -- =============================================================================
    -- UI: side 8 - statistik (dødsfald og uheldsrating for rolls)
    -- =============================================================================
    local ROLL_COLS = {
        { x = 6,   w = 22,  j = "CENTER", label = "#" },
        { x = 30,  w = 104, j = "LEFT",   label = "Ven" },
        { x = 136, w = 46,  j = "CENTER", label = "Rolls" },
        { x = 184, w = 46,  j = "CENTER", label = "Vundet" },
        { x = 232, w = 52,  j = "CENTER", label = "Tabt" },
        { x = 286, w = 50,  j = "CENTER", label = "Snit" },
    }

    local function BuildStatsPage(page)
        local left = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
        left:SetWidth(362)
        local lt = Txt(left, "GameFontNormalLarge")
        lt:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -10)
        lt:SetText("Dødsstatistik")
        lt:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
        ns.deathStatText = Txt(left, "GameFontHighlightSmall")
        ns.deathStatText:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -10)
        ns.deathStatText:SetWidth(338)
        ns.deathStatText:SetWordWrap(false)
        ns.deathStatText:SetSpacing(4)

        local right = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        right:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(362)
        local rt = Txt(right, "GameFontNormalLarge")
        rt:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -10)
        rt:SetText("Uheldsrating for rolls")
        rt:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

        for _, c in ipairs(ROLL_COLS) do
            local fs = Txt(right, "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", right, "TOPLEFT", 10 + c.x, -40)
            fs:SetWidth(c.w)
            fs:SetJustifyH(c.j)
            fs:SetTextColor(0.5, 0.5, 0.56)
            fs:SetText(c.label)
        end

        ns.rollRows = {}
        for i = 1, #ROSTER do
            local row = MakeBox("Button", right, COL_BTN, COL_BORDER)
            row:SetSize(342, 28)
            row:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -(56 + (i - 1) * 31))
            row.f = {}
            for k, c in ipairs(ROLL_COLS) do
                row.f[k] = Field(row, c.x, c.w, c.j, k == 2 and "GameFontNormal" or "GameFontHighlight")
            end
            row:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                local d = self.data
                if not d then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(d.name, 1, 1, 1)
                local r = d.r
                if not r or (r.rolls or 0) == 0 then
                    GameTooltip:AddLine("Ingen rolls registreret endnu", 0.6, 0.6, 0.66)
                else
                    GameTooltip:AddDoubleLine("Deltaget i", Plural(r.rolls, "roll", "rolls"), 0.8, 0.8, 0.8, 1, 1, 1)
                    GameTooltip:AddDoubleLine("Vundet", tostring(r.wins or 0), 0.8, 0.8, 0.8, 0.4, 0.9, 0.5)
                    GameTooltip:AddDoubleLine("Tabt", tostring(math.max(0, r.rolls - (r.wins or 0))), 0.8, 0.8, 0.8, 1, 0.45, 0.45)
                    local avg = ns.AvgRoll(r)
                    if avg then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine("Snit-roll", string.format("%.1f (forventet 50,5)", avg), 0.8, 0.8, 0.8, 1, 1, 1)
                        GameTooltip:AddDoubleLine("Laveste / højeste", string.format("%d / %d", r.low or 0, r.high or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                    end
                    local luck = ns.LuckStats and ns.LuckStats(d.name)
                    if luck then
                        GameTooltip:AddDoubleLine("Held, seneste " .. luck.n .. " rolls", string.format("%d%%", math.floor(luck.pct + 0.5)), 0.8, 0.8, 0.8, 0.5, 0.8, 1)
                    end
                    if (r.rolls or 0) < ns.ROLL_MIN then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Rating fra " .. ns.ROLL_MIN .. " rolls", 0.5, 0.5, 0.56)
                    end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                GameTooltip:Hide()
            end)
            ns.rollRows[i] = row
        end

        ns.rollNote = Txt(right, "GameFontHighlightSmall")
        ns.rollNote:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 10)
        ns.rollNote:SetWidth(338)
        ns.rollNote:SetTextColor(0.5, 0.5, 0.56)
        ns.rollNote:SetText("Tabt = andel af dine need/greed-rolls, du ikke vandt. Snit = dit gennemsnitlige roll (held er 50,5).")
    end

    local function RefreshStatsPage()
        local mobs, zones, falls = ns.DeathStats()
        local lines = {}
        local function section(title, list, empty, max, fmt)
            lines[#lines + 1] = "|cffffd100" .. title .. "|r"
            if #list == 0 then
                lines[#lines + 1] = "|cff888888" .. empty .. "|r"
            else
                for i = 1, math.min(max, #list) do lines[#lines + 1] = fmt(i, list[i]) end
            end
            lines[#lines + 1] = " "
        end
        local function withWho(i, e)
            return string.format("%d. %s  |cffff8080%d|r  |cff888888(%s)|r", i, e.name, e.n, ns.WhoText(e.who, 3))
        end
        section("Farligste mob", mobs, "Ingen er blevet slået ihjel af et mob endnu.", 5, withWho)
        section("Farligste zone", zones, "Ingen dødsfald endnu.", 3, withWho)
        section("Faldskade-konge", falls, "Ingen er faldet ihjel endnu. Endnu.", 3, function(i, e)
            return string.format("%d. %s  |cffff8080%s|r%s", i, e.name, Plural(e.n, "fald", "fald"),
                i == 1 and "  |cffffd100(kongen)|r" or "")
        end)
        lines[#lines] = nil
        ns.deathStatText:SetText(table.concat(lines, "\n"))

        local list = {}
        for _, name in ipairs(ROSTER) do
            local r = db.rolls[name]
            list[#list + 1] = { name = name, r = r, loss = ns.LossRate(r), avg = ns.AvgRoll(r), rolls = r and r.rolls or 0 }
        end
        table.sort(list, function(a, b)
            if (a.loss ~= nil) ~= (b.loss ~= nil) then return a.loss ~= nil end
            if a.loss and a.loss ~= b.loss then return a.loss > b.loss end
            if a.rolls ~= b.rolls then return a.rolls > b.rolls end
            return a.name < b.name
        end)
        local classOf = {}
        for _, s in ipairs(BuildStats()) do classOf[s.name] = s.class end

        for i, d in ipairs(list) do
            local row = ns.rollRows[i]
            row.data = d
            local r = d.r
            local rr, gg, bb = ClassColor(classOf[d.name])
            row.f[1]:SetText(d.loss and tostring(i) or "-")
            row.f[2]:SetText(d.name .. (d.name == db.me and " (dig)" or ""))
            row.f[2]:SetTextColor(rr, gg, bb)
            row.f[3]:SetText(d.rolls > 0 and tostring(d.rolls) or "-")
            row.f[4]:SetText(r and r.rolls > 0 and tostring(r.wins or 0) or "-")
            if d.loss then
                row.f[5]:SetText(string.format("%d%%", math.floor(d.loss * 100 + 0.5)))
                if i == 1 then row.f[5]:SetTextColor(1, 0.35, 0.35) else row.f[5]:SetTextColor(1, 1, 1) end
            else
                row.f[5]:SetText("|cff666666-|r")
            end
            row.f[6]:SetText(d.avg and string.format("%.1f", d.avg) or "-")
            if d.avg and d.avg < 45 then
                row.f[6]:SetTextColor(1, 0.5, 0.5)
            elseif d.avg and d.avg > 56 then
                row.f[6]:SetTextColor(0.4, 0.9, 0.5)
            else
                row.f[6]:SetTextColor(1, 1, 1)
            end
            if i == 1 and d.loss then
                row:SetBackdropColor(0.20, 0.08, 0.08, 1)
            elseif d.name == db.me then
                row:SetBackdropColor(0.13, 0.17, 0.26, 1)
            else
                row:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
            end
        end
    end

    EXTRA_PAGES[8] = { build = BuildStatsPage, refresh = RefreshStatsPage }
end

do
    -- =============================================================================
    -- UI: side 9 - guldgraf over tid
    -- =============================================================================
    local GOLD_RANGES = { { label = "7 dage", days = 7 }, { label = "30 dage", days = 30 },
                          { label = "90 dage", days = 90 }, { label = "Alt", days = 0 } }
    local FRIEND_COLORS = {
        { 1.00, 0.82, 0.20 }, { 0.35, 0.70, 1.00 }, { 1.00, 0.40, 0.40 }, { 0.40, 0.90, 0.50 },
        { 0.75, 0.45, 1.00 }, { 1.00, 0.60, 0.25 }, { 0.30, 0.90, 0.90 }, { 0.95, 0.50, 0.80 },
    }
    local GRAPH_L, GRAPH_R, GRAPH_T, GRAPH_B = 58, 12, 12, 24

    local function GoldShort(copper)
        local g = (copper or 0) / 10000
        if g >= 10000 then return string.format("%.0fk g", g / 1000) end
        if g >= 1000 then return string.format("%.1fk g", g / 1000) end
        return string.format("%d g", math.floor(g + 0.5))
    end

    -- Rundt tal over max (i kobber), så akserne får pæne trin
    local function NiceMax(copper)
        local g = math.max(1, copper / 10000)
        local step = 1
        while step * 10 <= g do step = step * 10 end
        for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
            if step * m >= g then return step * m * 10000 end
        end
        return step * 10 * 10000
    end

    -- Målinger for en ven inden for perioden, plus "nu" ud fra vennens karakterer
    local function GoldSeries(friend, from, stat)
        local pts = {}
        for _, smp in ipairs(db.goldHist[friend] or {}) do
            if smp[1] >= from then pts[#pts + 1] = { smp[1], smp[2] } end
        end
        if stat and stat.chars > 0 and stat.seen and stat.seen >= from then
            local last = pts[#pts]
            if not last or stat.seen > last[1] then pts[#pts + 1] = { stat.seen, stat.gold } end
        end
        return pts
    end

    local function BuildGoldPage(page)
        ns.goldRange = ns.goldRange or 2
        ns.goldHidden = ns.goldHidden or {}
        ns.goldRangeBtns = {}
        for i, rg in ipairs(GOLD_RANGES) do
            local b = MakeButton(page, 76, 24, rg.label, function()
                ns.goldRange = i
                ns.RefreshUI()
            end)
            b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 80, 0)
            ns.goldRangeBtns[i] = b
        end
        ns.goldInfo = Txt(page, "GameFontHighlightSmall")
        ns.goldInfo:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -6)
        ns.goldInfo:SetJustifyH("RIGHT")
        ns.goldInfo:SetWidth(400)
        ns.goldInfo:SetTextColor(0.6, 0.6, 0.66)

        ns.goldFriendBtns = {}
        for i, name in ipairs(ROSTER) do
            local b = MakeButton(page, 87, 22, name, function()
                ns.goldHidden[name] = not ns.goldHidden[name] or nil
                ns.RefreshUI()
            end)
            b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 91, -30)
            b.friend = name
            b:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                local d = self.data
                if not d then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(self.friend, 1, 1, 1)
                if #d.pts == 0 then
                    GameTooltip:AddLine("Ingen målinger i perioden", 0.6, 0.6, 0.66)
                else
                    local first, last = d.pts[1][2], d.pts[#d.pts][2]
                    local diff = last - first
                    GameTooltip:AddDoubleLine("Nu", FormatGold(last), 0.8, 0.8, 0.8, 1, 1, 1)
                    GameTooltip:AddDoubleLine("I perioden", (diff >= 0 and "+" or "-") .. FormatGold(math.abs(diff)),
                        0.8, 0.8, 0.8, diff >= 0 and 0.4 or 1, diff >= 0 and 0.9 or 0.45, diff >= 0 and 0.5 or 0.45)
                    GameTooltip:AddDoubleLine("Målinger", tostring(#d.pts), 0.8, 0.8, 0.8, 1, 1, 1)
                end
                GameTooltip:AddLine("Klik for at skjule/vise", 0.5, 0.8, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                GameTooltip:Hide()
            end)
            ns.goldFriendBtns[i] = b
        end

        local g = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
        g:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -60)
        g:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        g.lines, g.dots, g.grid, g.ylab, g.xlab = {}, {}, {}, {}, {}
        for i = 1, 5 do
            local t = g:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetColorTexture(1, 1, 1, i == 1 and 0.18 or 0.06)
            t:SetHeight(1)
            g.grid[i] = t
            local fs = Txt(g, "GameFontHighlightSmall")
            fs:SetJustifyH("RIGHT")
            fs:SetWidth(GRAPH_L - 8)
            fs:SetTextColor(0.55, 0.55, 0.6)
            g.ylab[i] = fs
        end
        for i = 1, 5 do
            local fs = Txt(g, "GameFontHighlightSmall")
            fs:SetJustifyH("CENTER")
            fs:SetWidth(60)
            fs:SetTextColor(0.55, 0.55, 0.6)
            g.xlab[i] = fs
        end
        g.empty = Txt(g, "GameFontHighlight")
        g.empty:SetPoint("CENTER", g, "CENTER", 0, 0)
        g.empty:SetJustifyH("CENTER")
        g.empty:SetWidth(600)
        g.empty:SetTextColor(0.6, 0.6, 0.66)
        ns.goldGraph = g
    end

    local function GraphLine(g, i)
        local l = g.lines[i]
        if l == nil then
            l = g.CreateLine and g:CreateLine(nil, "ARTWORK") or false
            if l then
                l:SetThickness(2)
            end   -- ellers en ældre klient uden linjer: så tegnes kun prikker
            g.lines[i] = l
        end
        return l
    end

    local function GraphDot(g, i)
        local d = g.dots[i]
        if not d then
            d = g:CreateTexture(nil, "OVERLAY")
            d:SetSize(5, 5)
            g.dots[i] = d
        end
        return d
    end

    local function RefreshGoldPage()
        for i, b in ipairs(ns.goldRangeBtns) do
            local c = (i == ns.goldRange) and COL_SELECT or COL_BTN
            b:SetBackdropColor(c[1], c[2], c[3], 1)
        end
        local g = ns.goldGraph
        local now = time()
        local days = GOLD_RANGES[ns.goldRange].days
        local from = days > 0 and (now - days * 86400) or nil

        local stats = {}
        for _, s in ipairs(BuildStats()) do stats[s.name] = s end
        if not from then
            from = now
            for _, name in ipairs(ROSTER) do
                local h = db.goldHist[name]
                if h and h[1] and h[1][1] < from then from = h[1][1] end
            end
            if now - from < 86400 then from = now - 86400 end
        end

        local series, maxG, any = {}, 0, false
        for i, name in ipairs(ROSTER) do
            local pts = GoldSeries(name, from, stats[name])
            local b = ns.goldFriendBtns[i]
            b.data = { pts = pts }
            local col = FRIEND_COLORS[i]
            if ns.goldHidden[name] then
                b.text:SetTextColor(0.4, 0.4, 0.45)
                b:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
            else
                b.text:SetTextColor(col[1], col[2], col[3])
                b:SetBackdropColor(col[1] * 0.18, col[2] * 0.18, col[3] * 0.18, 1)
                series[#series + 1] = { name = name, pts = pts, col = col }
                for _, p in ipairs(pts) do
                    if p[2] > maxG then maxG = p[2] end
                    any = true
                end
            end
        end

        local w = (g:GetWidth() or 732) - GRAPH_L - GRAPH_R
        local h = (g:GetHeight() or 340) - GRAPH_T - GRAPH_B
        if w <= 0 then w = 732 - GRAPH_L - GRAPH_R end
        if h <= 0 then h = 340 - GRAPH_T - GRAPH_B end
        local top = NiceMax(maxG)

        for i = 1, 5 do
            local frac = (i - 1) / 4
            local y = GRAPH_B + h * frac
            g.grid[i]:ClearAllPoints()
            g.grid[i]:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GRAPH_L, y)
            g.grid[i]:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -GRAPH_R, y)
            g.ylab[i]:ClearAllPoints()
            g.ylab[i]:SetPoint("RIGHT", g, "BOTTOMLEFT", GRAPH_L - 6, y)
            g.ylab[i]:SetText(GoldShort(top * frac))
        end
        for i = 1, 5 do
            local frac = (i - 1) / 4
            local t = from + (now - from) * frac
            g.xlab[i]:ClearAllPoints()
            g.xlab[i]:SetPoint("TOP", g, "BOTTOMLEFT", GRAPH_L + w * frac, GRAPH_B - 4)
            g.xlab[i]:SetText(i == 5 and "nu" or date("%d/%m", t))
        end

        local function X(t) return GRAPH_L + w * ((t - from) / math.max(1, now - from)) end
        local function Y(c) return GRAPH_B + h * (c / top) end
        local nl, nd = 0, 0
        for _, s in ipairs(series) do
            local prev
            for _, p in ipairs(s.pts) do
                local x, y = X(p[1]), Y(p[2])
                nd = nd + 1
                local d = GraphDot(g, nd)
                d:ClearAllPoints()
                d:SetPoint("CENTER", g, "BOTTOMLEFT", x, y)
                d:SetColorTexture(s.col[1], s.col[2], s.col[3], 1)
                d:Show()
                if prev then
                    nl = nl + 1
                    local l = GraphLine(g, nl)
                    if l then
                        l:SetStartPoint("BOTTOMLEFT", g, prev[1], prev[2])
                        l:SetEndPoint("BOTTOMLEFT", g, x, y)
                        l:SetColorTexture(s.col[1], s.col[2], s.col[3], 0.9)
                        l:Show()
                    end
                end
                prev = { x, y }
            end
        end
        for i = nl + 1, #g.lines do if g.lines[i] then g.lines[i]:Hide() end end
        for i = nd + 1, #g.dots do g.dots[i]:Hide() end

        g.empty:SetText(any and "" or "Ingen guldmålinger i perioden. Der måles, hver gang nogen logger ud.")
        local total = 0
        for _, s in ipairs(series) do
            local last = s.pts[#s.pts]
            if last then total = total + last[2] end
        end
        ns.goldInfo:SetText(any and ("Samlet for de viste: " .. FormatGold(total)) or "")
    end

    EXTRA_PAGES[9] = { build = BuildGoldPage, refresh = RefreshGoldPage }
end

do
    -- =============================================================================
    -- UI: side 10 - professions (hvem kan crafte hvad)
    -- =============================================================================
    local PROF_CAP = 375

    -- profHolders[profession] = { { friend, char, rank, max, class }, ... } med bedste karakter pr. ven først
    local function ProfHolders()
        local res = {}
        for _, pr in ipairs(ns.PROFS) do res[pr.name] = {} end
        for _, friend in ipairs(ROSTER) do
            for char, c in pairs((db.friends[friend] and db.friends[friend].chars) or {}) do
                for name, v in pairs(ns.ParseProf(c.prof)) do
                    if res[name] then
                        local list = res[name]
                        list[#list + 1] = { friend = friend, char = char, rank = v[1], max = v[2], class = c.class }
                    end
                end
            end
        end
        for _, list in pairs(res) do
            table.sort(list, function(a, b)
                if a.rank ~= b.rank then return a.rank > b.rank end
                if a.friend ~= b.friend then return a.friend < b.friend end
                return a.char < b.char
            end)
        end
        return res
    end

    local function BuildProfPage(page)
        ns.profRows = {}
        for i, pr in ipairs(ns.PROFS) do
            local row = MakeBox("Button", page, COL_PANEL, COL_BORDER)
            row:SetSize(732, 26)
            row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(i - 1) * 28)
            row.prof = pr
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexture(IC(pr.icon))
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.name = Field(row, 30, 120, "LEFT", "GameFontNormal")
            row.name:SetText(pr.name)
            row.who = Field(row, 156, 568, "LEFT")
            row:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.prof.name, 1, 0.82, 0.2)
                local list = self.data or {}
                if #list == 0 then
                    GameTooltip:AddLine("Ingen af jer har det endnu", 0.6, 0.6, 0.66)
                end
                for _, e in ipairs(list) do
                    local r, g, b = ClassColor(e.class)
                    GameTooltip:AddDoubleLine(e.friend .. " - " .. e.char, string.format("%d/%d", e.rank, e.max), r, g, b,
                        e.rank >= PROF_CAP and 1 or 0.9, e.rank >= PROF_CAP and 0.82 or 0.9, e.rank >= PROF_CAP and 0.2 or 0.9)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                GameTooltip:Hide()
            end)
            ns.profRows[i] = row
        end
        ns.profNote = Txt(page, "GameFontHighlightSmall")
        ns.profNote:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(#ns.PROFS * 28 + 4))
        ns.profNote:SetWidth(732)
        ns.profNote:SetTextColor(0.5, 0.5, 0.56)
        ns.profNote:SetText("Hver vens bedste karakter står først. Hold musen over en linje for at se alle karakterer.")
    end

    local function RefreshProfPage()
        local holders = ProfHolders()
        for _, row in ipairs(ns.profRows) do
            local list = holders[row.prof.name] or {}
            row.data = list
            -- Én post pr. ven (den bedste karakter)
            local parts, seen = {}, {}
            for _, e in ipairs(list) do
                if not seen[e.friend] then
                    seen[e.friend] = true
                    local col = e.rank >= PROF_CAP and "ffd100" or "ffffff"
                    parts[#parts + 1] = string.format("%s |cff%s%d|r", ColorName(e.friend, e.class), col, e.rank)
                end
            end
            if #parts == 0 then
                row.who:SetText("|cff666666ingen endnu|r")
                row.name:SetTextColor(0.5, 0.5, 0.56)
                row.icon:SetVertexColor(0.4, 0.4, 0.4)
            else
                row.who:SetText(table.concat(parts, "    "))
                row.name:SetTextColor(1, 0.82, 0.2)
                row.icon:SetVertexColor(1, 1, 1)
            end
        end
    end

    EXTRA_PAGES[10] = { build = BuildProfPage, refresh = RefreshProfPage }
end

do
    -- =============================================================================
    -- UI: side 11 - gear pr. karakter
    -- =============================================================================
    local GEAR_ROWS = 12
    local GC = { icon = 4, char = 26, friend = 176, level = 270, ilvl = 312, ench = 380, gems = 520, time = 610 }

    local function GearList()
        local list = {}
        for _, friend in ipairs(ROSTER) do
            if not ns.gearFriend or ns.gearFriend == friend then
                for char, c in pairs((db.friends[friend] and db.friends[friend].chars) or {}) do
                    if c.gear then
                        list[#list + 1] = { friend = friend, char = char, class = c.class, level = c.level or 0, g = c.gear }
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if (a.g.il or 0) ~= (b.g.il or 0) then return (a.g.il or 0) > (b.g.il or 0) end
            return a.char < b.char
        end)
        return list
    end

    local function MissingSlots(me)
        local names = {}
        for id in tostring(me or ""):gmatch("(%d+)") do names[#names + 1] = ns.SLOT_NAME[tonumber(id)] or ("slot " .. id) end
        return names
    end

    local function BuildGearPage(page)
        ns.gearOffset = 0
        ns.gearFriendBtn = MakeButton(page, 180, 26, "Ven: Alle", function()
            local idx = 0
            for i, n in ipairs(ROSTER) do if n == ns.gearFriend then idx = i end end
            ns.gearFriend = ROSTER[idx + 1]   -- efter sidste ven kommer "Alle" (nil)
            ns.gearOffset = 0
            ns.RefreshUI()
        end)
        ns.gearFriendBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)

        local heads = { { "Karakter", GC.char, 150 }, { "Ven", GC.friend, 90 }, { "Lvl", GC.level, 40 },
                        { "Item level", GC.ilvl, 66 }, { "Enchants", GC.ench, 136 }, { "Gems", GC.gems, 86 },
                        { "Opdateret", GC.time, 120 } }
        for _, hd in ipairs(heads) do
            local fs = Txt(page, "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", page, "TOPLEFT", hd[2], -34)
            fs:SetWidth(hd[3])
            fs:SetTextColor(0.5, 0.5, 0.56)
            fs:SetText(hd[1])
        end

        ns.gearRows = {}
        for i = 1, GEAR_ROWS do
            local row = MakeBox("Button", page, COL_PANEL, COL_BORDER)
            row:SetSize(732, 24)
            row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(52 + (i - 1) * 26))
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", GC.icon, 0)
            row.char = Field(row, GC.char, 148, "LEFT", "GameFontNormal")
            row.friend = Field(row, GC.friend, 90)
            row.level = Field(row, GC.level, 40)
            row.ilvl = Field(row, GC.ilvl, 66)
            row.ench = Field(row, GC.ench, 136)
            row.gems = Field(row, GC.gems, 86)
            row.time = Field(row, GC.time, 118)
            row:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                local d = self.data
                if not d then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local r, g, b = ClassColor(d.class)
                GameTooltip:AddLine(d.char .. " (" .. d.friend .. ")", r, g, b)
                GameTooltip:AddDoubleLine("Snit item level", string.format("%.1f", d.g.il or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                local miss = MissingSlots(d.g.me)
                GameTooltip:AddLine(" ")
                if #miss == 0 then
                    GameTooltip:AddLine("Alle enchants er på", 0.4, 0.9, 0.5)
                else
                    GameTooltip:AddLine("Mangler enchant: " .. table.concat(miss, ", "), 1, 0.5, 0.5, true)
                end
                if (d.g.mg or 0) > 0 then
                    GameTooltip:AddLine("Tomme gem-sockets: " .. d.g.mg, 1, 0.5, 0.5)
                else
                    GameTooltip:AddLine("Ingen tomme sockets", 0.4, 0.9, 0.5)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                GameTooltip:Hide()
            end)
            ns.gearRows[i] = row
        end

        ns.gearInfo = Txt(page, "GameFontHighlightSmall")
        ns.gearInfo:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(52 + GEAR_ROWS * 26 + 4))
        ns.gearInfo:SetWidth(732)
        ns.gearInfo:SetTextColor(0.5, 0.5, 0.56)

        ns.gearEmpty = Txt(page, "GameFontHighlight")
        ns.gearEmpty:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -64)
        ns.gearEmpty:SetWidth(700)
        ns.gearEmpty:SetTextColor(0.6, 0.6, 0.66)

        page:EnableMouseWheel(true)
        page:SetScript("OnMouseWheel", function(_, delta)
            ns.gearOffset = (ns.gearOffset or 0) - delta * 3
            ns.RefreshUI()
        end)
    end

    local function RefreshGearPage()
        ns.gearFriendBtn.text:SetText("Ven: " .. (ns.gearFriend or "Alle"))
        local list = GearList()
        local total = #list
        local offset = math.max(0, math.min(ns.gearOffset or 0, math.max(0, total - GEAR_ROWS)))
        ns.gearOffset = offset
        for i, row in ipairs(ns.gearRows) do
            local d = list[offset + i]
            row.data = d
            if d then
                local r, g, b = ClassColor(d.class)
                SetClassIcon(row.icon, d.class)
                row.char:SetText(d.char)
                row.char:SetTextColor(r, g, b)
                row.friend:SetText(d.friend)
                row.level:SetText(d.level > 0 and tostring(d.level) or "-")
                row.ilvl:SetText(string.format("|cffffffff%.1f|r", d.g.il or 0))
                local miss = MissingSlots(d.g.me)
                if #miss == 0 then
                    row.ench:SetText("|cff40e060OK|r")
                else
                    row.ench:SetText(string.format("|cffff6060Mangler %d|r |cff888888(%s)|r", #miss, table.concat(miss, ", ")))
                end
                row.gems:SetText((d.g.mg or 0) > 0 and string.format("|cffff6060%d tomme|r", d.g.mg) or "|cff40e060OK|r")
                row.time:SetText("|cff888888" .. FormatAgo(d.g.t and d.g.t > 0 and d.g.t or nil) .. "|r")
                row:Show()
            else
                row:Hide()
            end
        end
        if total == 0 then
            ns.gearEmpty:SetText("Intet gear registreret endnu. Det måles, når en ven logger ind eller skifter udstyr.")
            ns.gearInfo:SetText("")
        else
            ns.gearEmpty:SetText("")
            ns.gearInfo:SetText(string.format("Viser %d-%d af %d  -  sorteret efter item level  -  ringe tælles ikke med i enchants",
                offset + 1, math.min(offset + GEAR_ROWS, total), total))
        end
    end

    EXTRA_PAGES[11] = { build = BuildGearPage, refresh = RefreshGearPage }
end

do
    -- =============================================================================
    -- UI: side 12 - reputation (nøgler og exalted)
    -- =============================================================================
    local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

    local function StandingLabel(s)
        return _G["FACTION_STANDING_LABEL" .. s] or STANDING_NAMES[s] or "?"
    end

    local function StandingColor(s)
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[s]
        if c then return c.r, c.g, c.b end
        if s >= 7 then return 0.4, 0.9, 0.5 end
        if s >= 5 then return 0.3, 0.7, 0.3 end
        return 0.8, 0.8, 0.8
    end

    -- Vennens karakterer for en nøgle-fraktion: { { char, class, s, p, m, faction } }, bedste først
    local function RepFor(friend, names)
        local list = {}
        for char, c in pairs((db.friends[friend] and db.friends[friend].chars) or {}) do
            for _, fname in ipairs(names) do
                local v = c.rep and c.rep[fname]
                if v then
                    local s, p, m = ns.ParseRep(v)
                    list[#list + 1] = { char = char, class = c.class, s = s, p = p, m = m, faction = fname }
                end
            end
        end
        table.sort(list, function(a, b)
            if a.s ~= b.s then return a.s > b.s end
            if a.p ~= b.p then return a.p > b.p end
            return a.char < b.char
        end)
        return list
    end

    -- Alle fraktioner, vennen er exalted med: { [fraktion] = { karakter, ... } }
    local function ExaltedFor(friend)
        local res, n = {}, 0
        for char, c in pairs((db.friends[friend] and db.friends[friend].chars) or {}) do
            for fname, v in pairs(c.rep or {}) do
                if ns.ParseRep(v) >= 8 then
                    if not res[fname] then res[fname] = {}; n = n + 1 end
                    table.insert(res[fname], char)
                end
            end
        end
        return res, n
    end

    local REP_X, REP_W = 154, 98

    local function RepCellTooltip(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if d.exalted then
            GameTooltip:AddLine(d.friend .. ": exalted med", 1, 0.82, 0.2)
            local names = {}
            for fname in pairs(d.exalted) do names[#names + 1] = fname end
            table.sort(names)
            if #names == 0 then GameTooltip:AddLine("Ingen endnu", 0.6, 0.6, 0.66) end
            for _, fname in ipairs(names) do
                GameTooltip:AddDoubleLine(fname, table.concat(d.exalted[fname], ", "), 0.9, 0.9, 0.9, 0.6, 0.6, 0.66)
            end
        else
            local k = d.key
            GameTooltip:AddLine(d.friend .. " - " .. table.concat(k.names, " / "), 1, 0.82, 0.2)
            GameTooltip:AddLine(k.item .. " (" .. k.what .. ") kræver Revered", 0.6, 0.6, 0.66, true)
            GameTooltip:AddLine(" ")
            if #d.list == 0 then GameTooltip:AddLine("Ingen karakterer har denne rep endnu", 0.6, 0.6, 0.66) end
            for _, e in ipairs(d.list) do
                local r, g, b = ClassColor(e.class)
                local sr, sg, sb = StandingColor(e.s)
                local txt = StandingLabel(e.s) .. (e.s < 8 and e.m > 0 and string.format(" %d/%d", e.p, e.m) or "")
                GameTooltip:AddDoubleLine(e.char, txt, r, g, b, sr, sg, sb)
            end
        end
        GameTooltip:Show()
    end

    local function BuildRepPage(page)
        local function head(text, x, w, tip)
            local hf = CreateFrame("Frame", nil, page)
            hf:SetSize(w, 20)
            hf:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
            local fs = Txt(hf, "GameFontHighlightSmall")
            fs:SetAllPoints(hf)
            fs:SetJustifyH(x == 0 and "LEFT" or "CENTER")
            fs:SetTextColor(0.5, 0.5, 0.56)
            fs:SetText(text)
            if tip then
                hf:EnableMouse(true)
                hf:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:AddLine(tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                hf:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
        head("Ven", 0, 150)
        for k, kf in ipairs(ns.KEY_FACTIONS) do
            head(kf.label, REP_X + (k - 1) * (REP_W + 2), REP_W,
                table.concat(kf.names, " / ") .. ": " .. kf.item .. " til " .. kf.what .. " (Revered)")
        end
        local exX = REP_X + #ns.KEY_FACTIONS * (REP_W + 2)
        head("Exalted", exX, 732 - exX, "Antal fraktioner, vennen er exalted med på mindst én karakter")

        ns.repRows = {}
        for i = 1, #ROSTER do
            local row = MakeBox("Frame", page, COL_PANEL, COL_BORDER)
            row:SetSize(732, 34)
            row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(24 + (i - 1) * 38))
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name = Field(row, 34, 116, "LEFT", "GameFontNormal")
            row.cells = {}
            for k = 1, #ns.KEY_FACTIONS + 1 do
                local x = REP_X + (k - 1) * (REP_W + 2)
                local w = (k <= #ns.KEY_FACTIONS) and REP_W or (732 - x - 4)
                local cell = MakeBox("Button", row, COL_BTN, COL_BORDER)
                cell:SetSize(w, 28)
                cell:SetPoint("LEFT", row, "LEFT", x, 0)
                cell.text = Txt(cell, "GameFontHighlightSmall")
                cell.text:SetPoint("CENTER", cell, "CENTER", 0, 0)
                cell.text:SetJustifyH("CENTER")
                cell.text:SetWidth(w - 4)
                cell.text:SetWordWrap(false)
                cell:SetScript("OnEnter", function(self)
                    self:SetBackdropBorderColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
                    RepCellTooltip(self)
                end)
                cell:SetScript("OnLeave", function(self)
                    self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                    GameTooltip:Hide()
                end)
                row.cells[k] = cell
            end
            ns.repRows[i] = row
        end

        ns.repNote = Txt(page, "GameFontHighlightSmall")
        ns.repNote:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(24 + #ROSTER * 38 + 2))
        ns.repNote:SetWidth(732)
        ns.repNote:SetTextColor(0.5, 0.5, 0.56)
        ns.repNote:SetText("Grøn = Revered eller bedre, så heroic-nøglen kan købes. Vennens bedste karakter vises. Hold musen over et felt for detaljer.")
    end

    local function RefreshRepPage()
        local stats = {}
        for _, s in ipairs(BuildStats()) do stats[s.name] = s end
        for i, friend in ipairs(ROSTER) do
            local row = ns.repRows[i]
            local s = stats[friend] or {}
            local r, g, b = ClassColor(s.class)
            SetClassIcon(row.icon, s.class)
            row.name:SetText(friend .. (friend == db.me and " (dig)" or ""))
            row.name:SetTextColor(r, g, b)
            for k, kf in ipairs(ns.KEY_FACTIONS) do
                local cell = row.cells[k]
                local list = RepFor(friend, kf.names)
                cell.data = { friend = friend, key = kf, list = list }
                local best = list[1]
                if best then
                    local sr, sg, sb = StandingColor(best.s)
                    local pct = (best.s < 8 and best.m > 0) and string.format(" %d%%", math.floor(best.p / best.m * 100)) or ""
                    cell.text:SetText(StandingLabel(best.s) .. pct)
                    cell.text:SetTextColor(sr, sg, sb)
                    if best.s >= ns.KEY_STANDING then
                        cell:SetBackdropColor(0.08, 0.22, 0.10, 1)
                    else
                        cell:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
                    end
                else
                    cell.text:SetText("-")
                    cell.text:SetTextColor(0.4, 0.4, 0.45)
                    cell:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
                end
            end
            local ex, n = ExaltedFor(friend)
            local cell = row.cells[#ns.KEY_FACTIONS + 1]
            cell.data = { friend = friend, exalted = ex }
            cell.text:SetText(n > 0 and tostring(n) or "-")
            if n > 0 then cell.text:SetTextColor(1, 0.82, 0.2) else cell.text:SetTextColor(0.4, 0.4, 0.45) end
            cell:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
        end
    end

    EXTRA_PAGES[12] = { build = BuildRepPage, refresh = RefreshRepPage }
end

do
    -- =============================================================================
    -- Indstillinger: panel i spillets Options (Interface > AddOns > Wasted Coast Forever)
    -- =============================================================================
    local QUALITY_CHOICES = { 2, 3, 4, 5 }

    local function MakeCheck(parent, label, tip, get, set)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb.label = Txt(parent, "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        cb.label:SetText(label)
        cb.tip = Txt(parent, "GameFontHighlightSmall")
        cb.tip:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -2)
        cb.tip:SetTextColor(0.6, 0.6, 0.66)
        cb.tip:SetText(tip)
        cb.get = get
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            if ns.RefreshUI then ns.RefreshUI() end
        end)
        return cb
    end

    local function RefreshOptions()
        local p = ns.options
        if not p or not db then return end
        for _, cb in ipairs(p.checks) do cb:SetChecked(cb.get() and true or false) end
        for _, b in ipairs(p.qualityBtns) do
            local sel = (db.settings.minQuality or 3) == b.q
            local c = sel and COL_SELECT or COL_BTN
            b:SetBackdropColor(c[1], c[2], c[3], 1)
        end
        for _, b in ipairs(p.meBtns) do
            local sel = db.me == b.friend
            local c = sel and COL_SELECT or COL_BTN
            b:SetBackdropColor(c[1], c[2], c[3], 1)
        end
        p.meText:SetText(db.me and ("Du er registreret som |cffffd100" .. db.me .. "|r.") or "|cffff6060Du har ikke valgt, hvem du er.|r")
    end
    ns.RefreshOptions = RefreshOptions

    local function BuildOptions()
        local p = CreateFrame("Frame", "WastedCoastOptions", UIParent, "BackdropTemplate")
        p.name = "Wasted Coast Forever"
        p:Hide()

        local title = Txt(p, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
        title:SetText("Wasted Coast Forever (WC4ever)")
        title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
        local sub = Txt(p, "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetTextColor(0.6, 0.6, 0.66)
        sub:SetText("Alt kan også styres med /wc4ever. Ændringer gælder med det samme.")

        p.checks = {}
        local checks = {
            { "Lyd", "Egne lydklip og Blizzards lyd ved dødsfald, loot, wipes og trofæer.",
              function() return db.settings.sound end, function(v) db.settings.sound = v end },
            { "Beskeder i chatten", "Skriv dødsfald, loot og bosskills i dit chatvindue.",
              function() return db.settings.announce end, function(v) db.settings.announce = v end },
            { "Popups", "Små beskeder øverst på skærmen, når en ven logger ind, stiger i level eller wiper.",
              function() return db.settings.toasts end, function(v) db.settings.toasts = v end },
            { "Synk uden guild", "Skjult kanal og usynlige whispers, så I ser hinanden uden fælles guild eller gruppe.",
              function() return db.settings.fallbackSync ~= false end, function(v) ns.SetFallbackSync(v) end },
        }
        for i, c in ipairs(checks) do
            local cb = MakeCheck(p, c[1], c[2], c[3], c[4])
            cb:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -60 - (i - 1) * 44)
            p.checks[i] = cb
        end

        local qh = Txt(p, "GameFontNormal")
        qh:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -244)
        qh:SetText("Minimumskvalitet for loot")
        local qs = Txt(p, "GameFontHighlightSmall")
        qs:SetPoint("TOPLEFT", qh, "BOTTOMLEFT", 0, -2)
        qs:SetTextColor(0.6, 0.6, 0.66)
        qs:SetText("Loot under denne kvalitet bliver ikke registreret.")
        p.qualityBtns = {}
        for i, q in ipairs(QUALITY_CHOICES) do
            local b = MakeButton(p, 110, 24, string.format("|cff%s%s|r", QUALITY_HEX[q], QUALITY_NAME[q]), function()
                db.settings.minQuality = q
                RefreshOptions()
                if ns.RefreshUI then ns.RefreshUI() end
            end)
            b.q = q
            b:SetPoint("TOPLEFT", p, "TOPLEFT", 18 + (i - 1) * 116, -280)
            p.qualityBtns[i] = b
        end

        local mh = Txt(p, "GameFontNormal")
        mh:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -326)
        mh:SetText("Hvem er du?")
        p.meText = Txt(p, "GameFontHighlightSmall")
        p.meText:SetPoint("TOPLEFT", mh, "BOTTOMLEFT", 0, -2)
        p.meBtns = {}
        for i, name in ipairs(ROSTER) do
            local b = MakeButton(p, 110, 24, name, function()
                if db.me ~= name then SetMe(name) end
                if ns.picker then ns.picker:Hide() end
                RefreshOptions()
            end)
            b.friend = name
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", 18 + col * 116, -362 - row * 30)
            p.meBtns[i] = b
        end

        local open = MakeButton(p, 150, 24, "Åbn WC4ever", function()
            if ns.frame then ns.frame:Show() end
        end)
        open:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -436)
        local test = MakeButton(p, 150, 24, "Vis test-popups", function()
            SlashCmdList["WASTEDCOAST"]("testtoast")
        end)
        test:SetPoint("LEFT", open, "RIGHT", 8, 0)
        local sync = MakeButton(p, 150, 24, "Synk med vennerne", function()
            SlashCmdList["WASTEDCOAST"]("sync")
        end)
        sync:SetPoint("LEFT", test, "RIGHT", 8, 0)

        p:SetScript("OnShow", RefreshOptions)

        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(p, p.name)
            Settings.RegisterAddOnCategory(cat)
            ns.optionsCategory = cat
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(p)
        else
            -- Ingen Options-menu i denne klient: vis panelet som et selvstændigt vindue
            p.standalone = true
            p:SetBackdrop(FLAT)
            p:SetBackdropColor(COL_BG[1], COL_BG[2], COL_BG[3], COL_BG[4])
            p:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
            p:SetSize(520, 474)
            p:SetPoint("CENTER")
            p:SetFrameStrata("DIALOG")
            p:EnableMouse(true)
            local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
            table.insert(UISpecialFrames, "WastedCoastOptions")
        end
        ns.options = p
    end

    function ns.OpenOptions()
        local p = ns.options
        if not p then return end
        if ns.optionsCategory and Settings and Settings.OpenToCategory then
            local id = ns.optionsCategory.GetID and ns.optionsCategory:GetID() or ns.optionsCategory.ID
            Settings.OpenToCategory(id)
        elseif InterfaceOptionsFrame_OpenToCategory and not p.standalone then
            -- Kaldes to gange: første kald åbner ikke altid den rigtige side
            InterfaceOptionsFrame_OpenToCategory(p)
            InterfaceOptionsFrame_OpenToCategory(p)
        else
            p:Show()
        end
    end

    ns.BuildOptions = BuildOptions
end

-- =============================================================================
-- UI: hovedvindue, faner og identitetsvalg
-- =============================================================================
-- Fire faner, hver med sine undersider. Sidenumrene er de gamle (ns.ShowTab(3) viser stadig karaktererne).
local GROUPS = {
    { label = "Venner",     icon = "INV_Misc_Head_Human_01",
      pages = { 1, 3, 11, 10, 12, 9 }, names = { "Kort", "Karakterer", "Gear", "Professions", "Reputation", "Guld" } },
    { label = "Rangliste",  icon = "Ability_Rogue_Sprint",
      pages = { 2, 7, 14 },            names = { "Scoreboard", "Race", "Dueller" } },
    { label = "Loot & død", icon = "INV_Misc_Bone_HumanSkull_01",
      pages = { 4, 5, 8 },             names = { "Loot", "Instanser", "Statistik" } },
    { label = "Sjov",       icon = "Spell_Nature_Polymorph",
      pages = { 6, 13 },               names = { "Trofæer", "Drilleri" } },
}
ns.GROUPS = GROUPS

function ns.ShowTab(i)
    ns.tab = i
    for idx, page in ipairs(ns.pages) do page:SetShown(idx == i) end
    for gi, grp in ipairs(GROUPS) do
        local active = false
        for si, pg in ipairs(grp.pages) do
            local on = (pg == i)
            if on then active = true end
            local sb = ns.subTabs[gi] and ns.subTabs[gi][si]
            if sb then sb:SetActive(on) end
        end
        if active then ns.group = gi end
        if ns.tabs[gi] then ns.tabs[gi]:SetActive(active) end
    end
    for gi, list in pairs(ns.subTabs) do
        for _, sb in ipairs(list) do sb:SetShown(gi == ns.group) end
    end
    ns.RefreshUI()
end

function ns.PickFriend(name)
    ns.target = name
    ns.charOffset = 0
    ns.RefreshUI()
end

function ns.SelectTarget(name)
    ns.target = name
    ns.charOffset = 0
    ns.ShowTab(3)
end

function ns.RefreshUI()
    local f = ns.frame
    if not f or not f:IsShown() or not db then return end
    if db.me then
        f.me:SetText("Du er: |cffffd100" .. db.me .. "|r")
    else
        f.me:SetText("|cffff6060Du har ikke valgt, hvem du er|r")
    end
    if ns.tab == 1 then
        RefreshOverview()
    elseif ns.tab == 2 then
        RefreshScoreboard()
    elseif ns.tab == 3 then
        RefreshChars()
    elseif ns.tab == 4 then
        RefreshLoot()
    elseif ns.tab == 5 then
        RefreshRuns()
    elseif ns.tab == 6 then
        RefreshTrophies()
    elseif ns.tab == 7 then
        RefreshRace()
    elseif EXTRA_PAGES[ns.tab] then
        EXTRA_PAGES[ns.tab].refresh()
    end
    if ns.options and ns.options:IsShown() then ns.RefreshOptions() end
end

function ns.ShowIdentityPicker()
    if not ns.picker then
        local p = MakeBox("Frame", UIParent, COL_BG, COL_GOLD, "WastedCoastPicker")
        p:SetSize(260, 66 + #ROSTER * 30 + 10)
        p:SetPoint("CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        AddShadow(p, 8)

        local title = Txt(p, "GameFontNormalLarge")
        title:SetPoint("TOP", p, "TOP", 0, -12)
        title:SetJustifyH("CENTER")
        title:SetFont("Fonts\\MORPHEUS.TTF", 20, "")
        if not title:GetFont() then title:SetFontObject("GameFontNormalLarge") end
        title:SetShadowOffset(1, -1)
        title:SetText("Hvem er du?")

        local sub = Txt(p, "GameFontHighlightSmall")
        sub:SetPoint("TOP", p, "TOP", 0, -38)
        sub:SetJustifyH("CENTER")
        sub:SetTextColor(0.6, 0.6, 0.66)
        sub:SetText("Så ved addonet, hvem dine karakterer og dit loot er.")

        for i, name in ipairs(ROSTER) do
            local b = MakeButton(p, 220, 24, name, function()
                SetMe(name)
                p:Hide()
            end)
            b:SetPoint("TOP", p, "TOP", 0, -(62 + (i - 1) * 30))
        end
        table.insert(UISpecialFrames, "WastedCoastPicker")
        ns.picker = p
    end
    ns.picker:Show()
end

ns.LOGO = "Interface\\AddOns\\" .. addonName .. "\\media\\logo"

-- WC4ever-logo ved minimappet: venstreklik åbner/lukker, højreklik åbner indstillinger, træk flytter den
function ns.BuildMinimapButton()
    if ns.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "WastedCoastMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
    icon:SetTexture(ns.LOGO)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function Place()
        local a = math.rad(db.settings.minimapAngle or 215)
        local r = (Minimap:GetWidth() or 140) / 2 + 10
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    local function Follow()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local sc = Minimap:GetEffectiveScale()
        if not (mx and cx and sc) then return end
        db.settings.minimapAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
        Place()
    end
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Follow) GameTooltip:Hide() end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.OpenOptions()
        elseif ns.frame then
            ns.frame:SetShown(not ns.frame:IsShown())
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Wasted Coast Forever (WC4ever)", COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
        local online = 0
        for _, name in ipairs(ROSTER) do if IsOnline(name) then online = online + 1 end end
        GameTooltip:AddLine(string.format("%d af %d venner online", online, #ROSTER), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Venstreklik: åbn/luk vinduet", 0.7, 0.7, 0.76)
        GameTooltip:AddLine("Højreklik: indstillinger", 0.7, 0.7, 0.76)
        GameTooltip:AddLine("Træk: flyt knappen  -  skjul med /wc4ever minimap", 0.7, 0.7, 0.76)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
    b:SetShown(not db.settings.minimapHide)
    ns.minimapButton = b
end

local function BuildUI()
    -- Faneblade: (ikon +) tekst; den valgte får guldtekst og en guldstreg forneden
    local function MakeTab(parent, w, h, label, icon, onClick, font)
        local tb = MakeBox("Button", parent, COL_BTN, COL_BORDER)
        tb:SetSize(w, h)
        tb.text = Txt(tb, font or "GameFontHighlight")
        tb.text:SetText(label)
        tb.icon = tb:CreateTexture(nil, "ARTWORK")
        if icon then
            -- Ikon og tekst centreret sammen
            local size = h - 10
            tb.icon:SetSize(size, size)
            tb.text:SetPoint("CENTER", tb, "CENTER", (size + 6) / 2, 0)
            tb.icon:SetPoint("RIGHT", tb.text, "LEFT", -6, 0)
            SafeIcon(tb.icon, "Interface\\Icons\\" .. icon)
        else
            tb.text:SetPoint("CENTER", tb, "CENTER", 0, 0)
            tb.icon:Hide()
        end
        tb.accent = tb:CreateTexture(nil, "OVERLAY")
        tb.accent:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 1, 1)
        tb.accent:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -1, 1)
        tb.accent:SetHeight(2)
        tb.accent:SetColorTexture(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)

        function tb:SetActive(on)
            self.active = on
            self.accent:SetShown(on)
            self.icon:SetDesaturated(not on)
            self.icon:SetAlpha(on and 1 or 0.75)
            if on then
                self:SetBackdropColor(0.17, 0.15, 0.09, 1)
                self:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
                self.text:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])
            else
                self:SetBackdropColor(COL_BTN[1], COL_BTN[2], COL_BTN[3], 1)
                self:SetBackdropBorderColor(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
                self.text:SetTextColor(0.78, 0.78, 0.82)
            end
        end
        tb:SetScript("OnEnter", function(self)
            if not self.active then self.text:SetTextColor(1, 1, 1) self.icon:SetDesaturated(false) self.icon:SetAlpha(1) end
        end)
        tb:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
        tb:SetScript("OnClick", onClick)
        tb:SetActive(false)
        return tb
    end

    -- Vandret streg, der toner ud mod begge ender
    local function FadeLine(parent, y, r, g, b, a)
        local left = parent:CreateTexture(nil, "ARTWORK")
        left:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        left:SetPoint("TOPRIGHT", parent, "TOP", 0, y)
        left:SetHeight(1)
        Gradient(left, "HORIZONTAL", r, g, b, 0, r, g, b, a)
        local right = parent:CreateTexture(nil, "ARTWORK")
        right:SetPoint("TOPLEFT", parent, "TOP", 0, y)
        right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
        right:SetHeight(1)
        Gradient(right, "HORIZONTAL", r, g, b, a, r, g, b, 0)
    end

    local f = MakeBox("Frame", UIParent, COL_BG, COL_BORDER, "WastedCoastFrame")
    f:SetSize(760, 552)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.settings.pos = { point, relPoint, x, y }
    end)
    local pos = db.settings.pos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    table.insert(UISpecialFrames, "WastedCoastFrame")

    AddShadow(f, 8)

    -- Header: guldskær fra venstre, ikon og titel i quest-skriften
    local band = f:CreateTexture(nil, "BORDER", nil, 1)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    band:SetHeight(36)
    Gradient(band, "HORIZONTAL", COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 0.16, COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 0)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -4)
    logo:SetTexture(ns.LOGO)

    local title = Txt(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetFont("Fonts\\MORPHEUS.TTF", 21, "")
    if not title:GetFont() then title:SetFontObject("GameFontNormalLarge") end
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetText("Wasted Coast Forever")
    title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

    local sub = Txt(f, "GameFontHighlightSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -2)
    sub:SetTextColor(0.6, 0.6, 0.68)
    sub:SetText("WC4ever  -  vi dør sammen")

    local ver = Txt(f, "GameFontHighlightSmall")
    ver:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -13)
    ver:SetJustifyH("RIGHT")
    ver:SetTextColor(0.45, 0.45, 0.5)
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end)(addonName, "Version")
    ver:SetText(GAME.label .. (version and ("  -  v" .. version) or ""))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    FadeLine(f, -37, COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 0.45)

    -- Fire store faner og en række små undersider under den valgte
    ns.tabs, ns.subTabs = {}, {}
    for gi, grp in ipairs(GROUPS) do
        local tb = MakeTab(f, 178, 30, grp.label, grp.icon, function() ns.ShowTab(grp.pages[1]) end, "GameFontNormalLarge")
        tb:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (gi - 1) * 184.6, -42)
        ns.tabs[gi] = tb
        ns.subTabs[gi] = {}
        for si, pg in ipairs(grp.pages) do
            local sb = MakeTab(f, 112, 20, grp.names[si], nil, function() ns.ShowTab(pg) end, "GameFontHighlightSmall")
            sb:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (si - 1) * 116, -79)
            ns.subTabs[gi][si] = sb
        end
    end

    FadeLine(f, -104, COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 0.35)

    -- Sider
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -112)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 36)

    ns.pages = {}
    for i = 1, 14 do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints(content)
        ns.pages[i] = p
    end
    BuildOverview(ns.pages[1])
    BuildScoreboard(ns.pages[2])
    BuildCharsPage(ns.pages[3])
    BuildLootPage(ns.pages[4])
    BuildRunsPage(ns.pages[5])
    BuildTrophyPage(ns.pages[6])
    BuildRacePage(ns.pages[7])
    for i, pg in pairs(EXTRA_PAGES) do pg.build(ns.pages[i]) end

    -- Footer: lidt mørkere bånd med en streg over
    local foot = f:CreateTexture(nil, "BORDER", nil, 1)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    foot:SetHeight(32)
    Gradient(foot, "VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0.1)
    local footLine = f:CreateTexture(nil, "ARTWORK")
    footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 33)
    footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 33)
    footLine:SetHeight(1)
    footLine:SetColorTexture(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 0.8)

    f.me = Txt(f, "GameFontHighlightSmall")
    f.me:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)

    local switch = MakeButton(f, 50, 20, "Skift", function() ns.ShowIdentityPicker() end)
    switch:SetPoint("LEFT", f.me, "RIGHT", 10, 0)
    local opts = MakeButton(f, 100, 20, "Indstillinger", function() ns.OpenOptions() end)
    opts:SetPoint("LEFT", switch, "RIGHT", 6, 0)
    local refresh = MakeButton(f, 80, 20, "Opdater", function() ns.RefreshNow() end)
    refresh:SetPoint("LEFT", opts, "RIGHT", 6, 0)

    local hint = Txt(f, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("RIGHT")
    hint:SetTextColor(0.5, 0.5, 0.56)
    hint:SetText("Klik på et kort for at se vennens karakterer")

    -- Opdater løbende, mens vinduet er åbent (online-status, "set for x min siden")
    -- og ton blødt ind, når det åbnes
    local elapsed, fade = 0, 1
    f:SetScript("OnUpdate", function(self, dt)
        if fade < 1 then
            fade = math.min(1, fade + dt / 0.15)
            self:SetAlpha(fade)
        end
        elapsed = elapsed + dt
        if elapsed >= 2 then
            elapsed = 0
            ns.RefreshUI()
        end
    end)
    f:SetScript("OnShow", function(self)
        fade = 0
        self:SetAlpha(0)
        ns.RefreshUI()
    end)

    ns.frame = f
    ns.ShowTab(1)
    f:Hide()
end

-- =============================================================================
-- Demo-data (kun lokalt, til at se hvordan det ser ud)
-- =============================================================================
-- I en blok for sig (Luas grænse på 200 lokale variabler)
do
    local DEMO_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN", "DRUID" }
    local DEMO_SUFFIX = { "", "tank", "heal", "pvp", "alt" }
    local DEMO_ZONES = { "Hellfire Peninsula", "Zangarmarsh", "Terokkar Forest", "Nagrand", "Blade's Edge Mountains" }
    local DEMO_PLACES = {
        dungeon = { "The Slave Pens", "Shadow Labyrinth", "The Mechanar", "The Botanica" },
        raid    = { "Karazhan", "Gruul's Lair", "Magtheridon's Lair" },
        world   = { "Nagrand", "Hellfire Peninsula", "Netherstorm" },
        bg      = { "Warsong Gulch", "Arathi Basin" },
    }
    local DEMO_INST = { "The Slave Pens", "Shadow Labyrinth", "The Mechanar", "Karazhan", "The Botanica", "Gruul's Lair" }
    if not GAME.isTBC then
        DEMO_ZONES = { "Westfall", "Stranglethorn Vale", "Tanaris", "Mount Hyjal", "Eastern Plaguelands" }
        DEMO_PLACES = {
            dungeon = { "The Deadmines", "Shadowfang Keep", "Blackrock Depths", "Stratholme" },
            raid    = { "Onyxia's Lair", "Hyjal Summit" },
            world   = { "Westfall", "Mount Hyjal", "Stranglethorn Vale" },
            bg      = { "Warsong Gulch", "Arathi Basin" },
        }
        DEMO_INST = { "The Deadmines", "Shadowfang Keep", "Blackrock Depths", "Stratholme", "Onyxia's Lair" }
    end
    local DEMO_CTX = { "dungeon", "dungeon", "dungeon", "raid", "raid", "world", "bg" }
    local DEMO_HOW = { "need", "need", "greed", "de", "drop", "drop", "roll" }
    local DEMO_ITEMS = {
        { 28830, "Dragonspine Trophy", 4 }, { 28789, "Eye of Magtheridon", 4 },
        { 29370, "Icon of the Silver Crescent", 4 }, { 28034, "Hourglass of the Unraveller", 4 },
        { 32837, "Warglaive of Azzinoth", 4 }, { 19019, "Thunderfury, Blessed Blade of the Windseeker", 5 },
    }
    local DEMO_KILLERS = {
        { "Bonechewer Ravager", "Nærkamp" }, { "Fel Reaver", "Stomp" }, { "Faldskade", "" },
        { "Omgivelserne", "Lava" }, { "En meget vred kylling", "Næbhug" }, { "Marsh Lurker", "Nærkamp" },
        { "Omgivelserne", "Faldskade" },
    }
    local DEMO_EXALTED = { "Stormwind", "Darnassus", "Timbermaw Hold", "Argent Dawn", "The Aldor", "The Consortium", "Sporeggar" }

    -- Professions, gear og reputation til en demo-karakter
    local function DemoCharExtras(c)
        local parts, used = {}, {}
        for _ = 1, 2 do
            local pr = ns.PROFS[math.random(1, 10)]
            if not used[pr.name] then
                used[pr.name] = true
                local rank = math.random(1, 3) == 1 and 375 or math.random(150, 374)
                parts[#parts + 1] = string.format("%s=%d/375", pr.name, rank)
            end
        end
        if math.random() < 0.6 then parts[#parts + 1] = "Cooking=" .. math.random(50, 375) .. "/375" end
        if math.random() < 0.4 then parts[#parts + 1] = "First Aid=" .. math.random(100, 375) .. "/375" end
        table.sort(parts)
        c.prof = table.concat(parts, ",")

        local miss = {}
        for _, slot in ipairs({ 1, 3, 5, 7, 8, 9, 10, 15, 16 }) do
            if math.random() < 0.25 then miss[#miss + 1] = slot end
        end
        c.gear = { il = math.floor((60 + math.random() * 70) * 10) / 10, me = table.concat(miss, ","),
                   mg = math.random(0, 3) == 0 and math.random(1, 4) or 0, t = time() - math.random(60, 300000) }

        c.rep = {}
        for _, kf in ipairs(ns.KEY_FACTIONS) do
            if math.random() < 0.8 then
                local s = math.random(4, 8)
                local m = ({ [4] = 3000, [5] = 6000, [6] = 12000, [7] = 21000, [8] = 999 })[s]
                c.rep[kf.names[1]] = string.format("%d:%d:%d", s, s == 8 and 0 or math.random(0, m - 1), m)
            end
        end
        for _ = 1, math.random(0, 3) do
            c.rep[DEMO_EXALTED[math.random(#DEMO_EXALTED)]] = "8:0:999"
        end
    end

    local function ClearDemo()
        for i = #db.events, 1, -1 do
            if db.events[i].id:find("^demo%-") then
                db.seen[db.events[i].id] = nil
                table.remove(db.events, i)
            end
        end
        for i = #db.loot, 1, -1 do
            if db.loot[i].id:find("^demo%-") then
                db.lootSeen[db.loot[i].id] = nil
                table.remove(db.loot, i)
            end
        end
        for friend, runs in pairs(db.runs) do
            for inst, e in pairs(runs) do
                if e.demo then runs[inst] = nil end
            end
            if not next(runs) then db.runs[friend] = nil end
        end
        for friend, ids in pairs(db.demoAch) do
            for id in pairs(ids) do
                if db.ach[friend] then db.ach[friend][id] = nil end
            end
            if db.ach[friend] and not next(db.ach[friend]) then db.ach[friend] = nil end
        end
        wipe(db.demoAch)
        for friend, r in pairs(db.rolls) do
            if r.demo then db.rolls[friend] = nil end
        end
        if ns.ClearPrankDemo then ns.ClearPrankDemo() end
        for friend, h in pairs(db.goldHist) do
            for i = #h, 1, -1 do
                if h[i].d then table.remove(h, i) end
            end
            if #h == 0 then db.goldHist[friend] = nil end
        end
        for name, info in pairs(db.friends) do
            for cn, c in pairs(info.chars or {}) do
                if c.demo then
                    info.chars[cn] = nil
                    if db.chars[cn] == name then db.chars[cn] = nil end
                end
            end
            if not next(info.chars or {}) then db.friends[name] = nil end
        end
        if ns.RefreshUI then ns.RefreshUI() end
    end

    local function MakeDemo()
        ClearDemo()
        local now = time()
        for i, name in ipairs(ROSTER) do
            if name ~= db.me then
                local chars = {}
                local count = math.random(1, 5)
                for k = 1, count do
                    local cname = name .. DEMO_SUFFIX[k]
                    local class = DEMO_CLASSES[((i + k * 3) % #DEMO_CLASSES) + 1]
                    local seen = (k == 1 and math.random() < 0.5) and now or (now - math.random(600, 400000))
                    local real = db.friends[name] and db.friends[name].chars and db.friends[name].chars[cname]
                    if real then
                        -- Rør aldrig ægte karakterer: brug den bare som den er
                        class = real.class or class
                    else
                        local c = UpdateChar(name, cname, {
                            class = class, level = math.random(8, MAX_LEVEL),
                            gold = math.random(5, 4000) * 10000 + math.random(0, 99) * 100,
                            zone = DEMO_ZONES[math.random(#DEMO_ZONES)], xp = math.random(0, 99),
                        }, seen)
                        c.demo = true
                        DemoCharExtras(c)
                    end
                    chars[#chars + 1] = { name = cname, class = class }
                end

                for d = 1, math.random(0, 5) do
                    local ch = chars[math.random(#chars)]
                    local k = DEMO_KILLERS[math.random(#DEMO_KILLERS)]
                    local id = "demo-" .. name .. "-" .. d
                    db.seen[id] = true
                    table.insert(db.events, {
                        id = id, name = ch.name, class = ch.class, killer = k[1], ability = k[2],
                        level = math.random(8, MAX_LEVEL), zone = DEMO_ZONES[math.random(#DEMO_ZONES)],
                        time = now - math.random(60, 90000), friend = name,
                    })
                end

                for _ = 1, math.random(1, 4) do
                    local inst = DEMO_INST[math.random(#DEMO_INST)]
                    if not RunEntry(name, inst) then
                        local e = RunEntry(name, inst, true)
                        e.demo = true
                        e.wipes = math.random(0, 6)
                        e.clears = math.random(0, 5)
                        e.last = now - math.random(600, 400000)
                        for _, b in ipairs((BossInfo(inst) or BOSSES[inst] or { list = {} }).list) do
                            if math.random() < 0.7 then e.boss[b] = math.random(1, 6) end
                        end
                    end
                end

                if not db.rolls[name] then
                    local rolls = math.random(4, 40)
                    local cnt = math.random(rolls, rolls * 2)
                    db.rolls[name] = { rolls = rolls, wins = math.random(0, math.floor(rolls / 2)), cnt = cnt,
                                       sum = cnt * math.random(35, 65), low = math.random(1, 9), high = math.random(90, 100), demo = true }
                end

                if not db.goldHist[name] or #db.goldHist[name] == 0 then
                    local g = math.random(20, 800) * 10000
                    for k = 1, math.random(4, 16) do
                        g = math.max(0, g + math.random(-150, 300) * 10000)
                        ns.AddGoldSample(name, now - (17 - k) * math.random(20000, 200000), g, true)
                    end
                end

                db.ach[name] = db.ach[name] or {}
                db.demoAch[name] = db.demoAch[name] or {}
                for _ = 1, math.random(2, 9) do
                    local a = ACH[math.random(#ACH)]
                    if not db.ach[name][a.id] then
                        db.ach[name][a.id] = now - math.random(600, 900000)
                        db.demoAch[name][a.id] = true
                    end
                end

                for l = 1, math.random(0, 7) do
                    local ch = chars[math.random(#chars)]
                    local it = DEMO_ITEMS[math.random(#DEMO_ITEMS)]
                    local ctx = DEMO_CTX[math.random(#DEMO_CTX)]
                    local places = DEMO_PLACES[ctx]
                    local id = "demo-L-" .. name .. "-" .. l
                    db.lootSeen[id] = true
                    table.insert(db.loot, {
                        id = id, friend = name, char = ch.name, class = ch.class,
                        item = "item:" .. it[1], name = it[2], quality = it[3],
                        how = (ctx == "world") and "drop" or DEMO_HOW[math.random(#DEMO_HOW)],
                        ctx = ctx, zone = places[math.random(#places)], time = now - math.random(60, 300000),
                    })
                end
            end
        end
        if ns.MakePrankDemo then ns.MakePrankDemo() end
        if ns.RefreshUI then ns.RefreshUI() end
    end

    ns.ClearDemo = ClearDemo
    ns.MakeDemo = MakeDemo
end

-- =============================================================================
-- Synk uden guild: skjul kanalens beskeder og fejl fra whispers til offline karakterer
-- =============================================================================
do
    local notFound

    local function HideNotFound(_, _, msg)
        notFound = notFound or FormatToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
        local name = notFound and msg and msg:match(notFound)
        if not name then return false end
        local key = ((Ambiguate and Ambiguate(name, "none")) or name):lower()
        local at = route.probed[key]
        if not at or GetTime() - at > 30 then return false end
        -- Karakteren er gået offline: stop med at whispere den
        for friend, w in pairs(route.whisper) do
            if w.char:lower() == key then route.whisper[friend] = nil end
        end
        return true
    end

    local function IsSyncChannel(...)
        local want = route.CHANNEL:lower()
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v:lower():find(want, 1, true) then return true end
        end
        return false
    end

    local function HideChannelNotice(_, _, _, _, _, channelString, _, _, _, _, channelName)
        return IsSyncChannel(channelString, channelName)
    end

    function ns.InitFallbackFilters()
        if not ChatFrame_AddMessageEventFilter then return end
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", HideNotFound)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", HideChannelNotice)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", HideChannelNotice)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_JOIN", HideChannelNotice)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LEAVE", HideChannelNotice)
    end

    -- /wc4ever status: hvordan hver ven nås lige nu
    local VIA_LABEL = { GUILD = "guild", PARTY = "party", RAID = "raid", CHANNEL = "skjult kanal" }
    function ns.PrintRoutes()
        local id = (GetChannelName(route.CHANNEL)) or 0
        if db.settings.fallbackSync == false then
            Print("Synk uden guild er slået fra (|cffffd100/wc4ever kanal|r slår den til).")
        elseif not route.channelOK then
            Print("Den skjulte kanal virker ikke i denne klient. Vennerne nås via whisper.")
        else
            Print("Skjult kanal: " .. (id > 0 and ("|cff40ff40forbundet|r (/" .. id .. ")") or "|cffff6060ikke forbundet|r"))
        end
        for _, friend in ipairs(ROSTER) do
            if friend ~= db.me then
                local s, w = route.shared[friend], route.whisper[friend]
                local how
                if route.Recent(s) then how = "|cff40ff40" .. (VIA_LABEL[s.via] or s.via) .. "|r"
                elseif route.Recent(w) then how = "|cff40ff40whisper|r (" .. w.char .. ")"
                else how = "|cff9aa0a6ikke hørt fra de seneste 3 minutter|r" end
                print("  " .. friend .. ": " .. how)
            end
        end
    end
end

-- =============================================================================
-- Events
-- =============================================================================
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("CHAT_MSG_LOOT")
-- Forever (og Midnight) giver ikke addons adgang til combat log; der fejler registreringen
if not GAME.isForever then
    pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED")
end
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_FLAGS_CHANGED")
events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
-- Boss-events findes ikke i alle spilversioner: en ukendt event giver ellers en Lua-fejl
pcall(events.RegisterEvent, events, "ENCOUNTER_END")
pcall(events.RegisterEvent, events, "BOSS_KILL")
-- v0.5: guld ved logout, professions, gear og reputation
pcall(events.RegisterEvent, events, "PLAYER_LOGOUT")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_EQUIPMENT_CHANGED")
pcall(events.RegisterEvent, events, "UPDATE_FACTION")
if GAME.isForever then pcall(events.RegisterEvent, events, "ACHIEVEMENT_EARNED") end
pcall(events.RegisterEvent, events, "PLAYER_PVP_KILLS_CHANGED")
pcall(events.RegisterEvent, events, "HONOR_CURRENCY_UPDATE")
pcall(events.RegisterEvent, events, "CURRENCY_DISPLAY_UPDATE")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end
        InitDB()
        BuildLootPatterns()
        if RegisterPrefix then RegisterPrefix(PREFIX) end
        BuildUI()
        ns.BuildMinimapButton()
        ns.BuildOptions()
        ns.InitFallbackFilters()
        StartPump()
        Print("indlæst (" .. GAME.label .. "). Skriv /wc4ever for at åbne vinduet.")

    elseif event == "PLAYER_LOGIN" then
        -- Den skjulte synk-kanal: efter spillets egne kanaler, så de beholder /1 og /2
        C_Timer.After(5, route.Join)
        -- Vent lidt, så guild/party-info er klar
        C_Timer.After(6, function()
            if db.me then
                SendHeartbeat()
                RequestSync()
                ns.InitAchievements()
                ns.AfterIdentity()
            else
                ns.ShowIdentityPicker()
            end
        end)
        C_Timer.NewTicker(60, function()
            SendHeartbeat()
            ns.CheckGold()
        end)
        -- Hent vennernes data automatisk hvert 10. minut (de svarer højst så ofte uden "Opdater")
        C_Timer.NewTicker(600, function() RequestSync() end)
        C_Timer.NewTicker(2, CheckWipe)
        OnZoneChanged()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if db then OnZoneChanged() end

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        lastCombat = GetTime()

    elseif event == "PLAYER_XP_UPDATE" then
        TouchMe()

    elseif event == "PLAYER_LOGOUT" then
        if db and db.me then ns.SampleMyGold() end

    elseif event == "SKILL_LINES_CHANGED" then
        if db and db.me then ns.ScheduleScan("prof", 3) end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if db and db.me then ns.ScheduleScan("gear", 3) end

    elseif event == "PLAYER_PVP_KILLS_CHANGED" or event == "HONOR_CURRENCY_UPDATE" or event == "CURRENCY_DISPLAY_UPDATE" then
        ns.ScheduleHonor()

    elseif event == "ACHIEVEMENT_EARNED" then
        if db and db.me then C_Timer.After(3, ns.UpdateMyLegacy) end

    elseif event == "UPDATE_FACTION" then
        if db and db.me and not ns.IsScanningRep() then ns.ScheduleScan("rep", 10) end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        ns.OnFlags((...))

    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)

    elseif event == "BOSS_KILL" then
        OnBossKillEvent(...)

    elseif event == "PLAYER_LEVEL_UP" then
        PlayEventSound("levelup", db and db.me)
        C_Timer.After(2, SendHeartbeat)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()

    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()

    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage((...))

    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)

    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- Lige kommet ind i den skjulte kanal: sig hej og bed om data dér
        local notice, _, _, _, _, _, _, _, channelName = ...
        if notice == "YOU_JOINED" and channelName and channelName:lower() == route.CHANNEL:lower() then
            C_Timer.After(2, function()
                if not db.me then return end
                SendHeartbeat()
                Send("Q;" .. db.me)
            end)
        end
    end
end)

-- =============================================================================
-- Slash-kommandoer
-- =============================================================================
SLASH_WASTEDCOAST1 = "/wc4ever"
SLASH_WASTEDCOAST2 = "/wastedcoast"
SLASH_WASTEDCOAST3 = "/wc4l"   -- gammelt navn, virker stadig
SlashCmdList["WASTEDCOAST"] = function(input)
    local cmd, arg = strsplit(" ", strtrim((input or ""):lower()), 2)

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.frame:SetShown(not ns.frame:IsShown())
    elseif cmd == "minimap" then
        db.settings.minimapHide = not db.settings.minimapHide
        if ns.minimapButton then ns.minimapButton:SetShown(not db.settings.minimapHide) end
        Print("Knappen ved minimappet er " .. (db.settings.minimapHide and "skjult" or "vist igen") .. ".")
    elseif cmd == "jeg" then
        ns.ShowIdentityPicker()
    elseif cmd == "config" or cmd == "indstillinger" or cmd == "options" then
        ns.OpenOptions()
    elseif cmd == "sound" then
        local isEvent = false
        for _, e in ipairs(SOUND_EVENTS) do if e == arg then isEvent = true end end
        if isEvent then
            local ok, what = PlayEventSound(arg, db.me, true)
            Print(string.format("Lyd til |cffffd100%s|r: %s", arg, ok and ("afspillet (" .. what .. ")") or what))
        elseif arg and arg ~= "" then
            Print("Ukendt event. Prøv: " .. table.concat(SOUND_EVENTS, ", "))
        else
            db.settings.sound = not db.settings.sound
            Print("Lyd: " .. (db.settings.sound and "til" or "fra") ..
                ".  Test en lyd med |cffffd100/wc4ever sound <event>|r (" .. table.concat(SOUND_EVENTS, ", ") .. ").")
        end
    elseif cmd == "toast" then
        db.settings.toasts = not db.settings.toasts
        Print("Toasts (online, wipe, level): " .. (db.settings.toasts and "til" or "fra"))
    elseif cmd == "testtoast" then
        -- Viser eksempler på alle popups, uden at gemme eller sende noget
        local _, class = UnitClass("player")
        ns.Toast({ kind = "online", title = "Mikkel er online", text = "Mikkeltank (level 62) - Hellfire Peninsula",
                   class = class, force = true })
        ns.ShowWipeToast("Nick", "Shadow Labyrinth", time() + math.random(1, 9999) * 100)
        local a = ACH[math.random(#ACH)]
        ns.Toast({ kind = "achievement", head = "TROFÆ LÅST OP", title = a.name, text = a.desc, icon = a.icon,
                   pts = a.pts, sound = "achievement", friend = db.me, force = true })
        if ns.TestPrankToasts then ns.TestPrankToasts() end
    elseif cmd == "announce" then
        db.settings.announce = not db.settings.announce
        Print("Beskeder i chat: " .. (db.settings.announce and "til" or "fra"))
    elseif cmd == "loot" then
        local levels = { uncommon = 2, rare = 3, epic = 4, legendary = 5 }
        if arg and levels[arg] then
            db.settings.minQuality = levels[arg]
            Print("Registrerer nu loot af kvalitet |cffffd100" .. QUALITY_NAME[levels[arg]] .. "|r eller bedre.")
        else
            Print("Registrerer loot af kvalitet " .. (QUALITY_NAME[db.settings.minQuality] or "Rare") ..
                " eller bedre. Skift med |cffffd100/wc4ever loot uncommon|rare|epic|legendary|r.")
        end
    elseif cmd == "sync" then
        ns.RefreshNow()
        Print("Anmoder vennerne om at sende deres data...")
    elseif cmd == "status" then
        ns.PrintRoutes()
    elseif cmd == "kanal" then
        ns.SetFallbackSync(db.settings.fallbackSync == false)
        Print("Synk uden guild (skjult kanal og whispers): " .. (db.settings.fallbackSync ~= false and "til" or "fra"))
    elseif cmd == "demo" then
        if arg == "slut" or arg == "clear" then
            ns.ClearDemo()
            Print("Demo-data er fjernet.")
        else
            ns.MakeDemo()
            Print("Demo-data lagt ind (kun lokalt). Fjern det igen med |cffffd100/wc4ever demo slut|r.")
            ns.frame:Show()
        end
    elseif cmd == "test" then
        -- Falsk død, så du kan teste uden at dø (sendes ikke til de andre)
        AddDeath({
            id = "test-" .. time() .. "-" .. math.random(1000, 9999),
            name = UnitName("player"), class = select(2, UnitClass("player")),
            killer = "En meget vred kylling", ability = "Næbhug",
            level = UnitLevel("player"), zone = Clean(GetZoneText()), time = time(), friend = db.me,
        })
    elseif cmd == "testloot" then
        -- Falsk loot win (sendes ikke til de andre)
        local ctx, place = InstanceContext()
        AddLoot({
            id = "test-L-" .. time() .. "-" .. math.random(1000, 9999),
            friend = db.me, char = UnitName("player"), class = select(2, UnitClass("player")),
            item = "item:28830", name = "Dragonspine Trophy", quality = 4, how = "need",
            ctx = ctx, zone = Clean(place), time = time(),
        })
    elseif cmd == "reset" then
        if arg == "ja" then
            wipe(db.runs)
            wipe(db.rolls)
            wipe(db.goldHist)
            if ns.ResetPranks then ns.ResetPranks() end
            wipe(db.ach)
            wipe(db.demoAch)
            db.achInit = nil
            wipe(db.events)
            wipe(db.seen)
            wipe(db.loot)
            wipe(db.lootSeen)
            wipe(db.friends)
            wipe(db.chars)
            db.me = nil
            ns.RefreshUI()
            Print("Alle data er slettet.")
        else
            Print("Skriv |cffffd100/wc4ever reset ja|r for at slette alle data.")
        end
    elseif ns.PrankSlash and ns.PrankSlash(cmd, arg) then
        -- klaret i Drilleri.lua (angrib, annonce, emotes, testannonce)
    else
        Print("Kommandoer:")
        print("  /wc4ever              - vis/skjul vinduet")
        print("  /wc4ever jeg          - vælg, hvem du er")
        print("  /wc4ever config       - åbn indstillingerne (også under Options > AddOns)")
        print("  /wc4ever loot         - vis/skift minimumskvalitet for loot (uncommon, rare, epic, legendary)")
        print("  /wc4ever demo         - fyld med demo-data (|cffffd100demo slut|r fjerner det)")
        print("  /wc4ever sync         - hent data fra vennerne igen")
        print("  /wc4ever status       - se, hvordan hver ven nås (guild, gruppe, kanal eller whisper)")
        print("  /wc4ever kanal        - slå synk uden guild til/fra")
        print("  /wc4ever sound        - slå lyd til/fra  (|cffffd100sound <event>|r tester en lyd)")
        print("  /wc4ever toast        - slå popups (online, wipe, level) til/fra")
        print("  /wc4ever minimap      - vis/skjul WC4ever-knappen ved minimappet")
        print("  /wc4ever testtoast    - vis eksempler på popups")
        print("  /wc4ever announce     - slå chat-beskeder til/fra")
        print("  /wc4ever angrib <ven> - send et emote-angreb til en ven")
        print("  /wc4ever annonce      - slå dødsannoncer til/fra")
        print("  /wc4ever emotes       - slå popups for emote-angreb mod dig til/fra")
        print("  /wc4ever testannonce  - vis en test-dødsannonce")
        print("  /wc4ever test         - lav et falsk dødsfald")
        print("  /wc4ever testloot     - lav en falsk loot win")
        print("  /wc4ever reset ja     - slet alle data")
    end
end

-- =============================================================================
-- v0.6: det, Drilleri.lua skal bruge herfra (filen indlæses efter denne)
-- =============================================================================
ns.core = {
    ROSTER = ROSTER, ROSTER_SET = ROSTER_SET, ENV_NAMES = ENV_NAMES, GAME = GAME, MAX_LEVEL = MAX_LEVEL,
    QUALITY_HEX = QUALITY_HEX, EXTRA_PAGES = EXTRA_PAGES,
    COL_BG = COL_BG, COL_PANEL = COL_PANEL, COL_BORDER = COL_BORDER, COL_GOLD = COL_GOLD,
    COL_BTN = COL_BTN, COL_SELECT = COL_SELECT,
    Print = Print, ClassColor = ClassColor, ColorName = ColorName, FormatAgo = FormatAgo, Plural = Plural,
    FormatToPattern = FormatToPattern, FriendOfChar = FriendOfChar, EventFriend = EventFriend,
    IsOnline = IsOnline, BuildStats = BuildStats, Send = Send,
    MakeBox = MakeBox, Txt = Txt, Field = Field, MakeButton = MakeButton,
    Gradient = Gradient, BarFill = BarFill, SafeIcon = SafeIcon,
}
