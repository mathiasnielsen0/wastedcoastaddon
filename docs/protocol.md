# Synk-protokollen

Alt, vennerne deler, går som usynlige addon-beskeder med prefix `WCOAST`
(`WastedCoast.lua`, `PREFIX`). En besked er felter adskilt af `;`. Felt 1 er
beskedtypen, felt 2 er næsten altid afsenderens ven-ID (`db.me`).

Kilden til sandheden er koden. Denne fil er et kort, så du ved, hvor du skal kigge.
Modulernes header-kommentar beskriver deres egne beskeder i detaljer.

## Regler

- **Bagudkompatibilitet:** venner kører forskellige versioner samtidig. Nye felter
  lægges **altid sidst** i en eksisterende besked, og modtageren skal tåle, at de
  mangler (`nil`). Se fx `R` (v0.21) og felt 12-13 i `D`.
- En eksisterende beskedtype må aldrig skifte betydning, og felter må ikke byttes rundt.
  Har du brug for noget nyt, så lav en ny type. Nye drilleri-/sjov-typer får prefix `X`
  (dispatches i `ns.HandlePrankMessage` i `Drilleri.lua`).
- `;` må ikke stå i et felt: brug `Clean()` på fri tekst (zone, navne, items).
- **Max 255 tegn** pr. besked. Lange lister deles op (se `F`, `G`, `GC`); loot falder
  tilbage til `item:ID` (`SerializeLoot`).
- Modtageren validerer alt: kendt ven (`ROSTER_SET`), ikke dig selv (`friend ~= db.me`),
  tal med `tonumber`, tekst afkortet med `:sub(1, n)`. Ødelagte beskeder testes i
  `tests/test_robust.py`.
- Tal, der kun vokser (rolls, wipes, clears, boss-kills), flettes med "største vinder", så
  samme besked kan modtages mange gange.
- Hændelser (dødsfald, loot, dueller, prutter, stomi) har et ID, så dubletter filtreres.

## Afsendelse

`Send(msg, priority, bootstrap)` i `WastedCoast.lua` (eksporteres som `ns.core.Send`) lægger
beskeden i en kø, som tømmes af en ticker hvert 0,3 s (spillet tillader ca. én besked pr.
sekund). `priority = true` lægger den forrest (brug det til hændelser, ikke til synk-svar).

`route.Targets()` vælger vejene: den skjulte kanal (`WC4Lsync` for den gamle gruppe, ellers
afledt af gruppekoden i `Groups.lua`), og kun for venner, der ikke er hørt i kanalen, også
guild, party/raid eller whisper. `/wc4ever status` viser det live.

## Synk-flow

1. `Q;ven[;1|;0;L]` beder om data. `1` = tvunget ("Opdater"), `L` = let (automatisk hvert
   10. minut, kun det seneste).
2. Modtageren svarer via `route.reply.Queue` (ét fælles svar til alle, med throttling) og
   `RespondToSync(light)`: `GM`, `H`, `C` for alle egne karakterer, egne `D` og `L`, og
   `ns.SendMyExtras(light)`, som kalder hvert moduls sende-funktion.
3. Et nyt modul, der har data at synke, kobles på i `ns.SendMyExtras`
   (`WastedCoast.lua`, søg efter `function ns.SendMyExtras`).

## Beskedtyper

