# Arkitektur

## Filer og indlæsning

WoW indlæser filerne i den rækkefølge, `WastedCoast/WastedCoast.toc` angiver. Alle filer får
samme private tabel `ns` (`local _, ns = ...`).

| Fil | Ansvar |
|---|---|
| `Locale.lua` | `ns.L(tekst)`, `ns.LT(tabel)`, sprogvalg. Skal indlæses først |
| `Locale_en.lua` | `ns.EN`: dansk tekst -> engelsk tekst |
| `Sounds.lua` | Spillernes egne lydfiler pr. event (redigeres af brugeren) |
| `WastedCoast.lua` | Kernen: db, netværk, dødsfald, loot, instanser, trofæer, guld, gear, rep, alle hovedsider, toasts, indstillinger, demo, events og slash-kommandoer. Eksporterer `ns.core` til sidst |
| `Groups.lua` | Grupper, koder, ID'er, admin, skjult kanal pr. gruppe |
| `Drilleri.lua` | Dødsannoncer, Skammens hat, Need-politiet, emote-angreb, held, level-snegl. Dispatcher alle `X*`-beskeder og modul-kommandoer (`ns.PrankSlash`) |
| `Dueller.lua` | Dueller |
| `Bank.lua` | Guild bank og repair |
| `Played.lua` | Spilletid og deaths/hr |
| `Gossip.lua` | Daglig sladder |
| `Rares.lua` | Rare mobs |
| `Stomi.lua` | Stomi-fælden |
| `Haan.lua` | Hån-knappen (prutter) |
| `Gz.lua` | Gz-knappen (tillykke med levelet) |
| `Hjemmesko.lua` | Hjemmesko-alarmen: zZz på sovende AFK-venner og vækkelyd |
| `Weekly.lua` | Ugens pokaler |
| `Milestones.lua` | Gruppe-milepæle (fælles mål og fest-popup) |
| `Avis.lua` | Wasted Coast Tidende: dagens avis ved login (historier med betingelser og vægt) |
| `Bar.lua` | Bande-baren og nyhedslisten (samler nyheder fra alle moduler) |

`tests/wowmock.py` har sin egen kopi af fillisten (`FILES`). Den skal holdes i takt med `.toc`.

## Kernen og modulerne

`WastedCoast.lua` er stor (~8000 linjer) og delt i sektioner med `-- ====`-overskrifter
(`grep -n '^-- [A-ZÆØÅ]' WastedCoast/WastedCoast.lua` giver en indholdsfortegnelse). Filen
er tæt på **Luas grænse på 200 lokale variabler** i ét scope: læg nye ting i et modul eller i
en eksisterende tabel (som `route` og `GAME`), ikke som nye `local` på topniveau.

Moduler indlæses efter kernen og bruger den via `local C = ns.core` (`ROSTER`, `ROSTER_SET`,
`Send`, `Print`, `Name`, `GAME`, UI-byggeklodser som `MakeBox`, `Txt`, `MakeButton` osv.). Har et
modul brug for noget nyt fra kernen, så tilføj det til `ns.core` med en kommentar om versionen.

Kernen kalder modulerne gennem valgfrie hooks på `ns`, altid beskyttet med `if ns.X then`
(modulerne findes ikke endnu, når kernen indlæses):

| Hook | Kaldes når |
|---|---|
| `ns.HandlePrankMessage(kind, t)` | En `X*`-besked kommer ind (videre til `ns.HandleStomiMessage`, `ns.HandleHaanMessage`, `ns.HandleHjemmeskoMessage`, `ns.HandleWeeklyMessage` …) |
| `ns.OnBankMessage`, `ns.OnPlayedMessage`, `ns.OnRareMessage` | Deres beskedtype kommer ind |
| `ns.SendMyExtras(light)` | Synk-svar: kalder `ns.SendPrankExtras`, `ns.SendBank`, `ns.SendPlayed`, `ns.SendWeekly` |
| `ns.OnFreshDeath(ev, friend)`, `ns.OnMyDeath(ev)` | Et nyt dødsfald (en vens eller dit eget) |
| `ns.OnFriendHeartbeat(...)` | Livstegn fra en ven |
| `ns.AfterEvent()` | Efter de fleste ændringer (trofæer m.m. tjekkes) |
| `ns.PrankSlash(cmd, arg)` | Ukendt slash-kommando (videre til `ns.StomiSlash`, `ns.HaanSlash`, `ns.GzSlash`, `ns.HjemmeskoSlash`, `ns.WeeklySlash`, `ns.AvisSlash`) |
| `ns.GossipSlash`, `ns.BarSlash` | Deres kommandoer |
| `ns.MakePrankDemo`, `ns.ClearPrankDemo` | `/wc4ever demo` og `demo slut` |
| `ns.RefreshUI()` | Kald den efter ændringer, der skal vises |

Moduler laver selv deres egen event-frame (`CreateFrame("Frame")` nederst i filen) og
tickers (`C_Timer.NewTicker`).

## Vinduet

`GROUPS` (`WastedCoast.lua`, sektionen "UI: hovedvindue") definerer de fem faner og deres
undersider. Sidenumrene er historiske: 1-7 er kernens første sider, resten er registreret i
`EXTRA_PAGES[n] = { build = ..., refresh = ... }`, enten i kernen (8-12, 16) eller i et
modul (13 Drilleri, 14 Dueller, 15 Bank, 17 Played, 18 Weekly, 19 Milestones, 20 Avis). En ny side får næste ledige
nummer og indsættes i `GROUPS`.

Der er to udseender: spillets egne rammer (`ns.native`, standard på Forever) og addonets
mørke stil (standard på TBC). `ns.UseNativeSkin()` afgør det, og `/wc4ever stil` skifter.
Test begge (`tests/test_drilleri.py WastedCoast native`).

Nyhedspanelet og bande-baren henter nyheder i `Bar.lua`, sladderen i `Gossip.lua` og avisen i `Avis.lua` (hver historie er et `add(rubrik, vægt, ven, overskrift, tekst)` i `A.Collect`). Et modul,
der skal give nyheder eller sladder, tilføjes eksplicit der.

## Spilversioner

`GAME` (`WastedCoast.lua`) har `isForever`, `isTBC`, `isEra`, `maxLevel` og `toc`.

- **TBC Anniversary** (interface 20506): combat log, `GetItemInfo` og andre globale API'er.
- **WoW Forever** (interface 16001): ingen combat log (registreringen fejler, så den er pakket
  i `pcall`), kun `C_Item`, karakterer har efternavn, max level 60, og nogle værdier er
  "secret values", som skal gennem `GAME.Plain(v)`, før de sammenlignes. Addon-beskeder kan
  være spærret under bosskampe; køen prøver igen.

Ny kode, der kalder spillets API, skal virke på begge. Brug `pcall` eller nil-tjek for API'er,
der ikke findes overalt, og kør testene med `forever`.

## Sprog

Al brugertekst står på dansk i koden og pakkes i `ns.L("...")` (eller i en tabel registreret med
`ns.LT`). Den engelske tekst lægges i `Locale_en.lua` med den danske tekst som nøgle, ordret,
inklusive farvekoder og `%s`. `tests/test_language.py` fejler, hvis der dukker dansk op i
engelsk tilstand.
