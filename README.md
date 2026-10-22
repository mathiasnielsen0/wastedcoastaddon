# Wasted Coast (WC4L)

Addon til vennegruppen: grafisk overblik over jer alle, et scoreboard, en oversigt
over alle karakterer hver ven spiller, en loot-tracker for rare og bedre, en
dødstæller, wipe- og boss-tæller pr. instance, egne trofæer, popups og en
levelling-race. Alt synkroniserer mellem jer.

Version 0.4.0 (TBC Classic Anniversary, interface 20506)

---

## Installation

### Windows, med installeren

1. Pak zip-filen ud (hele den, ikke kun én fil).
2. Dobbeltklik på `install.bat`.
3. Vælg version (3 = Anniversary) og følg anvisningerne.
4. Start WoW, eller skriv `/reload` hvis spillet allerede kører.

### Manuelt (Windows og Mac)

Kopiér mappen `WastedCoast` ind i den rigtige AddOns-mappe:

| Version | Windows | Mac |
|---|---|---|
| Classic Era | `World of Warcraft\_classic_era_\Interface\AddOns\` | `/Applications/World of Warcraft/_classic_era_/Interface/AddOns/` |
| Classic | `World of Warcraft\_classic_\Interface\AddOns\` | `/Applications/World of Warcraft/_classic_/Interface/AddOns/` |
| TBC Classic Anniversary | `World of Warcraft\_anniversary_\Interface\AddOns\` | `/Applications/World of Warcraft/_anniversary_/Interface/AddOns/` |

Til sidst skal du have: `...\AddOns\WastedCoast\WastedCoast.toc`
(altså `.toc`-filen direkte i mappen, ikke i en undermappe).

### Opdatering

Kør `install.bat` igen (eller overskriv mappen manuelt) og skriv `/reload`.
Dine gemte data bliver ikke slettet. Gamle data fra 0.2 og 0.3 bliver flyttet over
automatisk. Første gang med 0.4 låser addonet de trofæer op, du allerede har
fortjent, uden at vise en byge af popups.
**Alle bør opdatere**, ellers kan nogle ikke se hinandens instans-tal, trofæer
og popups.
**Nye filer:** `Sounds.lua` og mappen `sounds`. Kopiér hele `WastedCoast`-mappen.

---

## Første gang

Når du logger ind, spørger addonet: **"Hvem er du?"** Vælg dit navn på listen.
Det gælder hele din konto, så alle dine karakterer bliver koblet til dig.
Du kan skifte senere med knappen "Skift" nederst i vinduet eller `/wc4l jeg`.

Skriv `/wc4l` for at åbne vinduet. Vil du se, hvordan det ser ud med data i,
så skriv `/wc4l demo` (og `/wc4l demo slut` for at fjerne det igen).

---

## Hvad kan det?

### Overblik
Et kort for hver ven med klasse-ikon, navn, den karakter vedkommende spillede
sidst, level, zone, online-prik, antal dødsfald, antal rare+ loot (med bar),
antal karakterer og titler. Hold musen over et kort for at se alle vennens
karakterer, "værste fjende" og seneste loot. Klik på et kort for at se alle
karakterer. Nederst står de seneste dødsfald og det seneste loot.

### Scoreboard
Alle venner i en rangliste. Klik på en kolonne for at sortere (klik igen for at
vende rækkefølgen): navn, højeste level, antal karakterer, døde, loot, point og
guld. Guld er summen af alle vennens karakterer. Førstepladsen får guldkant, og
din egen række er markeret.

**Point = loot x 5 + højeste level - døde x 3.**

### Karakterer
Vælg en ven til venstre og se **alle karakterer vedkommende har været logget ind
med**: level, døde, rare+ loot og hvornår karakteren sidst var online og hvor.
Hold musen over en karakter for guld og flere detaljer. Har en ven mange
karakterer, kan du rulle med musehjulet. Knappen "Se loot" hopper til lootlisten
filtreret til den ven.

En karakter dukker først op, når vennen har logget ind med den og addonet var
aktivt (eller når vennens andre klienter sender den under synk).

### Loot
Alle loot wins af kvalitet **rare eller bedre**, nyeste først. For hver vinder
ses item (med ikon og farve), hvem der vandt det (ven og karakter), **hvordan**
og **hvor**:

- **Hvordan:** Need, Greed, Disenchant, Roll (roll-sejr uden kendt valg) eller
  Drop (looted direkte, fx boss-drop uden roll eller fra loot master)
- **Hvor:** Dungeon, Raid, Verden eller PvP, plus zonens eller instansens navn

Filtrér på type (Alle, Dungeon, Raid, Verden, PvP) og på ven. Hold musen over et
item for Blizzards egen tooltip, og shift-klik for at sætte linket i chatten.

Hvad der **ikke** tæller: items fra quests, bytte og crafting, items andre
vinder, og crafting-materialer (fx Void Crystals fra disenchant). Vil du kun have epic og bedre,
så skriv `/wc4l loot epic` (og `/wc4l loot rare` for at gå tilbage).

### Instanser
Vælg en ven og se, hvor mange gange vedkommende har **klaret** hver dungeon og
raid (clear), hvor mange **wipes** der har været, og hvor mange af instancens
bosser der er dræbt (fx 3/4). Klik på en instance for at se **hver boss** med
antal kills. Slutbossen er markeret med en stjerne, og det er den, der giver en
clear. Hold musen over en instance for en hurtig oversigt.

- **Wipe:** alle i din gruppe (eller 90 % i en raid) er døde eller spøgelser, og
  der har lige været kamp. Hver spiller får sit eget wipe talt med.
- **Boss kill:** registreres via spillets boss-events og via kamploggen. Navnene
  på bosserne står i addonet på engelsk, så det virker med en engelsk klient.
  Instanser, addonet ikke kender, tæller stadig wipes og bosser, men aldrig clears.

### Trofæer
28 egne achievements til gruppen, fx *Første til at dø*, *Tyngdekraften vinder*
(dø af fald), *AFK midt i en pull*, *Gulvet er lava*, *Hat-trick*, *Ærkefjenden*,
*Healeren er ikke hjemme*, *Wipe-veteran*, *Lilla fingre* og *Nattergalen*.
Når du låser et op, kommer der en guldfarvet popup i Blizzard-stil, og vennerne
får en lille besked om det. Fanen **Trofæer** viser alle trofæerne, hvem der har
dem (hold musen over), og du kan skifte mellem venner. Rul med musehjulet.

### Race
En bar pr. ven, der viser, hvem der er længst fremme (vennens karakter med
højest level, inkl. XP-procent). Den forreste har guldkant, og barren bliver
guld ved level 70.

### Popups (toasts)
Små beskeder øverst på skærmen:
- **Ven logger ind** (højst en gang pr. ven pr. 10 minutter)
- **Ven stiger i level**
- **Wipe:** "Hvad FAaanden laver healer mand, kraftedme hele *Navn* party er død
  i *Instance*" (sendes til alle med addonet)
- **Boss nedlagt** og **instance klaret** (kun til dig)
- **Trofæer** (dine egne som stor popup, vennernes som lille)

Slå dem fra med `/wc4l toast`, og se eksempler med `/wc4l testtoast`.

### Egne lyde
Læg dine egne lydklip (`.ogg` eller `.mp3`) i mappen `WastedCoast\sounds` og skriv
filnavnene i `Sounds.lua` (der står en vejledning i filen). Du kan vælge lyd til
disse events: `death`, `loot`, `wipe`, `online`, `levelup`, `achievement`,
`bosskill`, og give hver ven sin egen lyd (fx Nick har sit eget *av*-skrig).
Står der flere filer på et event, vælges en tilfældig. Test med
`/wc4l sound death`. Uden egen lyd bruger addonet Blizzards lyd til dødsfald,
wipes, level-up og trofæer, mens loot, online og bosskill er tavse.
Efter du har lagt **nye lydfiler** i mappen, skal spillet genstartes helt (ikke
kun `/reload`).

### Titler
Uddeles automatisk og vises på kortene og under scoreboardet:
- **Klovnen**: flest dødsfald
- **Lootgoblin**: flest rare+ loot
- **Rigmanden**: mest guld i alt
- **Højest level**
- **Alt-junkie**: flest karakterer (mindst to)
- **Wipe-konge**: flest wipes

---

## Kommandoer

| Kommando | Hvad den gør |
|---|---|
| `/wc4l` | Vis/skjul vinduet |
| `/wc4l jeg` | Vælg, hvem du er |
| `/wc4l loot` | Vis, hvilken kvalitet loot registreres fra |
| `/wc4l loot epic` | Registrér kun epic og bedre (også `uncommon`, `rare`, `legendary`) |
| `/wc4l demo` | Fyld med demo-data, så du kan se, hvordan det ser ud (kun lokalt) |
| `/wc4l demo slut` | Fjern demo-data igen (rører ikke dine rigtige data) |
| `/wc4l sync` | Bed vennerne sende deres data igen |
| `/wc4l sound` | Slå lyd til/fra |
| `/wc4l sound <event>` | Test en lyd: `death`, `loot`, `wipe`, `online`, `levelup`, `achievement`, `bosskill` |
| `/wc4l toast` | Slå popups (online, level, wipe) til/fra |
| `/wc4l testtoast` | Vis eksempler på popups (sendes ikke til de andre) |
| `/wc4l announce` | Slå chat-beskeder til/fra (dødsfald og loot) |
| `/wc4l test` | Lav et falsk dødsfald (sendes ikke til de andre) |
| `/wc4l testloot` | Lav en falsk loot win (sendes ikke til de andre) |
| `/wc4l reset ja` | Slet alle data (inkl. valg af, hvem du er) |

`/wastedcoast` virker også.

---

## Sådan virker synkroniseringen

- Alt sendes via usynlige addon-beskeder i **party, raid og guild**. Det kræver,
  at I har addonet og er i samme guild (eller gruppe).
- **Online-status:** Hver spiller sender et livstegn hvert minut. En ven vises som
  online, hvis der er hørt fra vedkommende inden for de seneste par minutter.
  Level, klasse, zone og guld følger med.
- **Karakterer:** Hver gang du logger ind, bliver den karakter registreret hos dig
  selv. Når nogen beder om en synk, sender du alle dine karakterer med.
- **Loot og dødsfald:** Registreres af den, der vinder eller dør, og sendes til
  alle med det samme.
- **Instanser og trofæer:** Hver spiller tæller sine egne wipes, clears og
  bosskills og sender de samlede tal. Trofæer sendes, når de låses op. Ved
  synk sendes alle dine egne tal og trofæer igen.
- **Wipe-popup:** Sendes, når hele din gruppe er død. Flere i samme gruppe giver
  kun én popup hos de andre.
- **Når du logger ind:** Addonet beder vennerne om at sende deres egne karakterer,
  dødsfald og loot (de seneste 60 af hver), så du får historikken, selvom du har
  været offline.

---

## Hvor ligger dataene?

Når du logger ud eller skriver `/reload`, gemmer WoW dem her:

```
World of Warcraft\_anniversary_\WTF\Account\<DIT KONTONAVN>\SavedVariables\WastedCoastDB.lua
```

(Eller `_classic_` / `_classic_era_` afhængigt af version.) Den fil kan senere
bruges til at uploade data til et website.

---

## Ændre vennerne

Listen står øverst i `WastedCoast.lua`, i linjen der starter med
`local ROSTER = {`. Navnene bestemmer rækkefølgen på kortene. Alle skal have
samme liste, så del den ændrede fil med gruppen. Der er plads til otte venner
i layoutet.

---

## Fejlfinding

**Addonet er ikke på listen ved karaktervalg**
Tjek, at `WastedCoast.toc` ligger direkte i `AddOns\WastedCoast\`, og at du
bruger den rigtige mappe til din version.

**"Out of date"**
Sæt hak i "Load out of date AddOns" på addon-skærmen. Eller ret tallet i
`WastedCoast.toc` (`## Interface:`) til det, spillet bruger. Skriv
`/dump select(4, GetBuildInfo())` i spillet for at se tallet.

**Vennerne vises som offline, eller deres karakterer mangler**
De skal have den nye version, have valgt, hvem de er, og være i samme guild
eller gruppe som dig. Prøv `/wc4l sync` og vent et halvt minut.

**Mit loot dukker ikke op**
Tjek kvaliteten med `/wc4l loot`, og at du har valgt, hvem du er (ellers
gemmes loot kun hos dig selv). Prøv `/wc4l testloot` for at se, om listen virker.
Virker det ikke med rigtigt loot, så skriv `/dump LOOT_ITEM_SELF` og send mig
teksten, så kan jeg tilpasse genkendelsen.

**Ingen lyd fra mine egne klip**
Tjek, at filen ligger i `WastedCoast\sounds`, at navnet i `Sounds.lua` er stavet
helt ens (ingen mellemrum, æ, ø eller å), og at du har genstartet spillet efter at
have lagt filen der. `/wc4l sound death` fortæller, hvad der gik galt.

**Bosser eller wipes tæller ikke**
Skriv `/dump GetInstanceInfo()` inde i instancen og send mig det første navn, så
kan jeg rette stavningen i addonet. Spillet skal køre på engelsk for bossnavnene.

**Lua-fejl**
Skriv `/console scriptErrors 1` og `/reload`, og send fejlteksten videre.

**Den gamle demo "VennerneForever" kører stadig**
Slet mappen `VennerneForever` fra AddOns.
