local _, ns = ...

-- =============================================================================
-- Sprog: dansk (standard) eller engelsk.
--   Teksterne står på dansk i koden. ns.L(tekst) giver den engelske udgave (fra
--   Locale_en.lua), når sproget er engelsk, og ellers teksten selv.
--   Sproget er en lokal indstilling (db.settings.lang) og læses, når addonet
--   indlæses. Skift kræver /reload, fordi vinduerne bygges én gang.
--   Tabeller med tekster, der står direkte i filerne (fx dødsannoncer og trofæer),
--   registreres med ns.LT og oversættes på stedet, når sproget sættes.
-- =============================================================================
ns.lang = "da"
ns.EN = ns.EN or {}
ns.LANGS = { "da", "en" }
ns.LANG_NAMES = { da = "Dansk", en = "English" }

function ns.L(s)
    if ns.lang == "en" and type(s) == "string" then return ns.EN[s] or s end
    return s
end

local tables = {}
function ns.LT(t)
    tables[#tables + 1] = t
    return t
end

local function Translate(t, seen)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "string" then
            local e = ns.EN[v]
            if e then t[k] = e end
        elseif type(v) == "table" then
            Translate(v, seen)
        end
    end
end

-- Sætter sproget. Tabellerne oversættes kun én gang (fra dansk til engelsk).
local applied = false
function ns.SetLanguage(lang)
    ns.lang = (lang == "en") and "en" or "da"
    if ns.lang == "en" and not applied then
        applied = true
        local seen = {}
        for _, t in ipairs(tables) do Translate(t, seen) end
    end
end

-- Tolker et sprogvalg, som brugeren skriver (da, dansk, en, english ...)
function ns.ParseLanguage(s)
    s = tostring(s or ""):lower()
    if s == "da" or s == "dk" or s == "dansk" or s == "danish" then return "da" end
    if s == "en" or s == "eng" or s == "engelsk" or s == "english" then return "en" end
end
