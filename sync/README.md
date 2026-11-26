# WC4ever Sync

Et lille Windows-program (én exe, ingen installation og ingen admin-rettigheder), der sender
WC4ever-addonets data til websitet [skammenshat.dk](https://skammenshat.dk), hver gang WoW
gemmer dem (når du logger ud eller skriver `/reload`).

## Sådan bruger du det

1. Læg `WC4everSync.exe` og `wc4ever-sync.ini` (du får den med nøglen af Mathias) i samme mappe,
   fx i Overførsler.
2. Dobbeltklik på `WC4everSync.exe`. Siger Windows "Windows beskyttede din pc", så tryk
   *Flere oplysninger* → *Kør alligevel* (programmet er ikke signeret).
3. Programmet kopierer sig selv til `%LOCALAPPDATA%\WC4everSync`, sender dine data med det samme
   og viser, hvad det sendte. Derefter kører det usynligt og starter selv med Windows.

Mangler ini-filen eller nøglen, åbner programmet Notesblok, så du kan skrive den. WoW-mappen
findes selv (registreringsdatabasen og de almindelige steder). Ligger den et andet sted, så
skriv `wow = D:\Spil\World of Warcraft` i ini-filen.

| Kommando | Hvad den gør |
|---|---|
| `WC4everSync.exe` | Installér/opdatér og start (kør den bare igen efter en ny version) |
| `WC4everSync.exe --nu` | Send dine data nu og vis resultatet |
| `WC4everSync.exe --fjern` | Stop programmet og fjern det fra Windows-opstart |

Loggen ligger i `%LOCALAPPDATA%\WC4everSync\wc4ever-sync.log`.

## Hvad det gør

- Hvert 10. sekund kigger det på `<WoW>\_<version>_\WTF\Account\<konto>\SavedVariables\WastedCoast.lua`
  for alle spilversioner (Forever, Anniversary osv.). Har man flere konti, bruges den nyeste fil.
- Når filen er ændret og har ligget stille i 3 sekunder, sendes den gzip-pakket til
  `<url>/api/upload` med nøglen. Fejler det, prøves igen efter 30 sekunder og op til 16 minutter.
- `state.json` husker, hvad der er sendt, så en genstart ikke sender det samme igen.

## Bygge og teste

```bash
cd sync
go test ./...
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-H=windowsgui -s -w" -o WC4everSync.exe .
```

Ren Go uden andre pakker. `win_windows.go` har det Windows-specifikke (beskedbokse, mutex,
autostart via `reg.exe`); `win_other.go` er attrapper, så testene kan køre på Linux og Mac.
Den byggede `WC4everSync.exe` ligger i repoet, så den kan hentes direkte fra GitHub.
