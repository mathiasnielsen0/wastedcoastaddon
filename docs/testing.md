# Tests

Testene kører hele addonet i en ægte Lua 5.1 (via Python-pakken `lupa`) mod en lille attrap
af WoW's API. Der er ingen spilklient involveret.

```bash
pip install lupa
python tests/run_all.py          # alle testfiler i alle varianter, parallelt
python tests/run_all.py haan     # kun testfiler med "haan" i navnet
python tests/test_haan.py WastedCoast forever   # én fil, én variant
```

`run_all.py` kører hver `tests/test_*.py` som standard (TBC) og med `forever`.
`test_drilleri.py` kører i stedet standard og `native` (spillets egne rammer). Scriptet tjekker
også, at fillisten i `wowmock.py` passer med `.toc`, og afslutter med kode 1 ved fejl.

## Attrappen (`tests/wowmock.py`)

- `MOCK`: Lua-kode med falske API-funktioner (`UnitName`, `GetMoney`, `CreateFrame`,
  `C_Timer`, `GameTooltip` …) og globale tabeller, testene kan kigge i:
  `SENT` (sendte addon-beskeder), `PRINTS` (chat), `TIMERS`, `TICKERS`, `FRAMES`, `EMOTES`.
- `NOW` og `CLOCK` er tiden (`time()` og `GetTime()`). Skru dem frem for at teste cooldowns.
- `Fire(event, ...)` sender et event til alle frames, der har registreret det.
- `RunTimers()` kører ventende `C_Timer.After`-callbacks.
- `FILES` og `load_addon(lua, dir, ns)` indlæser addonets filer i `.toc`-rækkefølge.
- Lua kører i C-locale ligesom i spillet (ellers ødelægger `string.lower` "å" på Windows).

Mangler testen en API-funktion, så tilføj den i `MOCK` (eller i testfilen, hvis den kun bruges
der).

## En testfil

Kopiér strukturen fra en nyere fil, fx `tests/test_haan.py` eller `tests/test_weekly.py`:

1. Læs `sys.argv` (`ADDON`, `FOREVER`), opret `LuaRuntime`, kør `MOCK`.
2. For Forever: overskriv `GetBuildInfo` til interface 16001, og flyt item-API'et ind i
   `C_Item` (sæt de globale `GetItemInfo` osv. til `nil`).
3. `load_addon(lua, ADDON, ns)`.
4. Testene er én Lua-streng (`TESTS`) med små hjælpere: `check(cond, msg)`, `hb(...)` (falsk
   livstegn fra en ven), `pump()` (tømmer sendekøen), `sentWith("XH;")` (sendte beskeder af en
   type), `split(msg)` og `printed(tekst)`.
5. Afslut med `return PASSES` og `print("OK,", passes, "checks passed", ...)`.

## Hvad en ny feature bør teste

- Det sker lokalt (data i `db`, toast, chat).
- Den rigtige besked bliver sendt (`sentWith`), og en modtaget besked fra en ven virker
  (`Fire("CHAT_MSG_ADDON", "WCOAST", besked, "GUILD", karakter)`).
- Ødelagte eller ondsindede beskeder (manglende felter, ukendt ven, tekst i talfelter)
  crasher ikke og gemmer intet.
- Cooldowns og indstillinger, der slår featuren fra.
- Synk (`ns.SendMyExtras`) og demo (`/wc4ever demo` og `demo slut`).
- Engelsk: `test_language.py` åbner alle sider, kører en liste af slash-kommandoer og sender
  nogle beskeder ind, og fejler, hvis der står dansk i den viste tekst. Tilføj featurens
  kommandoer og beskeder dér, så dens tekster også bliver tjekket.
- Begge spilversioner.
