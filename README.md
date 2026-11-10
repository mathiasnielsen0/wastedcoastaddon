# Wasted Coast Forever (WC4ever)

Addon til vennegruppen: grafisk overblik over jer alle, et scoreboard, en oversigt
over alle karakterer hver ven spiller, en loot-tracker for rare og bedre, en
dødstæller, wipe- og boss-tæller pr. instance, egne trofæer, popups, en
levelling-race, dødsstatistik, uheldsrating for rolls, en guldgraf, professions,
gear, reputation og drillerier (dødsannoncer, Skammens hat, Need-politiet,
emote-angreb og held-rangering). Alt synkroniserer mellem jer.

Version 0.18.2. Virker på både TBC Classic Anniversary (interface 20506) og
WoW Forever (interface 16001). Samme mappe bruges til begge.

Addonet hed før WC4L. Mappen hedder stadig `WastedCoast`, så jeres gemte data,
indstillinger og synk med venner på en ældre version virker uændret, og
`/wc4l` virker stadig ved siden af `/wc4ever`.

---

## Installation

### Windows, med installeren

1. Pak zip-filen ud (hele den, ikke kun én fil).
2. Dobbeltklik på `install.bat`.
3. Vælg version (3 = Anniversary, 4 = WoW Forever) og følg anvisningerne.
4. Start WoW, eller skriv `/reload` hvis spillet allerede kører.

### Manuelt (Windows og Mac)

Kopiér mappen `WastedCoast` ind i den rigtige AddOns-mappe:

