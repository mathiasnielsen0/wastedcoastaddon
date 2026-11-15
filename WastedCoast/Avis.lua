local _, ns = ...
local L = ns.L

-- =============================================================================
-- Wasted Coast Tidende (v0.30): dagens sladder som en avis
--   * Avisen åbner ved hvert login (ikke ved /reload eller zone-skift) og opsummerer alt, der
--     er sket i banden i dag, fra kl. 00.00 i din lokale tid til nu. /wc4ever avis viser den igen,
--     og Sjov > Avisen viser dagens overskrifter i hovedvinduet.
--   * Hver historie har en betingelse i dagens data og en vægt (se Tekstbanken nedenfor). Den
--     tungeste bliver forsiden, resten fordeles på rubrikkerne: Dødsfald, Børsen, Levels og
--     karriere, Kapløbet (level-løbet) og Skandaler. Højst 3 historier om samme ven, så længe der er
--     andet at skrive om. En tom rubrik får en reservetekst.
--   * Derudover: Skammens hat (hvem, hvor længe og fra hvem), horoskop til hver ven (tegnet følger
--     klassen, teksten vennens vigtigste historie), små annoncer og vejret (zonen med flest døde).
--   * "Kopiér til Discord" giver avisen som ren tekst, klar til Ctrl+C.
--   * Avisen sender ingen beskeder. Den bygger på det, addonet allerede har og synker: dødsfald,
--     loot, Need-politiet, levels, guld, guild bank, stomi, prutter, gz, rare mobs, trofæer og
--     sladderens målinger (professions, reputation, gear, spilletid, instanser og rolls).
--   * Det, der ikke har et tidspunkt (levels, professions, spilletid ...), sammenlignes med et
--     øjebliksbillede, der tages første gang addonet kører på en ny dato. Mens du er online,
--     noterer avisen også, hvem der er online om natten og i arbejdstiden, hvor mange der var
--     online på én gang, og hvem der er i samme zone.
--   * Demo-data kommer aldrig i avisen. Daglig sladder (Gossip.lua) popper ikke op, når avisen er slået til.
--
-- db.avis = { day = dato (ÅÅÅÅ-MM-DD) for øjebliksbilledet, n = avisens nummer,
--             base = { lv, nc, chars, hk, bank, seen, st }  øjebliksbilledet fra dagens start,
--             hist = { [dato] = { t, lv = { ven -> level + XP/100 } } }  (de seneste 14 dage, til kapløbets tempo),
--             on = { ven -> { night, work } }, peak = { n, t }, duo = { ["A|B"] = { s, z } } }
-- db.settings.avis = false: avisen åbner ikke af sig selv ved login (/wc4ever avis virker stadig)
-- =============================================================================

local C = ns.core
local ROSTER, ROSTER_SET = C.ROSTER, C.ROSTER_SET
local Print, Name = C.Print, C.Name

local A = {}
ns.Avis = A

A.SHOW_DELAY = 30        -- sekunder efter login, så vennernes data er nået frem
A.PER_FRIEND = 3         -- historier om samme ven, før de andre får plads
A.PER_SECTION = 5
A.HIST_DAYS = 14
A.GOLD_MIN = 50 * 10000
A.MISSING_DAYS = 4

local PROF_MAX = (C.MAX_LEVEL or 60) >= 70 and 375 or 300
local STANDING = { [6] = "Honored", [7] = "Revered", [8] = "Exalted" }

local function DB()
    local db = WastedCoastDB
    db.avis = db.avis or {}
    local a = db.avis
    a.base = a.base or {}
    a.hist = a.hist or {}
    a.on = a.on or {}
    a.duo = a.duo or {}
    return db, a
end

local function IsDemo(e)
    return e.demo or e.d or (type(e.id) == "string" and e.id:find("^demo%-") ~= nil)
end

local function Today(t) return date("%Y-%m-%d", t or time()) end

-- Kl. 00.00 i dag (lokal tid), regnet ud fra klokken, så det også virker uden time(tabel)
local function Midnight(now)
    now = now or time()
    local t = date("*t", now)
    return now - ((t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0))
end
A.Midnight = Midnight

local function Clock(t) return date(L("%H.%M"), t) end

local function Duration(secs)
    secs = math.max(60, secs or 0)
    if secs < 3600 then return math.floor(secs / 60) .. L(" min") end
    if secs < 86400 then
        local h = math.floor(secs / 3600)
        return h .. (h == 1 and L(" time") or L(" timer"))
    end
    local d = math.floor(secs / 86400)
    return d .. (d == 1 and L(" dag") or L(" dage"))
end

-- Samme tekst hele dagen: valget afhænger af datoen og nøglen, ikke af tilfældigheder
local function Hash(s)
    local h = 7
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
    return h
