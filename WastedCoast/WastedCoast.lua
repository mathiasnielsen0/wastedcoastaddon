local addonName, ns = ...

-- =============================================================================
-- Wasted Coast (WC4L)
--   * Kort-overblik over vennerne
--   * Scoreboard (sorterbart)
--   * Karakterer: alle karakterer hver ven har været logget ind med
--   * Loot: alle rare+ loot wins (Need/Greed/Drop, dungeon/raid/verden)
--   * Dødstæller, titler og presence (hvem er online)
--   * v0.4: egne lyde, toasts, wipe- og bosstæller, trofæer og levelling-race
-- =============================================================================

local PREFIX = "WCOAST"   -- addon-besked prefix (max 16 tegn)
local SCHEMA = 4          -- version af dataformatet i SavedVariables

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

local MAX_LEVEL = 70

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

local function BossInfo(inst)
    return inst and BOSS_BY_NORM[Norm(inst)] or nil
end

local SendMsg = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

local db            -- sættes i InitDB (= WastedCoastDB)
local lastDamage    -- { t = GetTime(), source = "...", ability = "..." }

-- =============================================================================
-- Hjælpefunktioner
-- =============================================================================
local function Print(msg)
    print("|cff33ff99Wasted Coast:|r " .. msg)
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

-- Afspiller lyden til et event. Returnerer ok, beskrivelse (bruges af /wc4l sound <event>)
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
    if not quality and GetItemInfo then
        local _, _, q = GetItemInfo(itemString)
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
    db.demoAch = db.demoAch or {}    -- demo-trofæer (fjernes af /wc4l demo slut)
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

-- Liste over alle venner i roster-rækkefølge
local function BuildStats()
    local deaths = DeathsByFriend()
    local loot = LootByFriend()
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
    return titles, holders
end

local TITLE_ORDER = { "Klovnen", "Lootgoblin", "Rigmanden", "Højest level", "Alt-junkie", "Wipe-konge" }

-- =============================================================================
-- Netværk: kø, beskeder og synkronisering
-- =============================================================================
local queue = {}

