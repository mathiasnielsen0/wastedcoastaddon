-- =============================================================================
-- Wasted Coast: egne lyde
--
-- Sådan gør du:
--   1. Læg dine lydfiler (.ogg eller .mp3) i mappen  WastedCoast\sounds\
--   2. Skriv filnavnene herunder, ud for det event de skal bruges til
--   3. Skriv /reload i spillet og test med  /wc4l sound death
--
-- Står der flere filer på et event, vælges en tilfældig hver gang.
-- Findes filen ikke, bruger addonet i stedet Blizzards egen lyd (hvis der er en).
-- Filnavne må ikke indeholde mellemrum eller æ/ø/å.
--
-- Events:
--   death        en ven dør (dig selv inklusive)
--   loot         en ven vinder epic loot
--   wipe         hele partyet er dødt i en dungeon eller raid
--   online       en ven logger ind
--   levelup      en ven stiger i level
--   achievement  nogen låser et achievement op
--   bosskill     du dræber en boss
-- =============================================================================
local _, ns = ...

ns.sounds = {
    -- Gælder for alle venner:
    -- death       = { "death1.ogg", "death2.ogg" },
    -- loot        = { "kaching.mp3" },
    -- wipe        = { "healer.ogg" },
    -- online      = { "hej.ogg" },
    -- levelup     = { "ding.ogg" },
    -- achievement = { "tada.ogg" },
    -- bosskill    = { "boss.ogg" },

    -- Egen lyd til bestemte venner. Den vinder over lydene ovenfor.
    -- Navnet skal være det samme som i vennelisten (Mikkel, Mathias, Nick osv.).
    friends = {
        -- Mikkel = { death = { "mikkel_dod.ogg" } },
        -- Nick   = { death = { "nick_av.ogg" }, loot = { "nick_yes.ogg" } },
    },
}
