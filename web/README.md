# Skammens Hat (skammenshat.dk)

Websitet, der viser WC4ever-addonets data: hvem der bærer Skammens hat, banden, ranglisten,
kirkegården, loot, drillerier og trofæer. Det kører gratis som en Cloudflare Worker.

```
WoW (logout / /reload)
  -> WastedCoast.lua i WTF\Account\<konto>\SavedVariables
  -> WC4everSync.exe på din pc (sync/) gzip'er filen og sender den
  -> POST /api/upload (worker.js) gemmer den i Cloudflare KV
  -> skammenshat.dk henter den, pakker ud og læser Lua-tabellen i browseren (lua.js, app.js)
```

Addonet synker allerede alles data mellem vennerne i spillet, så det er nok, at én pc sender.
Sender flere, vinder den nyeste upload pr. spilversion (`_forever_`, `_anniversary_` osv.).

## Filer

| Fil | Indhold |
|---|---|
| `worker.js` | API'et: `POST /api/upload`, `GET /api/list`, `GET /api/data?flavor=` |
| `wrangler.toml` | Cloudflare-opsætningen (navn, KV-lager, mappen `public/`) |
| `public/index.html`, `style.css`, `app.js` | Selve siden |
| `public/lua.js` | Læser SavedVariables-formatet (Lua-tabeller) til JS |
| `tools/preview.js` | Laver én HTML-fil med indbyggede data: `node tools/preview.js WastedCoast.lua ud.html Mathias` |

Workeren læser aldrig Lua-filen, den gemmer den bare. Al logik ligger i `app.js`, så nye ting
på siden kræver kun en ændring her og et push til main.

## Sådan sættes det op (én gang)

1. **Domænet over på Cloudflare.** Opret en gratis konto på https://dash.cloudflare.com, vælg
   *Add a domain*, skriv `skammenshat.dk` og vælg *Free*. Cloudflare viser to navneservere. Log
   ind hos den, du købte domænet hos, og skift domænets navneservere til de to. Det kan tage
   nogle timer, før Cloudflare skriver, at domænet er *Active*. Resten kan godt laves imens.
2. **Opret websitet fra GitHub.** I Cloudflare: *Workers & Pages* → *Create* → *Import a
   repository* → forbind GitHub og vælg `wastedcoastaddon`. Sæt *Project name* til `wc4ever` og
   *Root directory* (under *Advanced settings*) til `web`. Resten lader du stå. Tryk *Deploy*.
   Herefter deployer Cloudflare selv, hver gang der pushes til main.
3. **Upload-nøglen.** Åbn workeren → *Settings* → *Variables and Secrets* → *Add*. Type: *Secret*,
   navn: `UPLOAD_KEY`, værdi: nøglen (den samme som i `wc4ever-sync.ini`). Gem og deploy.
4. **Domænet på websitet.** Når domænet er *Active*: workeren → *Settings* → *Domains & Routes*
   → *Add* → *Custom domain* → `skammenshat.dk` (og evt. `www.skammenshat.dk`).
5. **Sync-programmet.** Kør `WC4everSync.exe` på din pc, se [sync/README.md](../sync/README.md).

Indtil domænet virker, ligger siden på `https://wc4ever.<dit-navn>.workers.dev`. Sync-programmet
prøver selv igen, så det sender til skammenshat.dk, så snart domænet er klar.

**Hvis det første deploy fejler med en besked om KV:** gå til *Storage & Databases* → *KV* →
*Create* (navn `wc4ever-data`), kopiér ID'et og skriv `id = "<ID>"` under `binding = "WC_DATA"`
i `wrangler.toml`.

## Lokalt

```bash
cd web
echo UPLOAD_KEY=test123 > .dev.vars
npx wrangler dev            # http://localhost:8787
```

Send en fil til den lokale server med sync-programmet (`url = http://127.0.0.1:8787` i ini-filen
og `--nu`), eller med curl:

```bash
gzip -c WastedCoast.lua | curl -X POST -H "Authorization: Bearer test123" \
  --data-binary @- "http://localhost:8787/api/upload?flavor=_forever_&navn=Test"
```