| Version | Windows | Mac |
|---|---|---|
| Classic Era | `World of Warcraft\_classic_era_\Interface\AddOns\` | `/Applications/World of Warcraft/_classic_era_/Interface/AddOns/` |
| Classic | `World of Warcraft\_classic_\Interface\AddOns\` | `/Applications/World of Warcraft/_classic_/Interface/AddOns/` |
| TBC Classic Anniversary | `World of Warcraft\_anniversary_\Interface\AddOns\` | `/Applications/World of Warcraft/_anniversary_/Interface/AddOns/` |
| WoW Forever (beta) | `World of Warcraft\_classic_beta_\Interface\AddOns\` | `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/` |

Det endelige mappenavn for WoW Forever kendes først ved launch (4. november 2026).
Installeren prøver `_forever_` og derefter `_classic_beta_`.

Til sidst skal du have: `...\AddOns\WastedCoast\WastedCoast.toc`
(altså `.toc`-filen direkte i mappen, ikke i en undermappe).

### Opdatering

Kør `install.bat` igen (eller overskriv mappen manuelt) og skriv `/reload`.
Dine gemte data bliver ikke slettet. Gamle data fra 0.2 og 0.3 bliver flyttet over
automatisk. Med 0.5 kommer der fem nye faner; de fyldes, efterhånden som I logger ind
med den nye version. Første gang med 0.4 låser addonet de trofæer op, du allerede har
fortjent, uden at vise en byge af popups.
**Alle bør opdatere**, ellers kan nogle ikke se hinandens instans-tal, trofæer
og popups.
**Nye filer:** `Sounds.lua`, mappen `sounds`, (fra 0.6) `Drilleri.lua`, (fra 0.7.2) mappen `media`, (fra 0.9) `Dueller.lua`, (fra 0.10) `Groups.lua` (fra 0.11) `Bank.lua` og `Gossip.lua` (fra 0.13) `Played.lua`, (fra 0.16) `Rares.lua` og (fra 0.18) `Locale.lua` og `Locale_en.lua`. Kopiér hele
`WastedCoast`-mappen.

---

## Vinduet

Åbn med WC4ever-logoet ved minimappet eller `/wc4ever`. Der er fem faner, og hver har
nogle små undersider lige under fanerne:

| Fane | Undersider |
|---|---|
| **Venner** | Kort (forsiden), Karakterer, Gear, Professions, Reputation, Guld |
| **Rangliste** | Scoreboard, Spilletid, Race, Dueller, Bank & repair |
| **Loot** | Loot, Rolls |
| **Død** | Statistik, Instanser |
| **Sjov** | Trofæer, Drilleri |

Klik på en vens kort for at se vennens karakterer.

På WoW Forever bruger vinduet spillets egne rammer, faner og knapper, så det ligner resten
af Forevers UI: titellinje med logoet som portræt, fanerne hængende under vinduet og røde
knapper forneden. På TBC Anniversary bruger det addonets egen mørke stil. Skift med
`/wc4ever stil` og skriv `/reload` bagefter.

---

## Første gang: dit navn og din gruppe

Første gang du logger ind, åbner addonet vinduet **"Kom i gang"**:

1. **Skriv dit navn.** Det er det navn, vennerne ser. Du kan altid ændre det
   (knappen "Gruppe" nederst i vinduet eller `/wc4ever gruppe`). Bag navnet får du
   et fast, unikt ID, så dine data følger dig, selvom du skifter navn.
2. **Deltag i en vens gruppe:** indsæt koden, du har fået (den ligner
   `WC-ABCD-EFGH-JKLM-NPQR`), og tryk "Deltag".
   **Eller opret en ny gruppe:** du bliver admin og får en kode, som du sender til
   dine venner. Koden står altid i gruppevinduet, klar til Ctrl+C.

Navnet og gruppen gælder hele din konto, så alle dine karakterer bliver koblet til dig.
Der er plads til 10 venner i vinduet. Man er med i én gruppe ad gangen; indsætter du en
ny kode, skifter du gruppe.

**Admin** (den, der oprettede gruppen) kan fjerne medlemmer i gruppevinduet og tage
dem ind igen. En fjernet spiller forsvinder hos alle og kan ikke melde sig ind igen
med koden. WoW har ingen kryptografi, så det holder blandt venner, men er ikke
skudsikkert mod en, der virkelig vil snyde.

**De oprindelige 8 venner** (Mikkel, Mathias, Nick, Andreas, Frode, Søren, Rasmus og
Jeppe) behøver ikke gøre noget: ved opdateringen bliver I automatisk til gruppen
"Wasted Coast" med Mathias som admin, og al jeres historik er der stadig. Gruppen
bruger den samme skjulte kanal som før, så venner på en ældre version stadig ses.
Installerer en af jer forfra, så skriv dit navn præcis som før (fx Nick) og indsæt
gruppens kode (`WC-WASTED-COAST`, står også i Mathias' gruppevindue), så får du dit
gamle ID og din historik tilbage.

I behøver ikke være i samme guild: hver gruppe har sin egen skjulte kanal
(se "Sådan virker synkroniseringen"). Beskeder fra spillere uden for gruppen
ignoreres, også i guild og party.

Skriv `/wc4ever` for at åbne vinduet. Indstillingerne finder du under **Options >
AddOns > Wasted Coast Forever**, med knappen "Indstillinger" nederst i vinduet eller med
`/wc4ever config`. Vil du se, hvordan det ser ud med data i,
så skriv `/wc4ever demo` (og `/wc4ever demo slut` for at fjerne det igen).

---

## Hvad kan det?

### Overblik
Vennerne er delt i to grupper: **Online** øverst og **Offline** nedenunder.
De online venner har et stort kort med klasse-ikon, navn, den karakter vedkommende
spiller (fornavn og efternavn), level, zone, online-prik, antal dødsfald, antal
rare+ loot (med bar), antal karakterer og titler. De offline venner har et lille,
dæmpet kort med "OFFLINE", karakteren og hvornår de sidst var online (senest set
øverst). Hold musen over et kort for at se alle vennens karakterer, "værste fjende"
og seneste loot. Klik på et kort for at se alle karakterer. Nederst står de seneste
dødsfald og det seneste loot, når der er plads.

### Scoreboard
Alle venner i en rangliste. Klik på en kolonne for at sortere (klik igen for at
vende rækkefølgen): navn, højeste level, antal karakterer, døde (delt i **PvE** og
**PvP**), loot, point og guld. Guld er summen af alle vennens karakterer. Førstepladsen får guldkant, og
din egen række er markeret.

**Point = loot x 5 + højeste level - døde x 3.**

### PvP- og PvE-dødsfald
Alle dødsfald deles op i **PvP** (slået ihjel af en anden spiller eller dennes pet)
og **PvE** (mobs, bosser, fald, lava og alt andet). Opdelingen sendes med til
vennerne og står på kortene ("Døde: 12 (3 PvP)"), i Ranglisten (kolonnerne PvE og
PvP), under Karakterer og Spilletid (fx "9+3" = 9 PvE og 3 PvP), i deaths/hr
(PvE og PvP pr. time i tooltippen), i dødsstatistikken ("Farligste spiller") og i
seneste dødsfald. PvP-dødsfald får deres egne dødsannoncer, trofæerne *Ganket* og
*Kanonføde* og titlen **Gank-offeret**. Dødsfald fra før 0.15 tæller som PvE.

### Karakterer
Vælg en ven til venstre og se **alle karakterer vedkommende har været logget ind
med** (fornavn og efternavn): level, døde, rare+ loot og hvornår karakteren sidst var online og hvor.
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
så skriv `/wc4ever loot epic` (og `/wc4ever loot rare` for at gå tilbage).

### Toasts for rare/epic loot og rare mobs
Når en ven får et **rare** (blåt), **epic** (lilla) eller legendary item, får alle
en popup øverst på skærmen med vennens fulde karakternavn (fornavn + efternavn)
og item-linket, farvet efter kvaliteten. Det samme sker, når en ven **dræber et
rare eller rare elite mob**: popuppen viser mobbets navn, level og zone. Er flere
venner med til drabet, kommer den kun én gang. Rare mobs ses via target, focus,
mouseover, gruppens targets og nameplates, så hav mobbet i target, når det dør.
Slå dem fra hver for sig med `/wc4ever loottoast` og `/wc4ever raretoast`.

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
guld ved max level (70 på TBC, 60 på WoW Forever).

### Spilletid (Rangliste > Spilletid)
Spilletiden (`/played`) for hver ven og hele gruppen tilsammen, og **deaths/hr**:
dødsfald pr. times spilletid. Klik på en ven for at se spilletid, dødsfald og
deaths/hr på hver af vennens karakterer (med fornavn og efternavn). Spilletiden
måles automatisk lidt efter login (uden at skrive "Total time played" i chatten),
tæller videre, mens du spiller, og sendes til de andre hvert kvarter og ved synk.
Deaths/hr regnes kun på karakterer med kendt spilletid og mindst en halv times
spil. Spilletiden kan også ses i karakter-tooltippen under Venner > Karakterer.

### Statistik (under Død)
**Dødsstatistik:** fordelingen mellem PvE og PvP, de tre mobs, der har slået flest af jer ihjel,
de tre spillere, der har ganket jer mest, de tre farligste zoner, de tre med flest **deaths/hr** og **faldskade-kongen** (flest dødsfald af fald). Ud for hver står, hvem der
er døde til den. Til højre står **seneste dødsfald**: hvem (med karakterens fornavn og efternavn), hvornår, hvad der
slog dem ihjel og hvor.

### Rolls (under Loot)
**Uheldsrating for rolls:** hver gang du vælger Need, Greed eller Disenchant på et
item, tæller det som et roll. Addonet gemmer, hvor mange du har deltaget i, hvor
mange du vandt, og selve tallene du slog. **Tabt** er andelen af dine rolls, du
ikke vandt (fra 5 rolls), og **Snit** er dit gennemsnitlige roll (held er 50,5).
Den med højest tabt-procent står øverst og får titlen *Uheldsfuglen*. Kun rolls
fra den nye version tæller.

### Guld
En graf over hver vens samlede guld (alle karakterer) over tid. Der måles, mens
du spiller (højst hvert 10. minut, og kun når guldet har ændret sig), og når du
logger ud. Nye målinger sendes til vennerne med det samme. Vælg 7, 30 eller 90
dage eller det hele, og klik på et navn for at skjule eller vise vennen. Hold
musen over et navn for at se, hvor meget vennen har tjent eller brugt i perioden.

### Professions
Hvem kan crafte hvad: en linje pr. profession med hver ven og deres bedste skill.
375 er guld. Hold musen over en linje for at se alle karakterer med den.

### Gear
Hver karakters gennemsnitlige item level og hvad der mangler: slots uden enchant
(hoved, skuldre, bryst, ben, fødder, håndled, hænder, kappe, våben og
off-hand-våben eller skjold; ringe tæller ikke) og tomme gem-sockets. Gear måles,
når du logger ind og når du skifter udstyr. Filtrér på ven og rul med musehjulet.

### Reputation
For hver ven: hvor langt de er med de fem fraktioner, der giver heroic-nøgler
(Honor Hold/Thrallmar, Cenarion Expedition, Lower City, The Sha'tar og Keepers of
Time). Grøn betyder Revered, så nøglen kan købes. Sidste kolonne er, hvor mange
fraktioner vennen er exalted med. Hold musen over et felt for at se hver karakter.

### Dueller (Rangliste > Dueller)
Alle dueller, du er med i, bliver talt: vundet, tabt, og om nogen flygtede. Ranglisten
viser sejre, tab, sejrsprocent, stillingen mod vennerne og den aktuelle stime (+3 = tre
sejre i træk). Hold musen over en ven for at se alle modstandere, også dem uden for
vennegruppen. Til højre står det indbyrdes regnskab mellem vennerne (rækken mod
kolonnen, grøn = rækken fører) og de seneste dueller. Når to venner duellerer, får de
andre en popup med stillingen.

### Bank & repair (Rangliste > Bank & repair)
**Guild bank:** hvem har taget mest ud af guild banken, og hvem har lagt mest i den.
Både guld og ting tæller; ting regnes om til deres vendor-pris, så en stak Major Healing
Potions vejer mere end en grå klud. Skift mellem *Taget*, *Lagt* og *Netto* (lagt ind
minus taget ud) øverst. Under listen står titlerne *Bankrøveren*, *Bankens bedste ven*,
*Snylteren* og den ting, der er hævet flest af. Hold musen over en ven for at se guld og
ting hver for sig og vennens yndlingsting i banken.

**Repair:** hvor meget hver ven har betalt for at reparere, hvor meget guild banken har
betalt (Repair med guildens penge), antal reparationer og den største enkelte regning.
Titlerne er *Rustbunken*, *Guildens regning* og *Største regning*.

Hver ven måler kun sine egne handler, så alle skal have 0.11 for at tælle med, og der
tælles fra det tidspunkt, man opdaterer. Spillets egen bank-log bruges ikke, fordi den
kun gemmer de seneste handler og ikke har præcise tider. Totalerne sendes som én lille
besked efter et bank-besøg og ved synk. Tager eller lægger en ven mindst 50g, eller får
en repair-regning på mindst 15g, står det i chatten hos de andre (kan slås fra med
annonceringerne).

### Drilleri
Fanen samler alt det, der er lavet for at genere hinanden:
- **Held-rangering:** hvem har haft de bedste rolls på det seneste. Addonet gemmer
  dine seneste 30 rolls (need/greed og `/roll` 1-100) og sammenligner snittet med
  rent held. *Held 80%* betyder, at dine rolls er bedre end 80% af, hvad tilfældighed
  ville give; 50% er helt normalt. Kræver mindst 5 rolls. Den heldigste får titlen
  *Fætter Højben*.
- **Skammens hat:** den, der døde sidst, bærer hatten (dødningehovedet på kortet),
  indtil en anden dør. Fanen viser, hvor længe hatten har siddet, og hvem der har
  båret den længst i alt.
- **Emote-angreb:** klik på en ven (eller skriv `/wc4ever angrib nick`) for at sende en
  tilfældig fornærmelse. Vennen får en popup, og står I sammen (i gruppe eller med
  vennen som target), laver din karakter også en rigtig emote. Én gang pr. 15
  sekunder.
- **Need-politiet:** når du vinder noget på need, holder addonet øje med det. Tager du
  det på, er du frikendt. Sælger, disenchanter eller giver du det væk uden at have haft
  det på, eller ligger det ubrugt i tasken i 3 dage, bliver du hængt ud hos alle.
- **Level-snegl:** den, der er længst bagud i level (højeste karakter), får en snegl
  ved navnet på kortet (det er en skildpadde; WoW har ingen snegle-ikoner) og titlen
  *Level-snegl*. Hold musen over kortet for at se, hvor længe det er siden sidste
  level. Står der "mindst", har addonet ikke set selve level-up'et endnu.

### Dødsannoncer
Når en ven dør, får alle en popup med en dødsannonce, fx *"Nick blev overlistet af
en level 12 Murloc Forager"*. Annoncen afhænger af, hvordan man døde (fald, drukning,
lava, et alt for lavt eller højt mob osv.), og alle får den samme tekst. Mobbets level
kommer med, hvis det kunne ses (target eller nameplate), da man døde. Slå dem fra med
`/wc4ever annonce`.

### Daglig sladder
Når du logger ind efter mindst tre timers pause, kommer der efter et halvt minut et lille
vindue med højdepunkterne siden sidst, fx hvem der tog flest levels, hvem der døde mest,
den mest pinlige død (fald, lava eller et mob langt under ens eget level), epic loot,
nye trofæer, dueller, Need-politiets anholdelser, hvem der tjente eller brugte mest guld,
hvem der bærer Skammens hat, og hvem der ikke har været online i flere dage.
Sladderen står også i chatten. Den bygges af de data, addonet allerede har, så den sender
ingen ekstra beskeder. Første gang dækker den det seneste døgn, ellers tiden siden du sidst
var online (højst en uge). Vis den igen med `/wc4ever sladder`, og slå den fra ved login
med `/wc4ever sladder fra`.

### Indstillinger
Under **Options > AddOns > Wasted Coast Forever** kan du slå lyd, chatbeskeder og popups
til og fra, slå synk uden guild til og fra, vælge minimumskvalitet for loot og vælge, hvem du er. Der er også
knapper til at åbne vinduet, vise test-popups og synkronisere.

### Sprog / Language
Nederst i indstillingerne vælger du **Dansk** (standard) eller **English**. Sproget gælder
alt, hvad addonet viser: faner, kolonner, tooltips, popups, dødsannoncer, sladder,
trofæer og chatbeskeder. Det er en lokal indstilling, så hver ven vælger selv, og I kan
sagtens spille sammen med hver sit sprog (dødsannoncer og sladder er de samme, bare
oversat). Skiftet kræver en genindlæsning: addonet spørger, om det skal gøre det nu,
eller du kan skrive `/reload`. Du kan også skifte med `/wc4ever language en` eller
`/wc4ever sprog da`. På engelsk virker kommandoerne også med engelske navne, fx
`/wc4ever group`, `channel`, `style`, `surname`, `gossip`, `attack`, `obits`,
`testobit`, `demo clear` og `reset yes`.

### Popups (toasts)
Små beskeder øverst på skærmen:
- **Ven logger ind** (højst en gang pr. ven pr. 10 minutter)
- **Ven stiger i level** (og dig selv), med det samme og med hvor lang tid det tog siden karakterens sidste level
- **Wipe:** "Hvad FAaanden laver healer mand, kraftedme hele *Navn* party er død
  i *Instance*" (sendes til alle med addonet)
- **Boss nedlagt** og **instance klaret** (kun til dig)
- **Trofæer** (dine egne som stor popup, vennernes som lille)
- **Rare/epic loot** og **rare mobs dræbt** (sendes til alle med addonet)

Slå dem fra med `/wc4ever toast`, og se eksempler med `/wc4ever testtoast`.

### Egne lyde
Læg dine egne lydklip (`.ogg` eller `.mp3`) i mappen `WastedCoast\sounds` og skriv
filnavnene i `Sounds.lua` (der står en vejledning i filen). Du kan vælge lyd til
disse events: `death`, `loot`, `wipe`, `online`, `levelup`, `achievement`,
`bosskill`, og give hver ven sin egen lyd (fx Nick har sit eget *av*-skrig).
Står der flere filer på et event, vælges en tilfældig. Test med
`/wc4ever sound death`. Uden egen lyd bruger addonet Blizzards lyd til dødsfald,
wipes, level-up og trofæer, mens loot, online og bosskill er tavse.
Efter du har lagt **nye lydfiler** i mappen, skal spillet genstartes helt (ikke
kun `/reload`).

### Titler
Uddeles automatisk og vises på kortene og under scoreboardet:
- **Klovnen**: flest dødsfald
- **Gank-offeret**: flest PvP-dødsfald
- **Lootgoblin**: flest rare+ loot
- **Rigmanden**: mest guld i alt
- **Højest level**
- **Alt-junkie**: flest karakterer (mindst to)
- **Wipe-konge**: flest wipes
- **Faldskade-konge**: flest dødsfald af fald
- **Uheldsfuglen**: højest andel tabte rolls (mindst 5 rolls)
- **Fætter Højben**: bedst held i de seneste rolls (over 50%)
- **Skammens hat**: den, der døde sidst
- **Level-snegl**: længst bagud i level

---

## Kommandoer

| Kommando | Hvad den gør |
|---|---|
| `/wc4ever` | Vis/skjul vinduet (`/wc4l` virker også) |
| `/wc4ever gruppe` | Dit navn, opret eller deltag i en gruppe, del koden, fjern medlemmer (admin) |
| `/wc4ever config` | Åbn indstillingerne |
| `/wc4ever language en` | Skift sprog til engelsk (`/wc4ever sprog da` = dansk). Kræver /reload |
| `/wc4ever loot` | Vis, hvilken kvalitet loot registreres fra |
| `/wc4ever loot epic` | Registrér kun epic og bedre (også `uncommon`, `rare`, `legendary`) |
| `/wc4ever demo` | Fyld med demo-data, så du kan se, hvordan det ser ud (kun lokalt) |
| `/wc4ever demo slut` | Fjern demo-data igen (rører ikke dine rigtige data) |
| `/wc4ever sync` | Det samme som knappen "Opdater": bed vennerne sende deres data nu |
| `/wc4ever status` | Se, hvordan hver ven nås: guild, party/raid, skjult kanal eller whisper |
| `/wc4ever kanal` | Slå synk uden guild (skjult kanal og whispers) til/fra |
| `/wc4ever sound` | Slå lyd til/fra |
| `/wc4ever sound <event>` | Test en lyd: `death`, `loot`, `wipe`, `online`, `levelup`, `achievement`, `bosskill` |
| `/wc4ever toast` | Slå alle popups (online, level, wipe, loot, rares) til/fra |
| `/wc4ever loottoast` | Slå popups for rare/epic loot til/fra |
| `/wc4ever raretoast` | Slå popups for dræbte rare mobs til/fra |
| `/wc4ever stil` | Skift mellem spillets egne rammer (native) og addonets egen stil (kræver /reload) |
| `/wc4ever minimap` | Vis/skjul WC4ever-logoet ved minimappet (klik åbner vinduet, træk flytter det) |
| `/wc4ever testtoast` | Vis eksempler på popups (sendes ikke til de andre) |
| `/wc4ever efternavn X` | Sæt din karakters efternavn (WoW Forever). `auto` = find det selv. Uden navn: vis det |
| `/wc4ever announce` | Slå chat-beskeder til/fra (dødsfald og loot) |
| `/wc4ever sladder` | Vis sladderen siden sidst igen (`sladder fra`/`til` styrer den ved login) |
| `/wc4ever angrib <ven>` | Send et emote-angreb til en ven (det er nok at skrive starten af navnet) |
| `/wc4ever annonce` | Slå dødsannoncer til/fra |
| `/wc4ever emotes` | Slå popups for emote-angreb mod dig til/fra |
| `/wc4ever testannonce` | Vis eksempler på dødsannonce, Need-politi og emote-angreb |
| `/wc4ever test` | Lav et falsk dødsfald (sendes ikke til de andre) |
| `/wc4ever testloot` | Lav en falsk loot win (sendes ikke til de andre) |
| `/wc4ever reset ja` | Slet alle data (inkl. valg af, hvem du er) |

`/wastedcoast` virker også.

---

## Sådan virker synkroniseringen

- Alt sendes via usynlige addon-beskeder i **party, raid og guild**, og fra 0.5.1
  også i en **skjult kanal**, som addonet melder dig ind i, når du logger ind. Fra 0.10
  har hver gruppe sin egen kanal, afledt af koden (gruppen "Wasted Coast" bruger
  stadig `WC4Lsync`). Så kan I følge hinanden **uden at være i samme guild eller gruppe**.
  Kanalen vises ikke i dine chatvinduer, og dens beskeder bliver skjult.
- **Whisper som reserve:** Kan en ven ikke nås i guild, gruppe eller kanal (fx hvis
  klienten ikke kan sende addon-beskeder i kanaler), sender addonet usynlige
  whispers til vennens karakter i stedet. For at finde hinanden spørger det ved
  login og ved synk de seneste karakterer, det kender for hver ven, og de online
  karakterer på din venneliste i spillet. Fejlbeskeden "No player named ... is
  currently playing" for karakterer, der er offline, bliver skjult.
  **Første gang** uden fælles guild: tilføj vennernes karakterer til vennelisten
  (`/friend Navn`), så finder addonet dem selv.
- **Hver besked sendes kun én gang:** Spillet lader et addon sende omkring én besked i
  sekundet. Er den skjulte kanal forbundet, går alt derigennem, og guild og party bruges
  kun til venner, der ikke er hørt i kanalen. (Før 0.10.1 blev alt sendt både i guild og
  kanal, og køen hobede sig op, så vennernes tal kun kom igennem i party.)
- `/wc4ever status` viser, hvordan hver ven nås lige nu, hvilke veje der sendes ad, og
  hvor mange beskeder der står i kø. Slå kanal og whispers fra med
  `/wc4ever kanal` eller under Indstillinger ("Synk uden guild").
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
- **Rolls, guld, professions, gear og reputation:** Hver spiller måler sine egne
  og sender dem, når de ændrer sig. Guld måles løbende og sendes med det samme.
  Ved synk sendes det hele igen (de seneste 30 guldmålinger).
- **Automatisk synk:** Hvert 10. minut beder addonet vennerne om deres seneste data, så
  du får det, du har misset, uden at logge ud. Den sender ikke hele historikken igen
  (den kommer, når du logger ind). Ét svar går til alle, så spørger flere venner på
  samme tid, svarer hver spiller kun én gang.
- **Knappen "Opdater"** nederst i vinduet (eller `/wc4ever sync`) beder vennerne sende
  alt med det samme. De svarer højst hvert 30. sekund på den, og ellers højst hvert
  10. minut. Svaret kan tage op til et halvt minut at komme igennem.
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

(Eller `_classic_` / `_classic_era_` / Forever-mappen afhængigt af version.) Den fil kan senere
bruges til at uploade data til et website.

---

## Ændre vennerne

Listen står øverst i `WastedCoast.lua`, i linjen der starter med
`local ROSTER = {`. Navnene bestemmer rækkefølgen på kortene. Alle skal have
samme liste, så del den ændrede fil med gruppen. Der er plads til ti venner
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
De skal have den nye version og have valgt, hvem de er. Uden fælles guild eller
gruppe går det via den skjulte kanal; skriv `/wc4ever status` for at se, om den er
forbundet, og hvem der er hørt fra. Står kanalen som ikke forbundet, så tilføj
vennernes karakterer til vennelisten i spillet, så bruger addonet whispers. Prøv
`/wc4ever sync` og vent et halvt minut.

**Mit loot dukker ikke op**
Tjek kvaliteten med `/wc4ever loot`, og at du har valgt, hvem du er (ellers
gemmes loot kun hos dig selv). Prøv `/wc4ever testloot` for at se, om listen virker.
Virker det ikke med rigtigt loot, så skriv `/dump LOOT_ITEM_SELF` og send mig
teksten, så kan jeg tilpasse genkendelsen.

**Ingen lyd fra mine egne klip**
Tjek, at filen ligger i `WastedCoast\sounds`, at navnet i `Sounds.lua` er stavet
helt ens (ingen mellemrum, æ, ø eller å), og at du har genstartet spillet efter at
have lagt filen der. `/wc4ever sound death` fortæller, hvad der gik galt.

**Bosser eller wipes tæller ikke**
Skriv `/dump GetInstanceInfo()` inde i instancen og send mig det første navn, så
kan jeg rette stavningen i addonet. Spillet skal køre på engelsk for bossnavnene.

**WoW Forever: hvad er anderledes?**
Addonet kan selv se, hvilken version det kører på (det står i chatten, når det
indlæses). Forever kører på Blizzards nye motor, og det betyder:
- Max level er 60, så race og trofæer går til 60.
- Bosser og clears i Forevers dungeons og raids (også de nye, fx Barrow Deeps og
  Forevers egen Hyjal Summit) hentes fra spillets Encounter Journal.
- Addons kan ikke læse combat log. Mens du er i kamp, holder addonet øje med
  fjender, der har dig i target (dit target, focus, mouseover og alle nameplates),
  og ved et dødsfald er den seneste af dem dræberen. Fald, drukning og udmattelse
  genkendes også. Slå nameplates til for fjender (tasten V), så rammer det oftest
  rigtigt. Kun hvis der slet ikke er noget at gå efter, står der "Ukendt".
  Er dræberen en spiller (eller en spillers pet), tæller dødsfaldet som PvP.
- Karakterer har fornavn og efternavn. Addonet prøver selv at finde efternavnet;
  lykkes det ikke, skriver det det i chatten, og så sætter du det med
  `/wc4ever efternavn Ditefternavn`. Efternavnet sendes til vennerne og vises i
  dødsbeskeder, dødsannoncer, på kortene og under Karakterer.
- Under bosskampe kan spillet blokere addon-beskeder. De bliver sendt, når det er
  muligt igen.
- Nøgle-fraktionerne til TBC-heroics vises ikke på reputation-fanen.
- Hver vens **legacy points** (fra Legacy Challenges) vises på vennekortet, i
  kortets tooltip og på vennens side. De gælder hele Battle.net-kontoen, så det er
  ét tal pr. ven, og det opdateres, når nogen klarer en challenge.

**Honor**
Vennekortet viser hver vens honor points (lagt sammen på tværs af karakterer), og
tooltippet viser også honorable kills. Det virker på både TBC og WoW Forever.

**Lua-fejl**
Skriv `/console scriptErrors 1` og `/reload`, og send fejlteksten videre.

**Den gamle demo "VennerneForever" kører stadig**
Slet mappen `VennerneForever` fra AddOns.

## Tests

Testene kører addonet mod en lille attrap af WoW's API (kræver Python og `pip install lupa`):

```
python3 tests/test_drilleri.py WastedCoast          # hele addonet, klassisk stil
python3 tests/test_drilleri.py WastedCoast native   # med spillets egne rammer (som på Forever)
python3 tests/test_robust.py WastedCoast            # fejlrettelser, synk og ødelagte beskeder (TBC)
python3 tests/test_robust.py WastedCoast forever    # det samme som WoW Forever (ingen combat log, kun C_Item)
python3 tests/test_language.py WastedCoast          # engelsk: ingen dansk tekst nogen steder; dansk er standard
python3 tests/test_language.py WastedCoast forever  # det samme på WoW Forever
```
