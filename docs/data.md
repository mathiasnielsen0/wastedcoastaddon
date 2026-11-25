# Data (SavedVariables)

Alt gemmes i én global tabel, `WastedCoastDB` (`## SavedVariables` i `WastedCoast.toc`).
I koden hedder den `db` (i modulerne via en lokal `DB()`-funktion). WoW skriver den til
`WTF\Account\<konto>\SavedVariables\WastedCoastDB.lua` ved logout og `/reload`.

`InitDB()` i `WastedCoast.lua` opretter kernens felter og laver migreringer.
`SCHEMA = 5` (`db.schemaVersion`) er dataformatets version. Hvert modul opretter sine egne
felter med `db.x = db.x or {}` første gang, det bruger dem.

## Regler

- **Spillernes data må aldrig gå tabt.** Nye felter oprettes med `or {}`/`== nil`-tjek, gamle
  felter migreres i `InitDB` (se migreringen fra v0.2), og mappen hedder stadig `WastedCoast`,
  så SavedVariables følger med.
- Demo-data (`/wc4ever demo`) markeres med `demo = true` på posten (eller i `db.demoAch`), sendes
  aldrig til vennerne og fjernes af `/wc4ever demo slut`. Nye moduler med demo-data skal følge
  samme mønster (se `ns.MakePrankDemo` / `ns.ClearPrankDemo` i `Drilleri.lua`).
- Lister, der vokser, har et loft (fx `LOG_MAX` i `Haan.lua`), så filen ikke bliver uendelig.
- Nøglen til en ven er vennens faste ID (`Groups.lua`). De 8 oprindelige venner har deres navn
  som ID (`ns.LEGACY_ROSTER`).

## Kernen (`WastedCoast.lua`)

| Felt | Indhold |
|---|---|
| `me`, `myId`, `myName` | Hvem du er (ID og valgt navn). Sættes af `Groups.lua` |
| `group` | Din gruppe: id, kode, admin, `members`, fjernede medlemmer (`Groups.lua`). `members[id].dup` = det ID, en dublet er slået sammen med (kun lokalt, sendes ikke) |
| `friends[ven]` | `{ chars = { [karakter] = { class, level, gold, zone, seen, xp, surname, hb, prof, gear, rep, honor, played } }, session, ver }` (`ver` = vennens addon-version fra livstegnet, v0.31.3) |
| `chars[karakter]` | Hvilken ven en karakter tilhører |
| `events`, `seen` | Dødsfald og ID'er til at fjerne dubletter |
| `loot`, `lootSeen` | Loot wins og ID'er |
| `runs[ven][instans]` | `{ wipes, clears, boss = { navn = antal }, last }` |
| `ach[ven][trofæ]` | Tidspunkt trofæet blev låst op. `achInit`, `demoAch` |
| `rolls[ven]` | Roll-statistik, need/greed-tal (`ROLL_TYPE_FIELDS`) og seneste rolls (`last`) |
| `goldHist`, `goldChar`, `goldCharSince` | Guldmålinger (samlet og pr. karakter) |
| `legacy[ven]` | Legacy points (Forever) |
| `session` | Login-session (`ns.MySession`) |
| `settings` | Indstillinger, se nedenfor |

## Modulerne

| Felt | Modul |
|---|---|
| `needWatch`, `needShame`, `emoteStats`, `levelAt`, `myLevelT` | `Drilleri.lua` |
| `duels[ven]` | `Dueller.lua` |
| `bank[ven]` | `Bank.lua` |
| `gossip` | `Gossip.lua` |
| `rareLog`, `rareKills` | `Rares.lua` |
| `stomi` | `Stomi.lua` |
| `haan` | `Haan.lua` |
| `gz` | `Gz.lua` |
| `hjemmesko` (kun `log`; AFK-tilstanden ligger kun i sessionen) | `Hjemmesko.lua` |
| `weekly` | `Weekly.lua` |
| `playedDay[ven][dag]` (sekunder spillet den dag; dag = dagnummer i dansk tid), `playedDayLast[ven][karakter]` (`{ s, at }`, kun dine egne: spilletid ved sidste måling), `playedDaySince`, `playedDayDemo` (demo, sendes aldrig) | `Spilletid.lua` |
| `milestones` (`hit["kategori:mål"] = { t, by, s, shown }`, `init`) | `Milestones.lua` |
| `avis` (`day`, `n`, `base` = dagens øjebliksbillede, `hist[dato]` = levels de seneste 14 dage; `on`, `peak` og `duo` fra v0.30 bruges ikke længere) | `Avis.lua` |

Spilletid ligger på karakteren (`friends[ven].chars[karakter].played`, `Played.lua`).

## `db.settings`

Lokale valg, som aldrig synkes: `toasts`, `lootToasts`, `rareToasts`, `sound`, `announce`,
`minQuality`, `fallbackSync`, `lang`, `skin`, `pos`, `minimapAngle`, `minimapHide`,
`surnames`, `bar`, `barFolded` (`Bar.lua`), `emotes`, `obits` (`Drilleri.lua`), `gossip`, `stomi`,
`haan`, `gz`, `hjemmesko`, `milestones`, `avis`. Standardværdier sættes i `InitDB` eller i modulet. Tjek altid `~= false` for
indstillinger, der er slået til som standard, så gamle installationer uden feltet virker.
