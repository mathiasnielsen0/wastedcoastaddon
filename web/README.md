# Skammens Hat (skammenshat.dk)

Websitet, der viser WC4ever-addonets data: hvem der bærer Skammens hat, banden, ranglisten,
kirkegården, loot, drillerier og trofæer. Next.js på Vercel med en Neon Postgres-database,
begge gratis.

```
WoW (logout / /reload)
  -> WastedCoast.lua i WTF\Account\<konto>\SavedVariables
  -> WC4everSync.exe på din pc (sync/) gzip'er filen og sender den
  -> POST /api/upload gemmer den i Neon (én række pr. spilversion)
  -> forsiden læser Lua-tabellen på serveren (lib/lua.ts), regner tallene ud (lib/model.ts) og tegner siden
```

Addonet synker allerede alles data mellem vennerne i spillet, så det er nok, at én pc sender.
Sender flere, vinder den nyeste upload pr. spilversion (`_forever_`, `_anniversary_` osv.).

## Filer

| Fil | Indhold |
|---|---|
| `app/page.tsx` | Forsiden (`?v=_anniversary_` skifter spilversion) |
| `components/Site.tsx` | Alle sektionerne; `RankTable.tsx` er den sorterbare rangliste |
| `app/globals.css` | Designet |
| `app/api/upload/route.ts` | `POST /api/upload` (nøgle i `Authorization: Bearer ...`, body = gzip af WastedCoast.lua) |
| `app/api/list/route.ts`, `app/api/data/route.ts` | Hvilke versioner der findes, og den rå fil (gzip) |
| `lib/lua.ts` | Læser SavedVariables-formatet (Lua-tabeller) |
| `lib/model.ts` | Addonets data -> det, siden viser (Skammens hat, trofæer, ranglisten ...) |
| `lib/store.ts` | Neon-tabellen `savedvars` (oprettes selv ved første upload) |

Får addonet nye felter (docs/data.md), skal de bare læses i `lib/model.ts` og vises i `components/Site.tsx`.

## Sådan sættes det op (én gang)

1. **Opret projektet.** Log ind på https://vercel.com med GitHub. *Add New* → *Project* → vælg
   `wastedcoastaddon` → *Import*. Sæt *Root Directory* til `web` (Framework: Next.js vælges selv).
   Fold *Environment Variables* ud og tilføj `UPLOAD_KEY` med nøglen fra `wc4ever-sync.ini`.
   Tryk *Deploy*. Derefter deployer Vercel selv, hver gang der pushes til main.
2. **Databasen.** I projektet: *Storage* → *Create Database* → *Neon* → gratis plan → *Connect*
   til projektet. Det sætter `DATABASE_URL` af sig selv. Gå til *Deployments* og vælg *Redeploy*
   på det nyeste deploy, så den nye variabel kommer med.
3. **Domænet.** *Settings* → *Domains* → *Add* → `skammenshat.dk` (sig ja til også at tilføje
   `www`). Vercel viser de DNS-records, domænet skal have. Log ind der, hvor du købte domænet, og
   indtast dem. Det kan tage op til et par timer.
4. **Sync-programmet.** Kør `WC4everSync.exe` på din pc, se [sync/README.md](../sync/README.md).

Indtil domænet virker, ligger siden på `https://<projektnavn>.vercel.app`. Sync-programmet prøver
selv igen, så det sender til skammenshat.dk, så snart domænet er klar.

Tip: under *Settings* → *Build and Deployment* → *Root Directory* kan du slå *Skip deployments
when there are no changes to the root directory* til, så en ændring i addonet ikke bygger siden.

## Lokalt

```bash
cd web
npm install
npm test                                              # tester Lua-læseren
WC_LOCAL_STORE=.lokal-data UPLOAD_KEY=test123 npm run dev   # http://localhost:3000 uden database
```

Med `WC_LOCAL_STORE` gemmes uploads i en mappe i stedet for Neon. Send en fil med
sync-programmet (`url = http://127.0.0.1:3000` i ini-filen og `--nu`), eller med curl:

```bash
gzip -c WastedCoast.lua | curl -X POST -H "Authorization: Bearer test123" \
  --data-binary @- "http://localhost:3000/api/upload?flavor=_forever_&navn=Test"
```