local function Channels()
    local ch = {}
    if IsInRaid() then ch[#ch + 1] = "RAID" elseif IsInGroup() then ch[#ch + 1] = "PARTY" end
    if IsInGuild() then ch[#ch + 1] = "GUILD" end
    return ch
end

local function Send(msg, priority)
    for _, c in ipairs(Channels()) do
        local item = { msg, c }
        if priority then table.insert(queue, 1, item) else queue[#queue + 1] = item end
    end
    while #queue > 500 do table.remove(queue, 1) end
end

local function StartPump()
    C_Timer.NewTicker(0.3, function()
        local item = table.remove(queue, 1)
        if item then SendMsg(PREFIX, item[1], item[2]) end
    end)
end

local function SerializeDeath(ev)
    return table.concat({
        "D", ev.id, ev.name, ev.class or "", ev.killer, ev.ability,
        ev.level, ev.zone, ev.time, ev.friend or "",
    }, ";")
end

local function DeserializeDeath(t)
    if #t < 9 then return nil end
    local f = t[10]
    if f and not ROSTER_SET[f] then f = nil end
    return {
        id = t[2], name = t[3], class = t[4], killer = t[5], ability = t[6],
        level = tonumber(t[7]) or 0, zone = t[8], time = tonumber(t[9]) or 0,
        friend = f,
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

local function RequestSync()
    if db.me then Send("Q;" .. db.me) end
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
    if isDrop and GetItemInfoInstant then
        -- Spring crafting-materialer over (fx Void Crystals fra disenchant)
        local _, _, _, _, _, classID = GetItemInfoInstant(it.id)
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

local function OnLootMessage(msg)
    if type(msg) ~= "string" then return end
    for _, p in ipairs(LOOT_PATTERNS) do
        if msg:find(p.pattern) then
            local it = ParseLink(msg)
            if not it then return end
            if p.kind == "choice" then
                rollChoice[it.id] = { how = p.how, t = GetTime() }
            elseif p.kind == "won" then
                local how = p.how
                if not how then
                    local ch = rollChoice[it.id]
                    how = (ch and (GetTime() - ch.t) < 180) and ch.how or "roll"
                end
                recentRoll[it.id] = GetTime()
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
        if UnitExists(unit) and (not UnitIsConnected or UnitIsConnected(unit)) then
            total = total + 1
            if UnitIsDeadOrGhost(unit) then dead = dead + 1 end
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
        local recentFight = (UnitAffectingCombat and UnitAffectingCombat("player")) or (GetTime() - lastCombat) < 90
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
    { id = "lvl60", name = "Klar til Outland", desc = "Nå level 60.", icon = IC("INV_Misc_Note_01"), pts = 10,
      test = function(S) return S.maxLevel >= 60 end },
    { id = "lvl70", name = "Max level", desc = "Nå level 70.", icon = IC("INV_Misc_Note_01"), pts = 25,
      test = function(S) return S.maxLevel >= 70 end },
    { id = "alts5", name = "Alt-junkie", desc = "Spil med 5 forskellige karakterer.", icon = IC("INV_Misc_Bag_08"), pts = 15,
      test = function(S) return S.chars >= 5 end },
    { id = "gold1000", name = "Rigmanden", desc = "Eje 1000 guld på tværs af dine karakterer.", icon = IC("INV_Misc_Coin_01"), pts = 15,
      test = function(S) return S.gold >= 1000 * 10000 end },
    { id = "night", name = "Nattergalen", desc = "Log ind mellem klokken 02 og 05 om natten.", icon = IC("INV_Misc_PocketWatch_01"), pts = 10 },
}
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
-- Indkommende ekstra-beskeder (S, B, W, A) og toasts for venner
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
    elseif prevLevel and level and level == prevLevel + 1 then
        ns.Toast({ kind = "levelup", title = friend .. " nåede level " .. level, text = char, class = class,
                   sound = "levelup", friend = friend })
    end
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
end

ns.CheckBossDeath = CheckBossDeath

-- =============================================================================
-- Indkommende beskeder
-- =============================================================================
local lastSyncReply = {}

local function OnAddonMessage(prefix, message)
    if prefix ~= PREFIX or not message then return end
    local t = { strsplit(";", message) }
    local kind = t[1]

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

    elseif kind == "S" or kind == "B" or kind == "W" or kind == "A" then
        HandleExtraMessage(kind, t)

    elseif kind == "Q" then
        local friend = t[2]
        if db.me and ROSTER_SET[friend] and friend ~= db.me then
            local now = time()
            if not lastSyncReply[friend] or now - lastSyncReply[friend] > 600 then
                lastSyncReply[friend] = now
                C_Timer.After(1 + math.random() * 6, RespondToSync)
            end
        end
    end
end

-- =============================================================================
-- Identitet: hvilken ven er du?
-- =============================================================================
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

local function MakeBox(frameType, parent, bg, border, name)
    local f = CreateFrame(frameType, name, parent, "BackdropTemplate")
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
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
    card.bar:SetHeight(4)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -14)

    card.name = Txt(card, "GameFontNormalLarge")
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -2)
    card.name:SetText(friend)

    card.char = Txt(card, "GameFontHighlightSmall")
    card.char:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.char:SetTextColor(0.7, 0.7, 0.76)

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

    card.deaths = Txt(card, "GameFontNormal")
    card.deaths:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -96)

    card.lootText = Txt(card, "GameFontNormal")
    card.lootText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -96)
    card.lootText:SetJustifyH("RIGHT")

    card.barBG = card:CreateTexture(nil, "ARTWORK")
    card.barBG:SetColorTexture(0.17, 0.17, 0.21, 1)
    card.barBG:SetSize(BAR_W, 6)
    card.barBG:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -116)

    card.barFill = card:CreateTexture(nil, "OVERLAY")
    card.barFill:SetHeight(6)
    card.barFill:SetPoint("TOPLEFT", card.barBG, "TOPLEFT", 0, 0)

    card.charsText = Txt(card, "GameFontHighlightSmall")
    card.charsText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -128)
    card.charsText:SetTextColor(0.7, 0.7, 0.76)

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
    ns.deathTicker:SetWordWrap(false)
    ns.deathTicker:SetSpacing(3)

    ns.lootTicker = Txt(page, "GameFontHighlightSmall")
    ns.lootTicker:SetPoint("TOPLEFT", page, "TOPLEFT", 372, y)
    ns.lootTicker:SetWidth(360)
    ns.lootTicker:SetWordWrap(false)
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
        card.name:SetTextColor(r, g, b)
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
            card.barFill:SetColorTexture(COL_EPIC[1], COL_EPIC[2], COL_EPIC[3], 1)
            card.barFill:SetWidth(math.max(1, BAR_W * (s.loot / maxLoot)))
            card.barFill:Show()
        else
            card.barFill:Hide()
        end
        card.charsText:SetText(s.chars > 0 and Plural(s.chars, "karakter", "karakterer") or "Ingen karakterer endnu")
        card.titles:SetText(TitleText(titles[s.name]))
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
    panel.sub:SetText(string.format("%s  -  %d dødsfald  -  %d rare+ loot",
        Plural(cur.chars, "karakter", "karakterer"), cur.deaths, cur.loot))
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
        ns.lootInfo:SetText(minName .. " eller bedre registreres  -  /wc4l loot uncommon|rare|epic|legendary ændrer grænsen")
    else
        ns.lootEmpty:SetText("")
        ns.lootInfo:SetText(string.format("Viser %d-%d af %d  -  %s eller bedre  -  rul med musehjulet  -  /wc4l loot uncommon|rare|epic|legendary",
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
}

local toast = { queue = {}, frame = nil, active = nil }

local function ToastFrame()
    if toast.frame then return toast.frame end
    local f = MakeBox("Button", UIParent, COL_BG, COL_GOLD, "WastedCoastToast")
    f:SetSize(430, 72)
    f:SetPoint("TOP", UIParent, "TOP", 0, -130)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(48, 48)
    f.icon:SetPoint("LEFT", f, "LEFT", 12, 0)

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
            self:SetAlpha(self.t / 0.3)
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
            row.fill:SetColorTexture(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
        else
            row.fill:SetColorTexture(r, g, b, 0.9)
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

-- =============================================================================
-- UI: hovedvindue, faner og identitetsvalg
-- =============================================================================
function ns.ShowTab(i)
    ns.tab = i
    for idx, page in ipairs(ns.pages) do page:SetShown(idx == i) end
    for idx, tb in ipairs(ns.tabs) do
        local c = (idx == i) and COL_SELECT or COL_BTN
        tb:SetBackdropColor(c[1], c[2], c[3], 1)
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
    else
        RefreshRace()
    end
end

function ns.ShowIdentityPicker()
    if not ns.picker then
        local p = MakeBox("Frame", UIParent, COL_BG, COL_GOLD, "WastedCoastPicker")
        p:SetSize(260, 66 + #ROSTER * 30 + 10)
        p:SetPoint("CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")

        local title = Txt(p, "GameFontNormalLarge")
        title:SetPoint("TOP", p, "TOP", 0, -14)
        title:SetJustifyH("CENTER")
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

local function BuildUI()
    local f = MakeBox("Frame", UIParent, COL_BG, COL_BORDER, "WastedCoastFrame")
    f:SetSize(760, 520)
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

    -- Header
    local title = Txt(f, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    title:SetText("WASTED COAST")
    title:SetTextColor(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3])

    local sub = Txt(f, "GameFontHighlightSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetTextColor(0.6, 0.6, 0.68)
    sub:SetText("WC4L  -  vi dør sammen")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    -- Faner
    ns.tabs = {}
    local labels = { "Overblik", "Scoreboard", "Karakterer", "Loot", "Instanser", "Trofæer", "Race" }
    for i, label in ipairs(labels) do
        local tb = MakeButton(f, 100, 26, label, function() ns.ShowTab(i) end)
        tb:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 104, -42)
        ns.tabs[i] = tb
    end

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(COL_BORDER[1], COL_BORDER[2], COL_BORDER[3], 1)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -74)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -74)
    line:SetHeight(1)

    -- Sider
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -82)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 36)

    ns.pages = {}
    for i = 1, #labels do
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

    -- Footer
    f.me = Txt(f, "GameFontHighlightSmall")
    f.me:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)

    local switch = MakeButton(f, 50, 20, "Skift", function() ns.ShowIdentityPicker() end)
    switch:SetPoint("LEFT", f.me, "RIGHT", 10, 0)

    local hint = Txt(f, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("RIGHT")
    hint:SetTextColor(0.5, 0.5, 0.56)
    hint:SetText("Klik på et kort for at se vennens karakterer")

    -- Opdater løbende, mens vinduet er åbent (online-status, "set for x min siden")
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 2 then
            elapsed = 0
            ns.RefreshUI()
        end
    end)
    f:SetScript("OnShow", function() ns.RefreshUI() end)

    ns.frame = f
    ns.ShowTab(1)
    f:Hide()
