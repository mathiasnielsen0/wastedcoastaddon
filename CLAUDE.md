# Wasted Coast Forever (WC4ever)

WoW-addon til en vennegruppe: venneoverblik, scoreboard, loot, dødsfald, trofæer, drillerier og
meget mere, synkroniseret mellem vennerne med usynlige addon-beskeder. Lua 5.1, ingen
biblioteker. Samme mappe virker på **TBC Classic Anniversary** (interface 20506) og
**WoW Forever** (interface 16001).

Alt er på dansk: kode-kommentarer, brugertekst, README og commit-beskeder. Skriv også dansk.

## Layout

- `WastedCoast/`: addonet. Filrækkefølgen styres af `WastedCoast.toc`.
  `WastedCoast.lua` er kernen (~8000 linjer), resten er ét modul pr. feature.
- `tests/`: Python + `lupa` mod en WoW-attrap (`wowmock.py`).
- `README.md`: brugervejledningen til spillerne (installation, features, kommandoer).
- `docs/`: udviklerdokumentation, slå op efter behov:
  - [docs/architecture.md](docs/architecture.md): filer, `ns.core`, hooks, faner/sider, spilversioner, sprog
  - [docs/protocol.md](docs/protocol.md): alle synk-beskedtyper og reglerne for dem
  - [docs/data.md](docs/data.md): `WastedCoastDB` og hvilket modul ejer hvad
  - [docs/testing.md](docs/testing.md): attrappen og hvordan en testfil skrives

## Tests

```bash
pip install lupa
python tests/run_all.py
```

Kører alle testfiler i begge spilversioner (og `native`-stilen). Skal være grøn før commit.
`python tests/run_all.py haan` kører kun én fil. Ingen build-trin: addonet er filerne.

## Ny feature: tjekliste

Følg mønstret fra de seneste features (fx `Haan.lua`, `Weekly.lua`):

1. Nyt modul `WastedCoast/X.lua` med en header-kommentar: hvad featuren gør, beskedformater
   og `db`-felter. Brug `local C = ns.core` og `local L = ns.L`.
2. Tilføj filen i `WastedCoast.toc` **og** i `FILES` i `tests/wowmock.py` (samme rækkefølge;
   `run_all.py` tjekker det).
3. Kobl på kernen via hooks (`ns.HandlePrankMessage`, `ns.SendMyExtras`, `ns.PrankSlash`,
   `EXTRA_PAGES`, nyheder i `Bar.lua`, sladder i `Gossip.lua`), se docs/architecture.md.
4. Engelske tekster i `Locale_en.lua` for alle nye `L("...")`.
5. Test i `tests/test_x.py`, i begge versioner. Tilføj kommandoerne i `test_language.py`.
6. README: ny sektion under "Hvad kan det?", kommandotabellen, "Nye filer"-linjen og
   test-sektionen. Opdatér docs/protocol.md og docs/data.md, hvis der er nye beskeder eller felter.
7. Versionsbump (semver: ny feature = minor, rettelse = patch) i `WastedCoast.toc`
   (`## Version`), README linje 10 og versionslisten øverst i `WastedCoast.lua`.
8. Commit: `Kort dansk beskrivelse (vX.Y.Z)` og en brødtekst, der forklarer featuren.

## Regler, der ikke må brydes

- **Bagudkompatibel synk.** Venner kører forskellige versioner. Nye felter lægges sidst i en
  besked og må mangle; en beskedtype skifter aldrig betydning. Valider alt, der kommer ind.
  Max 255 tegn, og ingen `;` i felter (`Clean()`). Se docs/protocol.md.
- **Data må ikke gå tabt.** Nye `db`-felter oprettes med `or {}`, gamle migreres. Mappen
  hedder `WastedCoast`, prefix er `WCOAST`, og `/wc4l` virker stadig. Ændr ikke på det.
- **Al brugertekst gennem `ns.L`** (eller tabeller med `ns.LT`), på dansk i koden.
  `test_language.py` fejler, hvis der står dansk i engelsk tilstand.
- **Begge spilversioner.** Forever har ingen combat log, kun `C_Item`, efternavne og "secret
  values" (`GAME.Plain`). Brug `GAME.isForever`, `pcall` og nil-tjek på API'er.
- **Luas grænse på 200 lokale variabler**: `WastedCoast.lua` er tæt på. Læg nyt i et modul
  eller i en eksisterende tabel, ikke som nye top-level `local` i kernen.
- Demo-data markeres `demo = true` og sendes aldrig.
- Drillerierne er for sjov blandt venner: knapper i popups (stomi m.fl.) gør aldrig noget
  rigtigt i spillet (ingen handel, invites eller summons), og alt kan slås fra hos modtageren.

## Navigation

- Læs aldrig hele `WastedCoast.lua`. Find sektioner med
  `grep -n '^-- [A-ZÆØÅ]' WastedCoast/WastedCoast.lua` eller søg efter funktionsnavnet.
- Filerne er UTF-8 uden BOM. PowerShell 5.1's `Get-Content` viser æøå forkert; brug Read-værktøjet
  eller Bash. Gem altid som UTF-8.
- Synk-beskeder: `grep -n 'kind == "XH"' WastedCoast/*.lua` finder modtageren.