end
local function PD(key, list) return list[Hash(Today() .. key) % #list + 1] end

local function Red(s) return "|cff8a1c12" .. tostring(s) .. "|r" end
local DARK = { [3] = "0a4f9e", [4] = "5e2590", [5] = "a34700" }
local function Item(ev)
    local name = (ns.FixLootName and ns.FixLootName(ev)) or ev.name or "?"
    return "|cff" .. (DARK[ev.quality] or "3a2f22") .. "[" .. tostring(name) .. "]|r"
end
local function Killer(ev)
    if not ev.killer or ev.killer == "" then return "?" end
    return L(ev.killer) or ev.killer
end
local function EnvOf(ev)
    for k, v in pairs(C.ENV_NAMES) do
        if ev.killer == v or ev.ability == v then return k end
    end
end

-- Alle venner med karakterer (uden demo): højeste level med XP, klasse, zone, karakterer og honor kills
local function Friends()
    local out = {}
    for _, name in ipairs(ROSTER) do
        local info = WastedCoastDB.friends[name]
        local e = { lvl = 0, ls = 0, nc = 0, hk = 0, chars = {} }
        local seenBest
        for cn, c in pairs((info and info.chars) or {}) do
            if type(c) == "table" and not c.demo then
                e.nc = e.nc + 1
                e.chars[cn] = true
                local lv = tonumber(c.level) or 0
                local xp = ns.XPPct and ns.XPPct(lv, c.xp)
                local ls = lv + (xp or 0) / 100
                if ls > e.ls then e.ls, e.lvl, e.xp, e.cls = ls, lv, xp, c.class end
                if not seenBest or (c.seen or 0) > seenBest then seenBest, e.zone, e.cls2 = c.seen or 0, c.zone, c.class end
                if type(c.honor) == "table" and tonumber(c.honor.k) then e.hk = e.hk + tonumber(c.honor.k) end
            end
        end
        e.cls = e.cls or e.cls2
        if e.nc > 0 then out[name] = e end
    end
    return out
end
A.Friends = Friends

local function Snapshot()
    local db = WastedCoastDB
    local s = { lv = {}, nc = {}, chars = {}, hk = {}, bank = {}, seen = {}, st = (ns.GossipStats and ns.GossipStats()) or {} }
    for name, e in pairs(Friends()) do
        s.lv[name], s.nc[name], s.chars[name], s.hk[name] = e.ls, e.nc, e.chars, e.hk
    end
    for _, name in ipairs(ROSTER) do
        local b = db.bank and db.bank[name]
        if type(b) == "table" then
            s.bank[name] = { rep = b.rep or 0, wg = b.wg or 0, di = b.di or 0, grep = b.grep or 0 }
        end
        s.seen[name] = C.LastSeen(name)
    end
    return s
end

-- Første gang på en ny dato: tag et øjebliksbillede, som dagens tal sammenlignes med
function A.EnsureDay()
    local db, a = DB()
    local today = Today()
    if a.day == today then return false end
    a.day = today
    a.base = Snapshot()
    a.on, a.peak, a.duo = {}, nil, {}
    a.hist[today] = { t = Midnight(), lv = a.base.lv }
    local keys = {}
    for k in pairs(a.hist) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys - A.HIST_DAYS do a.hist[keys[i]] = nil end
    a.n = (a.n or 0) + 1
    return true
end

-- Hvert minut: hvem er online om natten og i arbejdstiden, hvor mange på én gang, og hvem er sammen
function A.Track()
    local db, a = DB()
    if not db.me then return end
    A.EnsureDay()
    local now = time()
    local t = date("*t", now)
    local fr = Friends()
    -- En ven, der ikke var med i øjebliksbilledet (ny i gruppen eller ingen data endnu), får sit nu
    local base = a.base
    if base and base.lv then
        for name, e in pairs(fr) do
            if not base.lv[name] then
                base.lv[name], base.chars[name], base.hk[name] = e.ls, e.chars, e.hk
                if base.nc then base.nc[name] = e.nc end
            end
        end
    end
    local online, zones = 0, {}
    for _, name in ipairs(ROSTER) do
        if C.IsOnline(name) then
            online = online + 1
            local o = a.on[name] or {}
            a.on[name] = o
            if t.hour >= 2 and t.hour < 5 and not o.night then o.night = now end
            if t.wday >= 2 and t.wday <= 6 and t.hour >= 9 and t.hour < 15 and not o.work then o.work = now end
            local z = fr[name] and fr[name].zone
            if type(z) == "string" and z ~= "" then
                zones[z] = zones[z] or {}
                table.insert(zones[z], name)
            end
        end
    end
    if online > ((a.peak and a.peak.n) or 0) then a.peak = { n = online, t = now } end
    for z, list in pairs(zones) do
        table.sort(list)
        for i = 1, #list do
            for j = i + 1, #list do
                local k = list[i] .. "|" .. list[j]
                local p = a.duo[k] or { s = 0 }
                p.s, p.z = p.s + 60, z
                a.duo[k] = p
            end
        end
    end
end

-- =============================================================================
-- Tekstbanken: tegn, kicker-navne, horoskoper og faste fraser
-- =============================================================================
A.SECTIONS = { "dod", "bors", "lvl", "kap", "skan" }
local SEC_NAME = ns.LT({ dod = "Dødsfald", bors = "Børsen", lvl = "Levels og karriere", kap = "Kapløbet", skan = "Skandaler" })
local SEC_KICK = ns.LT({ dod = "DØDSFALD", bors = "BØRSEN", lvl = "LEVELS OG KARRIERE", kap = "KAPLØBET", skan = "SKANDALER" })
local SEC_EMPTY = ns.LT({
    dod = "Ingen døde i dag. Ikke én. Hvem er I, og hvad har I gjort ved Wasted Coast?",
    bors = "Stille på børsen. Ingen fandt noget af værdi i dag.",
    lvl = "Ingen levels, ingen skills, ingen rep. Karrieren holder fridag.",
    kap = "Ingen bevægelse i kapløbet i dag.",
    skan = "Ingen stomi, ingen prutter. Det er næsten kedeligt.",
})
A.SEC_NAME = SEC_NAME

local SIGNS = ns.LT({
    WARRIOR = "Tyren", PALADIN = "Lyset", HUNTER = "Kæledyret", ROGUE = "Skyggen", PRIEST = "Bønnen",
    SHAMAN = "Totemet", MAGE = "Vandflasken", WARLOCK = "Dæmonen", DRUID = "Bjørnen",
    DEATHKNIGHT = "Kisten", MONK = "Tekoppen", DEMONHUNTER = "Bindet", EVOKER = "Ægget",
})

local HORO = ns.LT({
    hat = { "Stjernerne står i dit dødshus. Bliv i byen i dag.", "Hatten klæder dig. Det er desværre ikke en kompliment.",
            "Jupiter siger: gå ikke tæt på kanter i dag." },
    stomi = { "Sig nej til alt i dag, især til gratis gaver.", "Posen er et tegn. Lyt til den.",
              "Venus står i fordøjelsens hus. Det forklarer meget." },
    deaths = { "Saturn er i %s. Tag en anden vej.", "Undgå %s. Det gør stjernerne også.",
               "Mars siger, at %s ikke er dit sted." },
    levels = { "Mange levels i dag. Stjernerne siger: drik vand.", "Du flyver afsted. Husk at kigge op en gang imellem.",
               "Merkur siger: en pause er ikke en svaghed." },
    epic = { "En lilla ting har fundet dig. Pas på den, den er ny.", "Lykken smiler. Nyd det, før den holder op.",
             "Stjernerne er misundelige. Det er vi andre også." },
    cop = { "Tag dit gear på. Bare én gang.", "Need-politiet ser dig. Det gør stjernerne også.",
            "Grådighed er en vej, men den ender i Need-politiets bil." },
    gold = { "Guldet flyder. Nogen vil låne, før ugen er omme.", "Pengene brænder i lommen. Lad dem brænde lidt endnu.",
             "Auktionshuset kalder. Svar ikke." },
    missing = { "Stjernerne kan ikke se dig. Det kan vi heller ikke.", "Månen spørger, hvor du er blevet af.",
                "Et login ville gøre underværker for dit horoskop." },
    snail = { "Mars bevæger sig hurtigere end dig. Det gør alt.", "Tålmodighed er en dyd. Du har mange dyder.",
              "Et level venter derude. Det har ventet længe." },
    none = { "En stille dag venter. Brug den på at reparere dit gear.", "Stjernerne har intet at sige. Det er et godt tegn.",
             "Pluto siger: gør noget dumt, så der er noget at skrive om.", "Du møder en murloc. Den er ikke din ven." },
})

local TAILS = ns.LT({
    shame = { "Pinligt.", "Det bliver aldrig glemt.", "Spirit healeren grinte." },
    many = { "Spirit healeren kender navnet nu.", "Repair-regningen er ikke for sarte sjæle.", "Kirkegården overvejer at give stamkundekort." },
    gank = { "Hævnen er sød.", "Måske på tide at kigge sig over skulderen.", "Den anden faction siger tak for kampen." },
    epic = { "Screenshot eller det skete ikke.", "Resten af os kan bare pakke sammen.", "Misundelse er en grim ting. Vi er alle misundelige." },
    rare = { "Blå er det nye lilla.", "Ikke epic, men vi tager den.", "Pænt. Rigtig pænt." },
    levels = { "Græsset blev ikke slået i dag.", "Har personen overhovedet sovet?", "Respekt. Og lidt bekymring." },
    played = { "Stolen er formet efter personen nu.", "Familien har meldt personen savnet.", "Har personen et job?" },
    stomi = { "Sagde ja uden at tænke sig om.", "Posen sidder der i 24 timer.", "Det var en gratis gave. Troede personen." },
    fart = { "Ingen respekt for de afdøde.", "Kirkegården lugter stadig.", "Spirit healeren har klaget." },
    gold = { "Hvem skal give en omgang?", "Auktionshuset græder.", "Lån ud til en flyvende mount?" },
    gear = { "Nogen har været i bossernes lommer.", "Gammelt gear til salg, spørg i guilden.", "Det skinner helt ud til vejen." },
    wipe = { "Tanken siger, det var healerens skyld.", "Det er ikke wipes, det er træning.", "Næste gang læser vi bossens taktik." },
})
A.HORO, A.TAILS = HORO, TAILS

local WEEKDAYS = ns.LT({ "søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag" })
local MONTHS = ns.LT({ "januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september", "oktober", "november", "december" })

-- =============================================================================
-- Dagens avis: alle historier, hvis betingelse er opfyldt
-- =============================================================================
function A.Collect()
    local db, a = DB()
    A.EnsureDay()
    local now, since = time(), Midnight()
    local base = a.base or {}
    local P = { stories = {}, facts = {}, stats = { deaths = 0, levels = 0, loot = 0, farts = 0 }, since = since, now = now }
    local facts = P.facts
    local function F(f) facts[f] = facts[f] or {} return facts[f] end
    local function add(sec, w, f, h, t) P.stories[#P.stories + 1] = { sec = sec, w = w, f = f, h = h, t = t } end
    local fr = Friends()
    local function N(f) return Name(f) end

    -- ---------------------------------------------------------------- Dødsfald
    local today, byF, killerOf, zoneN, zoneKill, allDeaths = {}, {}, {}, {}, {}, {}
    for _, ev in ipairs(db.events or {}) do
        if type(ev) == "table" and not IsDemo(ev) then
            local f = C.EventFriend(ev)
            if f then
                -- Tal og tekst efterprøves, så et ødelagt dødsfald ikke vælter avisen
                -- (false, ikke nil, så den ødelagte værdi ikke kommer igennem __index)
                ev = setmetatable({ level = tonumber(ev.level) or false, klvl = tonumber(ev.klvl) or false, time = tonumber(ev.time) or false,
                                    zone = type(ev.zone) == "string" and ev.zone or false,
                                    killer = type(ev.killer) == "string" and ev.killer or false }, { __index = ev })
                allDeaths[#allDeaths + 1] = { ev = ev, f = f }
                if (ev.time or 0) >= since and (ev.time or 0) <= now + 60 then
                    today[#today + 1] = { ev = ev, f = f, env = EnvOf(ev) }
                end
            end
        end
    end
    table.sort(today, function(x, y) return (x.ev.time or 0) < (y.ev.time or 0) end)
    table.sort(allDeaths, function(x, y) return (x.ev.time or 0) < (y.ev.time or 0) end)
    P.stats.deaths = #today
    local mobVictims = {}
    for _, d in ipairs(today) do
        local ev, f = d.ev, d.f
        byF[f] = (byF[f] or 0) + 1
        F(f).deaths = byF[f]
        F(f).zone = ev.zone
        local z = ev.zone
        if type(z) == "string" and z ~= "" then
            zoneN[z] = (zoneN[z] or 0) + 1
            if not d.env and ev.pvp ~= true and ev.killer and ev.killer ~= "" and ev.killer ~= "Ukendt" then
                zoneKill[z] = zoneKill[z] or {}
                zoneKill[z][ev.killer] = (zoneKill[z][ev.killer] or 0) + 1
            end
        end
        if not d.env and ev.pvp ~= true and ev.killer and ev.killer ~= "" and ev.killer ~= "Ukendt" then
            killerOf[f] = killerOf[f] or {}
            killerOf[f][ev.killer] = (killerOf[f][ev.killer] or 0) + 1
            mobVictims[ev.killer] = mobVictims[ev.killer] or {}
            mobVictims[ev.killer][f] = true
        end
    end

    -- Den pinligste: en mob langt under ens eget level
    local worst, worstGap
    for _, d in ipairs(today) do
        local kl = tonumber(d.ev.klvl)
        if not d.env and d.ev.pvp ~= true and kl and kl > 0 and d.ev.level then
            local gap = d.ev.level - kl
            if gap >= 5 and (not worstGap or gap > worstGap) then worst, worstGap = d, gap end
        end
    end
    if worst then
        local ev = worst.ev
        add("dod", worstGap >= 8 and 95 or 60, worst.f,
            string.format(worstGap >= 8 and L("Skandale i %s") or L("Ydmygelse i %s"), ev.zone or "?"),
            string.format(L("%s (level %d) blev slået ihjel af en level %d %s. %s"), N(worst.f), ev.level, tonumber(ev.klvl), Killer(ev),
                PD("shame" .. worst.f, TAILS.shame)))
    end
    -- Miljøet: én historie pr. slags
    local envDone = {}
    for _, d in ipairs(today) do
        local k, ev, f = d.env, d.ev, d.f
        if k and not envDone[k] then
            envDone[k] = true
            local z = ev.zone or "?"
            if k == "Falling" then
                add("dod", 70, f, L("Tyngdekraften slår til"), string.format(L("%s faldt ned og døde i %s. Tyngdekraften: 1, %s: 0."), N(f), z, N(f)))
            elseif k == "Drowning" then
                add("dod", 70, f, L("Drama i dybet"), string.format(L("%s glemte at trække vejret i %s. Fiskene siger tak."), N(f), z))
            elseif k == "Fatigue" then
                add("dod", 72, f, L("Forsvundet på havet"), string.format(L("%s svømmede for langt ud fra %s og kom ikke tilbage."), N(f), z))
            elseif k == "Fire" or k == "Lava" then
                add("dod", 70, f, string.format(L("%s blev grillet"), N(f)), string.format(L("%s døde af %s i %s. Ingen mob, bare naturen."), N(f), L(C.ENV_NAMES[k]):lower(), z))
            else
                add("dod", 66, f, L("Slimet ihjel"), string.format(L("%s døde af %s i %s. Ingen mob, bare naturen."), N(f), L(C.ENV_NAMES[k]):lower(), z))
            end
        end
    end
    -- Mange dødsfald og samme dræber
    for f, n in pairs(byF) do
        local killer, kn = nil, 0
        for k, c in pairs(killerOf[f] or {}) do if c > kn or (c == kn and k < killer) then killer, kn = k, c end end
        if n >= 6 then
            add("dod", 85, f, L("Spirit healeren tager fri"), string.format(L("%s døde %s gange i dag. Spirit healeren har bedt om en pause."), N(f), Red(n)))
        elseif n >= 3 then
            local tail = (killer and kn >= 2) and string.format(L(" %d af gangene var det %s."), kn, L(killer)) or ""
            add("dod", 55 + n, f, string.format(L("%s døde %d gange"), N(f), n),
                string.format(L("%s har mødt spirit healeren %s gange i dag.%s %s"), N(f), Red(n), tail, PD("many" .. f, TAILS.many)))
        elseif killer and kn >= 2 then
            add("dod", 55, f, string.format(L("%s har %s i kikkerten"), L(killer), N(f)),
                string.format(L("%s er død til %s to gange i dag. Det er personligt nu."), N(f), L(killer)))
        end
    end
    -- Én mob, flere ofre
    for mob, set in pairs(mobVictims) do
        local list = {}
        for f in pairs(set) do list[#list + 1] = f end
        if #list >= 2 then
            table.sort(list)
            add("dod", 65, nil, string.format(L("%s terroriserer banden"), L(mob)),
                string.format(L("%s har taget både %s og %s i dag. Nogen må gøre noget."), L(mob), N(list[1]), N(list[2])))
        end
    end
    -- Dobbelt-tragedie: to venner i samme zone inden for 2 minutter
    for i = 2, #today do
        local x, y = today[i - 1], today[i]
        if x.f ~= y.f and x.ev.zone and x.ev.zone == y.ev.zone and math.abs((y.ev.time or 0) - (x.ev.time or 0)) <= 120 then
            add("dod", 75, nil, string.format(L("Dobbelt-tragedie i %s"), x.ev.zone),
                string.format(L("%s og %s døde med %d sekunders mellemrum. Dårligt teamwork."), N(x.f), N(y.f), math.abs((y.ev.time or 0) - (x.ev.time or 0))))
            break
        end
    end
    -- Den enkelte død: lige efter et ding, i det nye tøj, om natten, på max level, den første
    local doneF = {}
    for _, d in ipairs(today) do
        local ev, f = d.ev, d.f
        local la = db.levelAt and db.levelAt[f]
        if not doneF[f .. "ding"] and la and not la.g and ev.level == la.l and (ev.time or 0) - (la.t or 0) >= 0 and (ev.time or 0) - (la.t or 0) <= 600 then
            doneF[f .. "ding"] = true
            add("dod", 78, f, L("Kort glæde"), string.format(L("%s nåede level %d og døde %s senere."), N(f), la.l, Duration((ev.time or 0) - la.t)))
        end
        if not doneF[f .. "loot"] then
            for _, lv in ipairs(db.loot or {}) do
                if type(lv) == "table" and not IsDemo(lv) and (lv.quality or 0) >= 3 and lv.time and lv.time <= (ev.time or 0)
                    and (ev.time or 0) - lv.time <= 900 and C.EventFriend({ friend = lv.friend, name = lv.char }) == f then
                    doneF[f .. "loot"] = true
                    add("dod", 76, f, L("Døde i det nye tøj"), string.format(L("%s nåede at have %s i %s. Så kom døden."), N(f), Item(lv), Duration((ev.time or 0) - lv.time)))
                    break
                end
            end
        end
        local hour = tonumber(date("%H", ev.time or now)) or 12
        if not doneF.night and hour >= 1 and hour < 5 then
            doneF.night = true
            add("dod", 50, f, string.format(L("Natten tog %s"), N(f)),
                string.format(L("Kl. %s i %s. Burde have ligget i sin seng, ikke på en kirkegård."), Clock(ev.time), ev.zone or "?"))
        end
        if not doneF[f .. "max"] and (ev.level or 0) >= C.MAX_LEVEL then
            doneF[f .. "max"] = true
            add("dod", 82, f, L("Veteranen falder"), string.format(L("%s, level %d, troede at max level gjorde udødelig. Det gør det ikke."), N(f), ev.level))
        end
        if not doneF[f .. "first"] and (ev.level or 0) >= 10 and ev.name then
            local earlier = false
            for _, o in ipairs(allDeaths) do
                if o.ev ~= ev and o.ev.name == ev.name and (o.ev.time or 0) < (ev.time or 0) then earlier = true break end
            end
            if not earlier then
                doneF[f .. "first"] = true
                add("dod", 58, f, string.format(L("%s mister sin uskyld"), N(f)),
                    string.format(L("%s døde for første gang på level %d. Velkommen til klubben."), N(f), ev.level))
            end
        end
    end
    -- PvP
    local ganked, gankers, gankLvl = {}, {}, {}
    for _, d in ipairs(today) do
        if d.ev.pvp == true then
            local f, k = d.f, d.ev.killer or "?"
            ganked[f] = (ganked[f] or 0) + 1
            gankers[f] = gankers[f] or {}
            gankers[f][k] = (gankers[f][k] or 0) + 1
            local kl = tonumber(d.ev.klvl)
            if kl and d.ev.level and kl - d.ev.level >= 10 and not gankLvl[f] then gankLvl[f] = d end
        end
    end
    for f, n in pairs(ganked) do
        local who, wn = nil, 0
        for k, c in pairs(gankers[f]) do if c > wn or (c == wn and k < who) then who, wn = k, c end end
        if wn >= 2 then
            add("dod", 68, f, string.format(L("%s jagter %s"), who, N(f)),
                string.format(L("%s har ganket %s %d gange i dag. Det er en fejde nu."), who, N(f), wn))
        elseif gankLvl[f] then
            local ev = gankLvl[f].ev
            add("dod", 52, f, L("David mødte Goliat"),
                string.format(L("%s (level %d) havde ingen chance mod en level %d spiller i %s."), N(f), ev.level, tonumber(ev.klvl), ev.zone or "?"))
        else
            local z
            for _, d in ipairs(today) do if d.f == f and d.ev.pvp == true then z = d.ev.zone end end
            add("dod", 45, f, string.format(L("Baghold i %s"), z or "?"),
                string.format(L("%s blev ganket af %s. %s"), N(f), who or "?", PD("gank" .. f, TAILS.gank)))
        end
    end
    if #today >= 10 then
        add("dod", 40, nil, L("Blodig dag i Wasted Coast"), string.format(L("I alt %d dødsfald i dag. Spirit healerne har haft travlt."), #today))
    end

    -- ---------------------------------------------------------------- Børsen
    local epics, rareBy, rareList = {}, {}, {}
    for _, ev in ipairs(db.loot or {}) do
        if type(ev) == "table" and (ev.time or 0) >= since and not IsDemo(ev) then
            local f = C.EventFriend({ friend = ev.friend, name = ev.char })
            if f then
                P.stats.loot = P.stats.loot + 1
                if (ev.quality or 0) >= 4 then
                    epics[#epics + 1] = { ev = ev, f = f }
                    F(f).epic = true
                else
                    rareBy[f] = (rareBy[f] or 0) + 1
                    rareList[#rareList + 1] = { ev = ev, f = f }
                end
            end
        end
    end
    table.sort(epics, function(x, y)
        if (x.ev.quality or 0) ~= (y.ev.quality or 0) then return (x.ev.quality or 0) > (y.ev.quality or 0) end
        return (x.ev.time or 0) > (y.ev.time or 0)
    end)
    for i, e in ipairs(epics) do
        if i > 3 then break end
        local where = (e.ev.zone and e.ev.zone ~= "") and (L(" i ") .. e.ev.zone) or ""
        if (e.ev.quality or 0) >= 5 then
            add("bors", 100, e.f, L("Legendarisk!"), string.format(L("%s fik %s%s. Det her bliver der talt om i årevis."), N(e.f), Item(e.ev), where))
        else
            local first = true
            for _, o in ipairs(db.loot or {}) do
                if o ~= e.ev and not IsDemo(o) and (o.quality or 0) >= 4 and (o.time or 0) < (e.ev.time or 0)
                    and C.EventFriend({ friend = o.friend, name = o.char }) == e.f then first = false break end
            end
            if first then
                add("bors", 74, e.f, string.format(L("Første epic til %s"), N(e.f)),
                    string.format(L("%s fik %s%s. Det er den første lilla ting nogensinde."), N(e.f), Item(e.ev), where))
            else
                add("bors", 66 - i, e.f, string.format(L("%s i lilla"), N(e.f)),
                    string.format(L("%s fik %s%s. %s"), N(e.f), Item(e.ev), where, PD("epic" .. i, TAILS.epic)))
            end
        end
    end
    table.sort(rareList, function(x, y) return (x.ev.time or 0) > (y.ev.time or 0) end)
    local named, shown = {}, 0
    for f, n in pairs(rareBy) do
        if n >= 3 then
            local ex
            for _, r in ipairs(rareList) do if r.f == f then ex = r.ev break end end
            add("bors", 34, f, L("Tasken er snart fuld"), string.format(L("%s samlede %d rare items op, bl.a. %s."), N(f), n, Item(ex)))
            named[f] = true
        end
    end
    for _, r in ipairs(rareList) do
        if shown >= 2 then break end
        if not named[r.f] then
            named[r.f] = true
            shown = shown + 1
            add("bors", 31 - shown, r.f, string.format(L("Blåt held til %s"), N(r.f)),
                string.format(L("%s scorede %s%s. %s"), N(r.f), Item(r.ev), (r.ev.zone and r.ev.zone ~= "") and (L(" i ") .. r.ev.zone) or "", PD("rare" .. r.f, TAILS.rare)))
        end
    end
    -- Need-politiet
    local cops = {}
    for _, e in ipairs(db.needShame or {}) do
        if type(e) == "table" and (e.time or 0) >= since and not e.demo and ROSTER_SET[e.friend] then cops[#cops + 1] = e end
    end
    if #cops > 0 then
        local e = cops[#cops]
        F(e.friend).cop = e
        add("bors", 42, e.friend, string.format(L("Need-politiet anholder %s"), N(e.friend)),
            string.format(L("%s er anholdt for %s, der %s."), N(e.friend), Item({ quality = e.quality, name = e.name }),
                e.why == "gone" and L("blev solgt uden at være brugt") or L("aldrig er blevet taget på")))
    end
    -- Sladderens målinger: rolls, need/greed/pass, gear (sammenlignet med dagens start)
    local cur = (ns.GossipStats and ns.GossipStats()) or {}
    local bst = base.st or {}
    for _, f in ipairs(ROSTER) do
        local b, n = bst[f], cur[f]
        if b and n then
            if b.rolls and n.rolls and n.rolls - b.rolls >= 5 and (n.wins or 0) == (b.wins or 0) then
                add("bors", 29, f, string.format(L("RNG hader %s"), N(f)), string.format(L("%s rullede %d gange i dag og vandt ingenting."), N(f), n.rolls - b.rolls))
            end
            if b.nr and n.nr and b.gr and n.gr then
                local dn, dg = n.nr - b.nr, n.gr - b.gr
                if dn >= 5 and dg == 0 then
                    add("bors", 31, f, L("Need-goblin"), string.format(L("%s trykkede Need %d gange og Greed ikke én eneste gang."), N(f), dn))
                elseif dn >= 5 and dn >= dg * 3 then
                    add("bors", 28, f, L("Need-politiet kigger med"), string.format(L("%s needede %d gange og greedede kun %d."), N(f), dn, dg))
                end
            end
            if b.pr and n.pr and n.pr - b.pr >= 5 then
                add("bors", 21, f, L("En helgen blandt goblins"), string.format(L("%s passede %d gange. Wasted Coasts mest gavmilde sjæl."), N(f), n.pr - b.pr))
            end
            if b.il and n.il and n.il - b.il >= 3 then
                add("bors", 37, f, string.format(L("%s skinner"), N(f)),
                    string.format(L("%s steg %.1f item levels til %.1f. %s"), N(f), n.il - b.il, n.il, PD("gear" .. f, TAILS.gear)))
            end
        end
    end
    -- Guld
    if ns.GoldTotalAt then
        local up, upN, down, downN = nil, 0, nil, 0
        for _, f in ipairs(ROSTER) do
            local b, known = ns.GoldTotalAt(f, since, true)
            local last = known and ns.GoldTotalAt(f, now, true)
            if b and last then
                local diff = last - b
                if diff > upN then up, upN = f, diff end
                if -diff > downN then down, downN = f, -diff end
            end
        end
        if up and upN >= A.GOLD_MIN then
            F(up).goldUp = true
            add("bors", 32, up, string.format(L("%s er rig"), N(up)), string.format(L("%s tjente %s i dag. %s"), N(up), C.FormatGold(upN), PD("gold" .. up, TAILS.gold)))
        end
        if down and downN >= A.GOLD_MIN then
            F(down).goldDown = true
            add("bors", 31, down, L("Hvor blev pengene af?"), string.format(L("%s brugte %s i dag. Det må have været noget vigtigt. Eller repairs."), N(down), C.FormatGold(downN)))
        end
    end
    -- Guild bank og repair
    for _, f in ipairs(ROSTER) do
        local b, n = base.bank and base.bank[f], db.bank and db.bank[f]
        if b and type(n) == "table" then
            local rep, wg, di, grep = (n.rep or 0) - b.rep, (n.wg or 0) - b.wg, (n.di or 0) - b.di, (n.grep or 0) - b.grep
            if wg >= 10 * 10000 then
                add("bors", 36, f, L("Hvem tømte banken?"), string.format(L("%s hævede %s fra guild banken. Revisoren er tilkaldt."), N(f), C.FormatGold(wg)))
            end
            if grep >= 10000 then
                add("bors", 33, f, L("På fællesskabets regning"), string.format(L("%s lod guild banken betale %s i repairs."), N(f), C.FormatGold(grep)))
            elseif rep >= 5 * 10000 then
                add("bors", 30, f, L("Repair-chok"), string.format(L("%s brugte %s på repairs i dag. Smeden siger tak."), N(f), C.FormatGold(rep)))
            end
            if di >= 5 then
                add("bors", 22, f, L("Gavmildhed i banken"), string.format(L("%s lagde %d ting i guild banken."), N(f), di))
            end
        end
    end

    -- ---------------------------------------------------------------- Levels og karriere
    for _, f in ipairs(ROSTER) do
        local e, b = fr[f], base.lv and base.lv[f]
        if e and b then
            local g = e.lvl - math.floor(b)
            if g > 0 then
                P.stats.levels = P.stats.levels + g
                F(f).levels = g
                if e.lvl >= C.MAX_LEVEL then
                    add("lvl", 100, f, string.format(L("%s er i mål"), N(f)), string.format(L("%s ramte max level %d! Nu begynder det rigtige spil."), N(f), e.lvl))
                elseif g >= 3 then
                    add("lvl", 73, f, string.format(L("%s pløjede sig gennem %d levels"), N(f), g),
                        string.format(L("%s gik fra level %d til %d i dag. %s"), N(f), e.lvl - g, e.lvl, PD("levels" .. f, TAILS.levels)))
                elseif e.lvl % 10 == 0 then
                    add("lvl", 44, f, L("Rund fødselsdag"), string.format(L("%s fylder %d. Tillykke, du er voksen nu."), N(f), e.lvl))
                elseif g == 2 then
                    add("lvl", 52, f, string.format(L("%s tog to levels"), N(f)), string.format(L("%s er nu level %d."), N(f), e.lvl))
                else
                    add("lvl", 40, f, string.format(L("%s nåede level %d"), N(f), e.lvl), string.format(L("Et skridt tættere på %d."), C.MAX_LEVEL))
                end
            end
        end
    end
    -- Gz efter et ding
    local gzLog = (db.gz and db.gz.log) or {}
    local gzGiven = {}
    for _, g in ipairs(gzLog) do
        if type(g) == "table" and (g.t or 0) >= since and not g.demo and ROSTER_SET[g.from] then gzGiven[g.from] = (gzGiven[g.from] or 0) + 1 end
    end
    if ns.Gz then
        for _, f in ipairs(ROSTER) do
            local la = db.levelAt and db.levelAt[f]
            if la and not la.g and not la.d and (la.t or 0) >= since and now - la.t > 900 and fr[f] and fr[f].lvl == la.l then
                local from = {}
                local n = 0
                for _, g in ipairs(gzLog) do
                    if type(g) == "table" and g.to == f and tonumber(g.l) == la.l and not g.demo and not from[g.from] then from[g.from] = true n = n + 1 end
                end
                if n == 0 then
                    add("lvl", 46, f, L("Ingen sagde tillykke"), string.format(L("%s nåede level %d kl. %s, og stilheden var øredøvende."), N(f), la.l, Clock(la.t)))
                elseif n >= 3 then
                    add("lvl", 38, f, L("Hele banden jublede"), string.format(L("%s fik gz fra %d venner for level %d. Rørende."), N(f), n, la.l))
                end
            end
        end
    end
    -- Nye alts og honor kills
    for _, f in ipairs(ROSTER) do
        local e = fr[f]
        local bc = base.chars and base.chars[f]
        if e and bc then
            for cn in pairs(e.chars) do
                if not bc[cn] then
                    local c = WastedCoastDB.friends[f].chars[cn]
                    add("lvl", 35, f, string.format(L("%s har en ny alt"), N(f)),
                        string.format(L("%s har lavet %s, en level %d %s. Alt-junkien slår til igen."), N(f), cn, c.level or 1, C.ClassName(c.class)))
                    break
                end
            end
            local hk = e.hk - ((base.hk and base.hk[f]) or e.hk)
            if hk >= 25 then add("lvl", 34, f, string.format(L("%s gik i krig"), N(f)), string.format(L("%s tog %d honorable kills i dag."), N(f), hk)) end
        end
    end
    -- Professions, reputation, spilletid, instanser og legacy
    local playTop, playN = nil, 0
    for _, f in ipairs(ROSTER) do
        local b, n = bst[f], cur[f]
        if b and n then
            local gp, gFrom, gTo
            for pn, rank in pairs(n.prof or {}) do
                local old = b.prof and b.prof[pn]
                if old and rank >= PROF_MAX and old < PROF_MAX then
                    add("lvl", 58, f, string.format(L("%s er mester"), N(f)), string.format(L("%s har maxet %s (%d). Nu kan man tage imod bestillinger."), N(f), L(pn), rank))
                elseif old and rank - old >= 25 and (not gp or rank - old > gTo - gFrom) then
                    gp, gFrom, gTo = pn, old, rank
                end
            end
            if gp then add("lvl", 27, f, string.format(L("%s i lære"), N(f)), string.format(L("%s skillede %s fra %d til %d."), N(f), L(gp), gFrom, gTo)) end
            local hadRep = b.rep and next(b.rep) ~= nil
            local bf, bsd
            for fac, sd in pairs(n.rep or {}) do
                local old = (b.rep and b.rep[fac]) or (hadRep and 4) or nil
                if old and sd > old and sd >= 6 and (not bsd or sd > bsd or (sd == bsd and fac < bf)) then bf, bsd = fac, sd end
            end
            if bf then
                if bsd >= 8 then
                    add("lvl", 62, f, string.format(L("%s er Exalted"), N(f)), string.format(L("%s er nu Exalted med %s. Tabardet er bestilt."), N(f), bf))
                else
                    add("lvl", bsd == 7 and 44 or 30, f, string.format(L("%s har venner i %s"), N(f), bf), string.format(L("%s nåede %s med %s."), N(f), STANDING[bsd], bf))
                end
            end
            if b.played and n.played then
                local d = n.played - b.played
                if d >= 5 * 3600 then
                    add("lvl", 39, f, string.format(L("Har %s et job?"), N(f)), string.format(L("%s har spillet %s i dag. %s"), N(f), Duration(d), PD("played" .. f, TAILS.played)))
                elseif d >= 2 * 3600 and d > playN then
                    playTop, playN = f, d
                end
            end
            local bestInst, bestC, wipes, wipeInst, wipeMax, bosses = nil, 0, 0, nil, 0, 0
            for inst, r in pairs(n.runs or {}) do
                local o = (b.runs and b.runs[inst]) or { c = 0, w = 0, b = 0 }
                local dc, dw = (r.c or 0) - (o.c or 0), (r.w or 0) - (o.w or 0)
                if dc > bestC or (dc == bestC and dc > 0 and inst < bestInst) then bestInst, bestC = inst, dc end
                if dw > 0 then
                    wipes = wipes + dw
                    if dw > wipeMax then wipeInst, wipeMax = inst, dw end
                end
                bosses = bosses + math.max(0, (r.b or 0) - (o.b or 0))
            end
            if bestInst and bestC > 0 then
                local boss = bosses >= 2 and string.format(L(" og dræbte %d bosser"), bosses) or ""
                add("lvl", 50, f, string.format(L("%s ryddede %s"), N(f), L(bestInst)), string.format(L("%s klarede %s%s."), N(f), L(bestInst), boss))
            end
            if wipes >= 3 and wipeInst then
                add("lvl", 54, f, string.format(L("%s %d, banden 0"), L(wipeInst), wipes),
                    string.format(L("%s wipede %s gange i %s. %s"), N(f), Red(wipes), L(wipeInst), PD("wipe" .. f, TAILS.wipe)))
            end
            if n.lp and b.lp and n.lp > b.lp then
                local ch = ((n.lc or 0) - (b.lc or 0)) > 0 and string.format(L(" og klarede %s"), C.Plural((n.lc or 0) - (b.lc or 0), L("challenge"), L("challenges"))) or ""
                add("lvl", 33, f, string.format(L("%s skriver historie"), N(f)), string.format(L("%s tjente %d legacy points%s."), N(f), n.lp - b.lp, ch))
            end
        end
    end
    if playTop then add("lvl", 24, playTop, L("Dagens stamgæst"), string.format(L("%s har spillet %s i dag."), N(playTop), Duration(playN))) end
    -- Rare mobs og trofæer
    local rmBy = {}
    for _, r in ipairs(db.rareLog or {}) do
        if type(r) == "table" and (r.t or 0) >= since and ROSTER_SET[r.friend] and not r.demo then
            rmBy[r.friend] = rmBy[r.friend] or {}
            table.insert(rmBy[r.friend], r)
        end
    end
    for f, list in pairs(rmBy) do
        local last = list[#list]
        add("lvl", 41, f, L("Rare-jægeren slår til"),
            string.format(L("%s nedlagde %s%s. Trofæet hænger over pejsen."), N(f), last.mob or "?", (last.zone and last.zone ~= "") and (L(" i ") .. last.zone) or ""))
    end
    local achs = {}
    for _, f in ipairs(ROSTER) do
        for id, t in pairs((db.ach and db.ach[f]) or {}) do
            local ac = C.ACH_BY_ID and C.ACH_BY_ID[id]
            if ac and type(t) == "number" and t >= since and not (db.demoAch and db.demoAch[f] and db.demoAch[f][id]) then
                achs[#achs + 1] = { f = f, a = ac }
            end
        end
    end
    table.sort(achs, function(x, y) return (x.a.pts or 0) > (y.a.pts or 0) or ((x.a.pts or 0) == (y.a.pts or 0) and x.f < y.f) end)
    for i, x in ipairs(achs) do
        if i > 2 then break end
        add("lvl", 38 + math.min(10, (x.a.pts or 0) / 5), x.f, string.format(L("Trofæ til %s"), N(x.f)),
            string.format(L("%s låste trofæet %s op: %s"), N(x.f), x.a.name or "?", x.a.desc or ""))
    end

    -- ---------------------------------------------------------------- Kapløbet
    local race = {}
    for f, e in pairs(fr) do
        if e.lvl > 0 then race[#race + 1] = { f = f, lvl = e.lvl, xp = e.xp, ls = e.ls, gain = (base.lv and base.lv[f]) and (e.lvl - math.floor(base.lv[f])) or 0 } end
    end
    table.sort(race, function(x, y) if x.ls ~= y.ls then return x.ls > y.ls end return x.f < y.f end)
    P.race = race
    local blv = base.lv or {}
    if #race >= 2 then
        local leader = race[1]
        local bLeader
        for f, v in pairs(blv) do
            if fr[f] and (not bLeader or v > blv[bLeader] or (v == blv[bLeader] and f < bLeader)) then bLeader = f end
        end
        local lead = math.floor(leader.ls - race[2].ls)
        if bLeader and bLeader ~= leader.f and blv[leader.f] then
            add("kap", 77, leader.f, L("Ny fører i kapløbet"), string.format(L("%s har overhalet %s og fører nu kapløbet."), N(leader.f), N(bLeader)))
        else
            -- Overhalinger længere nede
            local best
            for i, x in ipairs(race) do
                for j = i + 1, #race do
                    local y = race[j]
                    if blv[x.f] and blv[y.f] and blv[x.f] < blv[y.f] and (not best or i < best.i) then best = { i = i, x = x, y = y } end
                end
            end
            if best then
                add("kap", 48, best.x.f, string.format(L("%s overhaler %s"), N(best.x.f), N(best.y.f)),
                    string.format(L("%s er gået forbi %s og ligger nu nummer %d."), N(best.x.f), N(best.y.f), best.i))
            end
        end
        if lead >= 5 then
            add("kap", 40, leader.f, string.format(L("%s stikker af"), N(leader.f)), string.format(L("%s fører med %d levels. Resten kan se støvet."), N(leader.f), lead))
        end
        for i = 2, #race do
            local x, y = race[i - 1], race[i]
            local d = x.ls - y.ls
            if x.lvl < C.MAX_LEVEL and d > 0 and d < 0.25 then
                add("kap", 36, y.f, L("Fotofinish"), string.format(L("%s er kun %d%% XP fra at indhente %s."), N(y.f), math.max(1, math.floor(d * 100)), N(x.f)))
                break
            end
        end
        -- Tempo: levels siden en dag for 3-14 dage siden
        local old
        for _, h in pairs(a.hist) do
            local age = since - (h.t or since)
            if age >= 3 * 86400 and age <= A.HIST_DAYS * 86400 and h.lv and h.lv[leader.f] and (not old or h.t < old.t) then old = h end
        end
        if old and leader.lvl < C.MAX_LEVEL then
            local days = (now - old.t) / 86400
            local rate = (leader.ls - old.lv[leader.f]) / days
            if rate > 0.05 then P.eta = { f = leader.f, d = math.ceil((C.MAX_LEVEL - leader.ls) / rate) } end
        end
        -- Sneglen: lavest, og intet level i mindst 3 dage
        local low = race[#race]
        local la = db.levelAt and db.levelAt[low.f]
        if low.ls < leader.ls and la and not la.g and not la.d and la.t and now - la.t >= 3 * 86400 then
            F(low.f).snail = true
            add("kap", 30, low.f, L("Sneglen står stille"), string.format(L("%s har ikke fået et level i %s. Vi tænker på dig."), N(low.f), Duration(now - la.t)))
        end
    end

    -- ---------------------------------------------------------------- Skandaler
    local stLog = (db.stomi and db.stomi.log) or {}
    local stomiTold, dodged = {}, false
    for _, e in ipairs(stLog) do
        if type(e) == "table" and (e.t or 0) >= since and not e.demo and ROSTER_SET[e.to] and ROSTER_SET[e.from] then
            if e.r == "y" and not stomiTold[e.to] then
                stomiTold[e.to] = true
                F(e.to).stomi = true
                local week, revenge = 0, false
                for _, o in ipairs(stLog) do
                    if type(o) == "table" and not o.demo and o.r == "y" then
                        if o.to == e.to and (o.t or 0) >= now - 7 * 86400 then week = week + 1 end
                        if o.from == e.to and o.to == e.from and (o.t or 0) < (e.t or 0) then revenge = true end
                    end
                end
                if revenge then
                    add("skan", 70, e.from, L("Hævnens pose"), string.format(L("%s gav %s stomi tilbage. Cirklen er sluttet."), N(e.from), N(e.to)))
                elseif week >= 2 then
                    add("skan", 64, e.to, string.format(L("%s sagde ja igen"), N(e.to)), string.format(L("%s fik stomi af %s. Det er pose nummer %d på en uge."), N(e.to), N(e.from), week))
                else
                    add("skan", 47, e.to, L("Stomi-skandale"), string.format(L("%s fik stomi af %s kl. %s. %s"), N(e.to), N(e.from), Clock(e.t), PD("stomi" .. e.to, TAILS.stomi)))
                end
            elseif (e.r == "n" or e.r == "d") and not dodged then
                dodged = true
                add("skan", 22, e.to, L("Fælden klappede ikke"), string.format(L("%s gennemskuede en stomi-fælde fra %s."), N(e.to), N(e.from)))
            end
        end
    end
    local traps = {}
    for _, e in ipairs(stLog) do
        if type(e) == "table" and not e.demo and (e.t or 0) >= now - 7 * 86400 and ROSTER_SET[e.from] then
            local tr = traps[e.from] or { n = 0 }
            tr.n = tr.n + 1
            if (e.t or 0) >= since then tr.today = true end
            traps[e.from] = tr
        end
    end
    for f, tr in pairs(traps) do
        if tr.n >= 3 and tr.today then
            add("skan", 52, f, L("Stomi-terroristen"), string.format(L("%s har sat %d stomi-fælder på en uge. Ingen er sikre."), N(f), tr.n))
        end
    end
    -- Prutter
    local hLog = (db.haan and db.haan.log) or {}
    local sent, recv, onDeath, deathVictim = {}, {}, {}, {}
    for _, e in ipairs(hLog) do
        if type(e) == "table" and (e.t or 0) >= since and not e.demo and ROSTER_SET[e.from] and ROSTER_SET[e.to] then
            P.stats.farts = P.stats.farts + 1
            sent[e.from] = (sent[e.from] or 0) + 1
            recv[e.to] = (recv[e.to] or 0) + 1
            if e.death then
                onDeath[e.death] = onDeath[e.death] or {}
                onDeath[e.death][e.from] = true
                deathVictim[e.death] = e.to
            end
        end
    end
    for id, set in pairs(onDeath) do
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        if n >= 3 then
            add("skan", 58, deathVictim[id], string.format(L("Kollektiv prut over %s"), N(deathVictim[id])),
                string.format(L("%d venner pruttede af %s, mens liget stadig var varmt."), n, N(deathVictim[id])))
            break
        end
    end
    local function Top(t)
        local best, n = nil, 0
        for k, v in pairs(t) do if v > n or (v == n and best and k < best) then best, n = k, v end end
        return best, n
    end
    local ts, tn = Top(sent)
    if ts and tn >= 5 then add("skan", 24, ts, L("Prut-baronen"), string.format(L("%s pruttede af de døde %d gange i dag. %s"), N(ts), tn, PD("fart" .. ts, TAILS.fart))) end
    local tr, rn = Top(recv)
    if tr and rn >= 5 then add("skan", 21, tr, string.format(L("%s er bandens pruttepude"), N(tr)), string.format(L("%s blev pruttet af %d gange. Det sker, når man dør så tit."), N(tr), rn)) end
    local tg, gn = Top(gzGiven)
    if tg and gn >= 3 then add("skan", 18, tg, L("Bandens sødeste"), string.format(L("%s sagde tillykke %d gange i dag."), N(tg), gn)) end
    -- Socialt: savnede, tilbage, natteugler, pjækkere, samlet bande og makkerpar
    for _, f in ipairs(ROSTER) do
        if f ~= db.me then
            local seen = C.LastSeen(f)
            if seen and now - seen > A.MISSING_DAYS * 86400 and now - seen < 60 * 86400 then
                F(f).missing = true
                local e = fr[f]
                add("skan", 12, f, L("Efterlyst"), string.format(L("%s er ikke set i %s. Sidst set i %s på level %d."), N(f), Duration(now - seen),
                    (e and e.zone and e.zone ~= "") and e.zone or "?", (e and e.lvl) or 0))
                break
            end
        end
    end
    for _, f in ipairs(ROSTER) do
        local bs = base.seen and base.seen[f]
        local seen = C.LastSeen(f)
        if f ~= db.me and bs and seen and since - bs >= 7 * 86400 and seen >= since then
            add("skan", 54, f, string.format(L("%s er tilbage fra de døde"), N(f)), string.format(L("%s loggede ind efter %s væk. Keybinds er sikkert glemt."), N(f), Duration(seen - bs)))
        end
    end
    for _, f in ipairs(ROSTER) do
        local o = a.on[f]
        if o and o.night and f ~= db.me then
            add("skan", 30, f, L("Natteuglen"), string.format(L("%s var online kl. %s i nat. Hvad foregår der?"), N(f), Clock(o.night)))
            break
        end
    end
    for _, f in ipairs(ROSTER) do
        local o = a.on[f]
        if o and o.work and f ~= db.me then
            add("skan", 34, f, string.format(L("Pjækker %s?"), N(f)), string.format(L("%s var online en hverdag kl. %s. Chefen må ikke se det her."), N(f), Clock(o.work)))
            break
        end
    end
    if a.peak and a.peak.n >= 6 and (a.peak.t or 0) >= since then
        add("skan", 42, nil, L("Banden er samlet"), string.format(L("%d venner var online på samme tid kl. %s. Sådan skal det være."), a.peak.n, Clock(a.peak.t)))
    end
    local duoK, duoS
    for k, p in pairs(a.duo) do
        if p.s >= 1800 and (not duoS or p.s > duoS) then duoK, duoS = k, p.s end
    end
    if duoK then
        local x, y = duoK:match("^(.-)|(.*)$")
        if x and ROSTER_SET[x] and ROSTER_SET[y] then
            add("skan", 26, nil, string.format(L("Set sammen i %s"), a.duo[duoK].z or "?"),
                string.format(L("%s og %s har været i %s sammen i %s i dag. Rygterne går."), N(x), N(y), a.duo[duoK].z or "?", Duration(duoS)))
        end
    end

    -- ---------------------------------------------------------------- Skammens hat
    local hat = {}
    P.hat = hat
    -- Den, der døde sidst, bærer hatten (samme regel som Drilleri.lua, men uden demo-dødsfald)
    local holder = allDeaths[#allDeaths] and allDeaths[#allDeaths].f
    if holder and ROSTER_SET[holder] then
        hat.f = holder
        local i = #allDeaths
        while i > 0 and allDeaths[i].f ~= holder do i = i - 1 end
        local start = i
        while start > 1 and allDeaths[start - 1].f == holder do start = start - 1 end
        local got = start > 0 and allDeaths[start].ev.time
        local prev = start > 1 and allDeaths[start - 1]
        local streaks = 0
        for j = 1, #allDeaths do
            local d = allDeaths[j]
            if d.f == holder and (d.ev.time or 0) >= since and (j == 1 or allDeaths[j - 1].f ~= holder) then streaks = streaks + 1 end
        end
        F(holder).hat = true
        if got and now - got > 86400 then
            hat.text = string.format(L("%s har båret hatten i %s. Nogen må snart dø, så den kan komme videre."), N(holder), Duration(now - got))
        elseif got and prev and prev.ev.time and got >= since then
            local wore = got - prev.ev.time
            if wore < 600 then
                hat.text = string.format(L("%s overtog hatten fra %s, som kun nåede at bære den i %s. Rekordkort!"), N(holder), N(prev.f), Duration(wore))
            else
                hat.text = string.format(L("%s overtog hatten fra %s kl. %s."), N(holder), N(prev.f), Clock(got))
            end
        elseif got then
            hat.text = string.format(L("%s har båret hatten siden kl. %s."), N(holder), Clock(got))
        end
        if streaks >= 3 then
            hat.extra = string.format(L("Det er %d. gang i dag, at hatten havner hos %s. Den passer perfekt."), streaks, N(holder))
        end
    else
        hat.text = L("Ingen bærer hatten endnu. Den venter tålmodigt på den første, der dør.")
    end

    -- ---------------------------------------------------------------- Horoskop
    P.horo = {}
    for _, f in ipairs(ROSTER) do
        local e = fr[f]
        if e then
            local fx = facts[f] or {}
            local text
            if fx.hat then text = PD(f .. "h", HORO.hat)
            elseif fx.stomi then text = PD(f .. "s", HORO.stomi)
            elseif (fx.deaths or 0) >= 3 then text = string.format(PD(f .. "d", HORO.deaths), fx.zone or "?")
            elseif (fx.levels or 0) >= 3 then text = PD(f .. "l", HORO.levels)
            elseif fx.epic then text = PD(f .. "e", HORO.epic)
            elseif fx.cop then text = PD(f .. "c", HORO.cop)
            elseif fx.goldUp then text = PD(f .. "g", HORO.gold)
            elseif fx.missing then text = PD(f .. "m", HORO.missing)
            elseif fx.snail then text = PD(f .. "n", HORO.snail)
            else text = PD(f .. "x", HORO.none) end
            P.horo[#P.horo + 1] = { f = f, sign = SIGNS[e.cls or ""] or L("Stjernen"), t = text }
        end
    end

    -- ---------------------------------------------------------------- Små annoncer og vejret
    P.ads = {}
    local function ad(s) if #P.ads < 3 then P.ads[#P.ads + 1] = s end end
    for f in pairs(stomiTold) do ad(string.format(L("Sælges: stomipose, kun brugt i 24 timer. Henv. %s."), N(f))) break end
    local mostF, mostN = nil, 0
    for f, n in pairs(byF) do if n > mostN or (n == mostN and f < mostF) then mostF, mostN = f, n end end
    if mostF and mostN >= 3 then ad(string.format(L("Købes: sund fornuft til kamp mod lavere levels. Henv. %s."), N(mostF))) end
    for _, e in ipairs(cops) do
        if e.why == "gone" then ad(string.format(L("Sælges: %s, aldrig brugt. Henv. %s."), Item({ quality = e.quality, name = e.name }), N(e.friend))) break end
    end
    for f, fx in pairs(facts) do
        if fx.goldDown then ad(string.format(L("Lån søges: ærlig sjæl mangler guld til repairs. Henv. %s."), N(f))) break end
    end
    if hat.f then ad(L("Bortgives: lilla hat, lidt brugt. Går til den næste, der dør.")) end
    if #P.ads == 0 then ad(L("Ingen annoncer i dag. Selv auktionshuset holder fri.")) end

    local wz, wn = nil, 0
    for z, n in pairs(zoneN) do if n > wn or (n == wn and z < wz) then wz, wn = z, n end end
    if wz then
        local k = Top(zoneKill[wz] or {})
        P.weather = k and string.format(L("Vejret i %s: overskyet med risiko for %s"), wz, L(k)) or string.format(L("Vejret i %s: overskyet med dødsfald"), wz)
    else
        P.weather = L("Vejret i Elwynn: klart og stille")
    end

    -- ---------------------------------------------------------------- Udvælgelse
    table.sort(P.stories, function(x, y)
        if x.w ~= y.w then return x.w > y.w end
        return (x.h or "") < (y.h or "")
    end)
    local per, chosen, rest = {}, {}, {}
    for _, s in ipairs(P.stories) do
        if not s.f or (per[s.f] or 0) < A.PER_FRIEND then
            chosen[#chosen + 1] = s
            if s.f then per[s.f] = (per[s.f] or 0) + 1 end
        else
            rest[#rest + 1] = s
        end
    end
    for _, s in ipairs(rest) do chosen[#chosen + 1] = s end
    P.sec = {}
    for _, k in ipairs(A.SECTIONS) do P.sec[k] = {} end
    P.lead = chosen[1]
    for i = 2, #chosen do
        local l = P.sec[chosen[i].sec]
        if l and #l < A.PER_SECTION then l[#l + 1] = chosen[i] end
    end
    if not P.lead then
        P.lead = { sec = "dod", w = 0, h = L("Stille dag i Wasted Coast"),
                   t = L("Ingen døde, ingen loot, ingen levels. Gå ud og dø lidt, så der er noget at skrive om.") }
    end
    P.count = #P.stories
    return P
end

function A.DateLine(t)
    local d = date("*t", t or time())
    return string.format(L("%s d. %d. %s"), WEEKDAYS[d.wday] or "", d.day, MONTHS[d.month] or "")
end

-- Ren tekst til Discord (uden farvekoder og links)
local function Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return s
end
A.Plain = Plain

function A.PlainText(P)
    local _, a = DB()
    local out = {}
    local function w(s) out[#out + 1] = Plain(s) end
    w("**" .. L("Wasted Coast Tidende") .. "** - " .. A.DateLine(P.now))
    w("_" .. P.weather .. "_")
    w("")
    w("**" .. P.lead.h .. "**")
    w(P.lead.t)
    for _, k in ipairs(A.SECTIONS) do
        if #P.sec[k] > 0 then
            w("")
            w("__" .. SEC_NAME[k] .. "__")
            for _, s in ipairs(P.sec[k]) do w("- **" .. s.h .. ":** " .. s.t) end
        end
    end
    if P.hat and P.hat.text then
        w("")
        w("__" .. L("Skammens hat") .. "__")
        w(P.hat.text)
    end
    if #P.horo > 0 then
        w("")
        w("__" .. L("Horoskop") .. "__")
        for _, h in ipairs(P.horo) do w("- " .. Name(h.f) .. " (" .. h.sign .. "): " .. h.t) end
    end
    return table.concat(out, "\n")
end

-- =============================================================================
-- Vinduet: avisen i spillet
-- =============================================================================
local ui = {}
A.ui = ui
local PAPER = { 0.93, 0.88, 0.76, 1 }
local INK = { 0.16, 0.12, 0.08 }
local RED = { 0.54, 0.11, 0.07 }
local HEAD_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local WIN_W, WIN_H = 980, 880
local PAD = 18
local COL_W, COL_GAP = 292, 20

local function Ink(parent, size, font, col, justify)
    local fs = C.Txt(parent, "GameFontHighlight")
    pcall(fs.SetFont, fs, font or BODY_FONT, size or 11, "")
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    local c = col or INK
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    fs:SetWordWrap(true)
    return fs
end

local function Rule(parent, x, y, w, h)
    local t = parent:CreateTexture(nil, "ARTWORK")
    C.BarFill(t, INK[1], INK[2], INK[3], 1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetSize(w, h or 1)
    return t
end

local function Height(fs)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return (type(h) == "number" and h > 0) and h or 14
end

-- En rubrik: titel, streg og plads til historier (headline + tekst)
local function Section(parent, x, y, w, h, title)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(w, h)
    box.title = Ink(box, 15, HEAD_FONT, INK)
    box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    box.title:SetWidth(w)
    box.title:SetText(title)
    Rule(box, 0, -20, w, 2)
    box.items, box.w, box.h, box.top, box.tsize, box.gap = {}, w, h, -26, 11, 7
    return box
end

-- entries: { { h = overskrift (valgfri), t = tekst } }. Det, der ikke er plads til, skjules.
local function Fill(box, entries, startY)
    local y = startY or box.top
    local used = 0
    for i, e in ipairs(entries) do
        local it = box.items[i]
        if not it then
            it = { h = Ink(box, 13, HEAD_FONT, INK), t = Ink(box, box.tsize, BODY_FONT, INK) }
            it.h:SetWidth(box.w)
            it.t:SetWidth(box.w)
            box.items[i] = it
        end
        local need = 0
        it.h:ClearAllPoints()
        it.t:ClearAllPoints()
        if e.h and e.h ~= "" then
            it.h:SetText(e.h)
            it.h:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
            need = Height(it.h) + 2
        else
            it.h:SetText("")
        end
        it.t:SetText(e.t or "")
        it.t:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y - need)
        need = need + Height(it.t) + box.gap
        if -(y - need) > box.h and used > 0 then
            it.h:Hide()
            it.t:Hide()
        else
            it.h:Show()
            it.t:Show()
            y = y - need
            used = used + 1
        end
    end
    for i = #entries + 1, #box.items do
        box.items[i].h:Hide()
        box.items[i].t:Hide()
    end
    return y
end

local function BuildWindow()
    local p = C.MakeBox("Frame", UIParent, C.COL_BG, C.COL_GOLD, "WastedCoastAvis")
    p:SetSize(WIN_W, WIN_H)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    if p.SetClampedToScreen then p:SetClampedToScreen(true) end
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if C.AddShadow then C.AddShadow(p, 8) end
    table.insert(UISpecialFrames, "WastedCoastAvis")

    local logo = p:CreateTexture(nil, "OVERLAY")
    logo:SetSize(52, 52)
    logo:SetPoint("TOPLEFT", p, "TOPLEFT", -14, 14)
    logo:SetTexture(ns.LOGO)
    local title = C.Txt(p, "GameFontNormal")
    title:SetPoint("TOP", p, "TOP", 0, -12)
    title:SetText(L("Wasted Coast Forever"))
    local close = C.MakeCloseButton(p, 24, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -6)

    local paper = C.MakeBox("Frame", p, PAPER, { 0.45, 0.36, 0.2, 1 })
    paper:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -36)
    paper:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 44)
    ui.paper = paper
    local W = WIN_W - 28 - 2 * PAD

    local function at(fs, x, y, w) fs:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + x, y) if w then fs:SetWidth(w) end end
    ui.dateL = Ink(paper, 10) at(ui.dateL, 0, -10, 330)
    ui.dateC = Ink(paper, 10, nil, nil, "CENTER") at(ui.dateC, 330, -10, W - 660)
    ui.dateR = Ink(paper, 10, nil, nil, "RIGHT") at(ui.dateR, W - 330, -10, 330)
    Rule(paper, PAD, -24, W, 1)
    ui.mast = Ink(paper, 44, HEAD_FONT, INK, "CENTER") at(ui.mast, 0, -30, W)
    ui.mast:SetText(L("Wasted Coast Tidende"))
    ui.tag = Ink(paper, 10, nil, nil, "CENTER") at(ui.tag, 0, -80, W)
    ui.tag:SetText(L("Uafhængig af enhver sund fornuft siden level 1 · Danmarks eneste avis med stomi-rubrik"))
    Rule(paper, PAD, -96, W, 2)
    Rule(paper, PAD, -100, W, 1)

    -- Forsiden
    local LEAD_W = 600
    ui.kick = Ink(paper, 10, BODY_FONT, RED) at(ui.kick, 0, -112, LEAD_W)
    ui.head = Ink(paper, 30, HEAD_FONT, INK) at(ui.head, 0, -126, LEAD_W)
    ui.body = Ink(paper, 13, BODY_FONT, INK)
    ui.body:SetPoint("TOPLEFT", ui.head, "BOTTOMLEFT", 0, -8)
    ui.body:SetWidth(LEAD_W)
    ui.statN, ui.statL = {}, {}
    for i = 1, 4 do
        local x = (i - 1) * 150
        ui.statN[i] = Ink(paper, 22, HEAD_FONT, INK) at(ui.statN[i], x, -272, 140)
        ui.statL[i] = Ink(paper, 9, BODY_FONT, INK) at(ui.statL[i], x, -298, 140)
    end
    Rule(paper, PAD, -266, LEAD_W, 1)
    local vr = paper:CreateTexture(nil, "ARTWORK")
    C.BarFill(vr, INK[1], INK[2], INK[3], 1)
    vr:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + LEAD_W + 16, -112)
    vr:SetSize(1, 204)

    -- Skammens hat
    local hx = LEAD_W + 34
    local hw = W - hx
    local hatBox = C.MakeBox("Frame", paper, PAPER, { INK[1], INK[2], INK[3], 1 })
    hatBox:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD + hx, -110)
    hatBox:SetSize(hw, 208)
    local hk = Ink(hatBox, 9, BODY_FONT, RED, "CENTER")
    hk:SetPoint("TOP", hatBox, "TOP", 0, -8)
    hk:SetWidth(hw - 16)
    hk:SetText(L("DAGENS PORTRÆT"))
    local ht = Ink(hatBox, 20, HEAD_FONT, INK, "CENTER")
    ht:SetPoint("TOP", hk, "BOTTOM", 0, -2)
    ht:SetWidth(hw - 16)
    ht:SetText(L("Skammens hat"))
    ui.hatIcon = hatBox:CreateTexture(nil, "ARTWORK")
    ui.hatIcon:SetSize(64, 64)
    ui.hatIcon:SetPoint("TOP", ht, "BOTTOM", 0, -4)
    ui.hatIcon:SetTexture(ns.HAT_ICON)
    ui.hatText = Ink(hatBox, 11, BODY_FONT, INK, "CENTER")
    ui.hatText:SetPoint("TOP", ui.hatIcon, "BOTTOM", 0, -6)
    ui.hatText:SetWidth(hw - 20)

    Rule(paper, PAD, -326, W, 2)
    Rule(paper, PAD, -330, W, 1)

    -- Rubrikkerne
    local function colX(i) return PAD + (i - 1) * (COL_W + COL_GAP) end
    ui.box = {}
    ui.box.dod = Section(paper, colX(1), -340, COL_W, 190, SEC_NAME.dod)
    ui.box.bors = Section(paper, colX(2), -340, COL_W, 190, SEC_NAME.bors)
    ui.box.lvl = Section(paper, colX(3), -340, COL_W, 190, SEC_NAME.lvl)
    Rule(paper, PAD, -538, W, 2)
    ui.box.kap = Section(paper, colX(1), -548, COL_W, 240, SEC_NAME.kap)
    ui.box.skan = Section(paper, colX(2), -548, COL_W, 240, SEC_NAME.skan)
    ui.box.horo = Section(paper, colX(3), -548, COL_W, 240, L("Horoskop"))
    ui.box.horo.tsize, ui.box.horo.gap = 10, 3

    -- Kapløbets tabel
    local kb = ui.box.kap
    ui.raceRows = {}
    for i = 1, 10 do
        local r = { n = Ink(kb, 11), l = Ink(kb, 11, nil, nil, "RIGHT"), g = Ink(kb, 11, nil, nil, "RIGHT") }
        r.n:SetWidth(COL_W - 130)
        r.l:SetWidth(80)
        r.g:SetWidth(44)
        ui.raceRows[i] = r
    end

    -- Knapper
    local discord = C.MakeButton(p, 150, 24, L("Kopiér til Discord"), function() A.ShowCopy() end)
    discord:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 11)
    local open = C.MakeButton(p, 130, 24, L("Åbn WC4ever"), function()
        p:Hide()
        if ns.frame then ns.frame:Show() if ns.ShowTab then ns.ShowTab(20) end end
    end)
    open:SetPoint("LEFT", discord, "RIGHT", 6, 0)
    local done = C.MakeButton(p, 100, 24, L("Luk avisen"), function() p:Hide() end)
    done:SetPoint("LEFT", open, "RIGHT", 6, 0)
    local hint = C.Txt(p, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 17)
    hint:SetTextColor(0.6, 0.58, 0.52)
    hint:SetText(L("Avisen kommer ved hvert login. /wc4ever avis fra slår det fra."))

    ui.frame = p
    return p
end

local function RenderRace(P)
    local kb = ui.box.kap
    local kap = P.sec.kap
    local y = kb.top
    local entries = {}
    if kap[1] then entries[1] = kap[1] else entries[1] = { h = L("Stillingen i kapløbet"), t = "" } end
    y = Fill(kb, { { h = entries[1].h, t = entries[1].t } })
    local shown = 0
    for i, r in ipairs(ui.raceRows) do
        local x = P.race[i]
        if x and y - 14 > -(kb.h - 30) then
            shown = shown + 1
            r.n:ClearAllPoints() r.l:ClearAllPoints() r.g:ClearAllPoints()
            r.n:SetPoint("TOPLEFT", kb, "TOPLEFT", 0, y)
            r.l:SetPoint("TOPLEFT", kb, "TOPLEFT", COL_W - 130, y)
            r.g:SetPoint("TOPLEFT", kb, "TOPLEFT", COL_W - 44, y)
            r.n:SetText(i .. ". " .. Name(x.f))
            r.l:SetText(x.xp and string.format("%d (%d%%)", x.lvl, x.xp) or tostring(x.lvl))
            r.g:SetText(x.gain > 0 and Red("+" .. x.gain) or "0")
            r.n:Show() r.l:Show() r.g:Show()
            y = y - 14
        else
            r.n:Hide() r.l:Hide() r.g:Hide()
        end
    end
    -- Resten af kapløbets historier og tempoet under tabellen
    ui.raceNote = ui.raceNote or Ink(kb, 10)
    local note = ui.raceNote
    note:SetWidth(COL_W)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", kb, "TOPLEFT", 0, y - 4)
    local notes = {}
    if P.eta then notes[#notes + 1] = string.format(L("Med det seneste tempo når %s level %d om %d dage."), Name(P.eta.f), C.MAX_LEVEL, P.eta.d) end
    for i = 2, #kap do notes[#notes + 1] = kap[i].t end
    if #P.race == 0 then notes[#notes + 1] = SEC_EMPTY.kap end
    note:SetText(table.concat(notes, " "))
end

local function Render(P)
    local p = ui.frame or BuildWindow()
    local _, a = DB()
    ui.P = P
    ui.dateL:SetText(A.DateLine(P.now) .. " · " .. string.format(L("Opdateret kl. %s"), Clock(P.now)))
    ui.dateC:SetText(P.weather)
    ui.dateR:SetText(string.format(L("Nr. %d · %s i dag · Pris: 1 kobber"), a.n or 1, C.Plural(P.count, L("historie"), L("historier"))))
    local lead = P.lead
    ui.kick:SetText(L("DAGENS STORE HISTORIE") .. " · " .. (SEC_KICK[lead.sec] or ""))
    ui.head:SetText(lead.h)
    ui.body:SetText(lead.t)
    local st = P.stats
    local stats = {
        { st.deaths, L("dødsfald i banden i dag") }, { st.levels, L("levels i dag") },
        { st.loot, L("rare og epic items i dag") }, { st.farts, L("prutter over de døde") },
    }
    for i, s in ipairs(stats) do
        ui.statN[i]:SetText(tostring(s[1]))
        ui.statL[i]:SetText(s[2])
    end
    ui.hatText:SetText((P.hat.text or "") .. (P.hat.extra and ("\n" .. P.hat.extra) or ""))
    if ui.hatIcon.SetDesaturated then ui.hatIcon:SetDesaturated(not P.hat.f) end
    for _, k in ipairs({ "dod", "bors", "lvl" }) do
        local list = P.sec[k]
        if #list == 0 then list = { { t = SEC_EMPTY[k] } } end
        Fill(ui.box[k], list)
    end
    RenderRace(P)
    local skan = {}
    for _, s in ipairs(P.sec.skan) do skan[#skan + 1] = s end
    if #skan == 0 then skan[1] = { t = SEC_EMPTY.skan } end
    for i, ad in ipairs(P.ads) do skan[#skan + 1] = { h = i == 1 and L("Små annoncer") or nil, t = ad } end
    Fill(ui.box.skan, skan)
    local horo = {}
    for _, h in ipairs(P.horo) do horo[#horo + 1] = { t = Red(Name(h.f)) .. " (" .. h.sign .. "): " .. h.t } end
    Fill(ui.box.horo, horo)
    return p
end

function A.Show(auto)
    local db = DB()
    if not db.me then
        if not auto then Print(L("Du er ikke med i en gruppe endnu. Avisen skriver kun om banden.")) end
        return
    end
    local P = A.Collect()
    A.last = P
    local p = Render(P)
    p:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
    if db.settings.announce and auto then
        Print("|cffffd100" .. L("Wasted Coast Tidende") .. ":|r " .. P.lead.h .. ". " .. P.lead.t)
    end
end
ns.ShowAvis = A.Show

-- Kopi-boksen: avisen som ren tekst, markeret, så Ctrl+C kopierer den
function A.ShowCopy()
    local P = ui.P or A.last or A.Collect()
    local text = A.PlainText(P)
    if not ui.copy then
        local box = C.MakeBox("Frame", UIParent, C.COL_BG, C.COL_GOLD, "WastedCoastAvisCopy")
        box:SetSize(560, 360)
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:EnableMouse(true)
        table.insert(UISpecialFrames, "WastedCoastAvisCopy")
        local t = C.Txt(box, "GameFontNormal")
        t:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        t:SetText(L("Tryk Ctrl+C for at kopiere, og sæt det ind i Discord"))
        local close = C.MakeCloseButton(box, 22, function() box:Hide() end)
        close:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
        local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -30, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        if ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
        eb:SetWidth(510)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() box:Hide() end)
        sf:SetScrollChild(eb)
        ui.copy, ui.copyEdit = box, eb
    end
    ui.copyEdit:SetText(text)
    ui.copy:Show()
    ui.copyEdit:SetFocus()
    ui.copyEdit:HighlightText()
    A.lastPlain = text
end

-- =============================================================================
-- Side 20: Sjov > Avisen (dagens overskrifter)
-- =============================================================================
local page = {}
local function BuildPage(pg)
    local box = C.MakeBox("Frame", pg, C.COL_PANEL, C.COL_BORDER)
    box:SetAllPoints(pg)
    local h = C.Txt(box, "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    h:SetText(L("Wasted Coast Tidende"))
    h:SetTextColor(C.COL_GOLD[1], C.COL_GOLD[2], C.COL_GOLD[3])
    page.sub = C.Txt(box, "GameFontHighlightSmall")
    page.sub:SetPoint("LEFT", h, "RIGHT", 8, -1)
    page.sub:SetTextColor(0.6, 0.6, 0.66)
    local btn = C.MakeButton(box, 140, 24, L("Åbn dagens avis"), function() A.Show(false) end)
    btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -8)
    page.list = C.Txt(box, "GameFontHighlight")
    page.list:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -44)
    page.list:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    page.list:SetJustifyH("LEFT")
    if page.list.SetJustifyV then page.list:SetJustifyV("TOP") end
    page.list:SetSpacing(5)
    local note = C.Txt(box, "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
    note:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    note:SetTextColor(0.5, 0.5, 0.56)
    note:SetText(L("Avisen samler alt, der er sket i banden i dag. Den åbner ved hvert login (/wc4ever avis fra slår det fra)."))
end

local function RefreshPage()
    if not page.list or not WastedCoastDB.me then return end
    local P = A.Collect()
    page.sub:SetText(A.DateLine(P.now) .. " · " .. C.Plural(P.count, L("historie"), L("historier")))
    local lines = { "|cffffd100" .. P.lead.h .. "|r  " .. P.lead.t }
    for _, k in ipairs(A.SECTIONS) do
        for _, s in ipairs(P.sec[k]) do
            if #lines < 16 then lines[#lines + 1] = "|cff9aa0a6" .. SEC_NAME[k] .. ":|r |cffffd100" .. s.h .. "|r  " .. s.t end
        end
    end
    page.list:SetText(table.concat(lines, "\n"))
end
C.EXTRA_PAGES[20] = { build = BuildPage, refresh = RefreshPage }

-- =============================================================================
-- Kommando og events
-- =============================================================================
function ns.AvisSlash(cmd, arg)
    if cmd ~= "avis" and cmd ~= "avisen" and cmd ~= "news" and cmd ~= "paper" then return false end
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "fra" or arg == "off" then
        db.settings.avis = false
        Print(L("Avisen ved login: fra. |cffffd100/wc4ever avis|r virker stadig."))
    elseif arg == "til" or arg == "on" then
        db.settings.avis = nil
        Print(L("Avisen ved login: til."))
    elseif arg == "discord" then
        A.Show(false)
        A.ShowCopy()
    else
        A.Show(false)
    end
    return true
end

local shownThisSession = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, isInitial, isReload)
    if not WastedCoastDB then return end
    if event == "PLAYER_LOGIN" then
        DB()
        -- Lidt efter, så gruppen og vennerne er indlæst, før dagens øjebliksbillede tages
        C_Timer.After(1, function() if WastedCoastDB.me then pcall(A.EnsureDay) end end)
        C_Timer.NewTicker(60, function() pcall(A.Track) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Kun ved et rigtigt login: ikke ved /reload eller når man skifter zone
        if shownThisSession or isInitial == false or isReload == true then return end
        shownThisSession = true
        C_Timer.After(A.SHOW_DELAY, function()
            local db = WastedCoastDB
            if db and db.me and db.settings.avis ~= false then pcall(A.Show, true) end
        end)
    end
end)