| Type | Felter efter typen | Hvad | Hvor (sender / modtager) |
|---|---|---|---|
| `H` | ven, karakter, klasse, level, guld, zone, xp, efternavn, session | Livstegn hvert minut | `SendHeartbeat` / `OnAddonMessage` |
| `C` | ven, karakter, klasse, level, guld, zone, sidst set, xp, efternavn | En (måske offline) karakter | `RespondToSync` / `OnAddonMessage` |
| `Q` | ven, tvunget, let | Synk-forespørgsel | `RequestSync` / `OnAddonMessage` |
| `D` | id, navn, klasse, dræber, evne, level, zone, tid, ven, dræber-level, efternavn, pvp | Dødsfald | `SerializeDeath` / `DeserializeDeath` |
| `L` | id, ven, karakter, klasse, item, kvalitet, hvordan, kontekst, zone, tid, navn | Loot win | `SerializeLoot` / `DeserializeLoot` |
| `S` | ven, instans, wipes, clears, sidst | Instans-tal | `WastedCoast.lua` / `HandleExtraMessage` |
| `B` | ven, instans, boss, antal | Boss-kills | samme |
| `W` | ven, instans, tid | Wipe (toast hos alle) | samme |
| `A` | ven, trofæ-id, tid | Trofæ låst op | samme |
| `R` | ven, rolls, wins, sum, cnt, low, high, nr, nw, gr, gw, dr, dw, pr | Roll-statistik (need/greed/de/pass fra v0.21) | `ns.SendRollSummary` / `HandleExtraMessage` |
| `G` | ven, `tid:kobber,...` | Guldhistorik (samlet, til ældre versioner) | `ns.SendGoldHistory` / samme |
| `GC` | ven, karakter, `tid:kobber,...` | Guld pr. karakter (v0.18.7) | samme |
| `P` | ven, karakter, professions | Professions | `ns.SendProf` / samme |
| `E` | ven, karakter, ilvl×10, manglende enchants, manglende gems, tid | Gear | `ns.SendGear` / samme |
| `F` | ven, karakter, `fraktion=værdi,...` | Reputation | `ns.SendRep` / samme |
| `LP` | ven, points, challenges, tid | Legacy points (Forever) | `ns.SendLegacy` / `ns.OnLegacyMessage` |
| `HP` | ven, karakter, honor, kills, tid | Honor | `ns.SendHonor` / `ns.OnHonorMessage` |
| `PT` | ven, karakter, spilletid, tid i level, målt | `/played` | `Played.lua` |
| `BK` | ven, tid, dg, wg, di, wi, dv, wv, rep, grep, nrep, maxrep, top-hævet, top-indsat, siden | Guild bank og repair | `Bank.lua` |
| `RM` | ven, karakter, klasse, mob, level, klassifikation, zone, tid, guid | Rare mob dræbt | `Rares.lua` |
| `GM` | afsender, gruppe, medlem, navn, navn-tid, kom-med-tid | Gruppemedlem | `Groups.lua` |
| `GW` | afsender, gruppe | "Hvem er med?" | `Groups.lua` |
| `GK` | afsender, gruppe, medlem, tid, 1/0 | Admin fjerner/genoptager | `Groups.lua` |
| `XE` | fra, til, angreb-nr, nonce | Emote-angreb | `Drilleri.lua` |
| `XN` | id, ven, karakter, klasse, item, kvalitet, grund, tid, navn | Need-politiet | `Drilleri.lua` |
| `XK` | ven, tid, `roll,roll,...` | Seneste 30 rolls (held) | `Drilleri.lua` |
| `XL` | ven, level, tid, gæt | Hvornår højeste level blev nået (level-snegl) | `Drilleri.lua` |
| `XU` | ven, karakter, klasse, level, sekunder | Level-up toast | `Drilleri.lua` |
| `XD` | ven, id, karakter, modstander, vandt, flygtede, tid, zone | Duel | `Dueller.lua` |
| `XS` | fra, til, nonce, karakter, klasse, zone, item-id, kvalitet, guld, item-navn | Stomi-fælde sat | `Stomi.lua` |
| `XT` | offer, fra, nonce, resultat, tid, lokkemad | Svar på stomi-fælde | `Stomi.lua` |
| `XH` | fra, til, dødsfald-id, nonce, tekst-nr, lyd-nr, tid | Prut (hån-knappen) | `Haan.lua` |
| `XW` | ven, uge-nr, spilletid, levels | Egen spilletid og levels i ugen | `Weekly.lua` |
| `XP` | ven, `dag=sek,dag=sek,...` | Egen spilletid pr. dag (dagnummer i dansk tid). Største værdi vinder, deles op ved 255 tegn | `Spilletid.lua` |
| `XG` | fra, til, level, nonce, tekst-nr, tid | Gz (tillykke med levelet) | `Gz.lua` |
| `XZ` | ven, 1/0, sekunder AFK, zone | AFK i en by (1, ved start og hvert 5. min.) eller vågen (0) | `Hjemmesko.lua` |
| `XV` | fra, til, nonce, tekst-nr, tid | Prik til en sovende ven (vækkelyd) | `Hjemmesko.lua` |
| `XM` | fra, kategori, mål, tid, udløser, stille | Gruppe-milepæl nået (v0.29). Tidligste tid vinder; stille = ingen fest | `Milestones.lua` |

## Ny beskedtype: tjekliste

1. Vælg en ubrugt type (`grep -n 'kind == "XY"' WastedCoast/*.lua`). Sjov-features: `X`-prefix.
2. Beskriv formatet i modulets header-kommentar og tilføj en linje i tabellen ovenfor.
3. Send med `C.Send(msg, true)` for hændelser, og læg en sende-funktion i
   `ns.SendMyExtras`, hvis data skal med ved synk.
4. Modtag: `X`-typer i `ns.HandlePrankMessage` (`Drilleri.lua`), andre i `OnAddonMessage`
   (`WastedCoast.lua`). Valider alle felter.
5. Test afsendelse (`sentWith("XY;")`), modtagelse (`Fire("CHAT_MSG_ADDON", "WCOAST", ...)`) og
   en ødelagt udgave af beskeden.