end

-- =============================================================================
-- Demo-data (kun lokalt, til at se hvordan det ser ud)
-- =============================================================================
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
}

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
                        class = class, level = math.random(8, 70),
                        gold = math.random(5, 4000) * 10000 + math.random(0, 99) * 100,
                        zone = DEMO_ZONES[math.random(#DEMO_ZONES)], xp = math.random(0, 99),
                    }, seen)
                    c.demo = true
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
                    level = math.random(8, 70), zone = DEMO_ZONES[math.random(#DEMO_ZONES)],
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
                    for _, b in ipairs(BOSSES[inst].list) do
                        if math.random() < 0.7 then e.boss[b] = math.random(1, 6) end
                    end
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
    if ns.RefreshUI then ns.RefreshUI() end
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
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_FLAGS_CHANGED")
-- Boss-events findes ikke i alle spilversioner: en ukendt event giver ellers en Lua-fejl
pcall(events.RegisterEvent, events, "ENCOUNTER_END")
pcall(events.RegisterEvent, events, "BOSS_KILL")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end
        InitDB()
        BuildLootPatterns()
        if RegisterPrefix then RegisterPrefix(PREFIX) end
        BuildUI()
        StartPump()
        Print("indlæst. Skriv /wc4l for at åbne vinduet.")

    elseif event == "PLAYER_LOGIN" then
        -- Vent lidt, så guild/party-info er klar
        C_Timer.After(6, function()
            if db.me then
                SendHeartbeat()
                RequestSync()
                ns.InitAchievements()
            else
                ns.ShowIdentityPicker()
            end
        end)
        C_Timer.NewTicker(60, SendHeartbeat)
        C_Timer.NewTicker(2, CheckWipe)
        OnZoneChanged()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if db then OnZoneChanged() end

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        lastCombat = GetTime()

    elseif event == "PLAYER_XP_UPDATE" then
        TouchMe()

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
    end
end)

-- =============================================================================
-- Slash-kommandoer
-- =============================================================================
SLASH_WASTEDCOAST1 = "/wc4l"
SLASH_WASTEDCOAST2 = "/wastedcoast"
SlashCmdList["WASTEDCOAST"] = function(input)
    local cmd, arg = strsplit(" ", strtrim((input or ""):lower()), 2)

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.frame:SetShown(not ns.frame:IsShown())
    elseif cmd == "jeg" then
        ns.ShowIdentityPicker()
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
                ".  Test en lyd med |cffffd100/wc4l sound <event>|r (" .. table.concat(SOUND_EVENTS, ", ") .. ").")
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
                " eller bedre. Skift med |cffffd100/wc4l loot uncommon|rare|epic|legendary|r.")
        end
    elseif cmd == "sync" then
        SendHeartbeat()
        RequestSync()
        Print("Anmoder vennerne om at sende deres data...")
    elseif cmd == "demo" then
        if arg == "slut" or arg == "clear" then
            ClearDemo()
            Print("Demo-data er fjernet.")
        else
            MakeDemo()
            Print("Demo-data lagt ind (kun lokalt). Fjern det igen med |cffffd100/wc4l demo slut|r.")
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
            Print("Skriv |cffffd100/wc4l reset ja|r for at slette alle data.")
        end
    else
        Print("Kommandoer:")
        print("  /wc4l              - vis/skjul vinduet")
        print("  /wc4l jeg          - vælg, hvem du er")
        print("  /wc4l loot         - vis/skift minimumskvalitet for loot (uncommon, rare, epic, legendary)")
        print("  /wc4l demo         - fyld med demo-data (|cffffd100demo slut|r fjerner det)")
        print("  /wc4l sync         - hent data fra vennerne igen")
        print("  /wc4l sound        - slå lyd til/fra  (|cffffd100sound <event>|r tester en lyd)")
        print("  /wc4l toast        - slå popups (online, wipe, level) til/fra")
        print("  /wc4l testtoast    - vis eksempler på popups")
        print("  /wc4l announce     - slå chat-beskeder til/fra")
        print("  /wc4l test         - lav et falsk dødsfald")
        print("  /wc4l testloot     - lav en falsk loot win")
        print("  /wc4l reset ja     - slet alle data")
    end
end
