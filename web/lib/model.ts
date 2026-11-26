// Regner addonets WastedCoastDB om til det, siden viser. Samme regler som i addonet
// (fx Skammens hat = den, der døde sidst). Se docs/data.md for felterne.
/* eslint-disable @typescript-eslint/no-explicit-any */

export const CLASS_COLORS: Record<string, string> = {
  WARRIOR: "#C69B6D", PALADIN: "#F48CBA", HUNTER: "#AAD372", ROGUE: "#FFF468", PRIEST: "#FFFFFF",
  SHAMAN: "#0070DD", MAGE: "#3FC7EB", WARLOCK: "#8788EE", DRUID: "#FF7C0A", DEATHKNIGHT: "#C41E3A",
  MONK: "#00FF98", DEMONHUNTER: "#A330C9", EVOKER: "#33937F",
};
export const CLASS_NAMES: Record<string, string> = {
  WARRIOR: "Warrior", PALADIN: "Paladin", HUNTER: "Hunter", ROGUE: "Rogue", PRIEST: "Priest", SHAMAN: "Shaman",
  MAGE: "Mage", WARLOCK: "Warlock", DRUID: "Druid",
};
export const FLAVOR_NAMES: Record<string, string> = {
  _forever_: "Forever", _classic_beta_: "Forever beta", _anniversary_: "Anniversary",
  _classic_era_: "Classic Era", _classic_: "Classic", _retail_: "Retail",
};
// Trofæerne fra WastedCoast.lua: id -> [navn, beskrivelse, point]
export const TROPHIES: Record<string, [string, string, number]> = {
  first_death: ["Første blod", "Dø for første gang.", 5],
  deaths10: ["Fast gæst på kirkegården", "Dø 10 gange.", 10],
  deaths50: ["Kirkegårdsgænger", "Dø 50 gange.", 25],
  deaths100: ["Professionelt lig", "Dø 100 gange. Respekt.", 50],
  first_to_die: ["Første til at dø", "Vær den første i gruppen, der dør i en dungeon.", 10],
  pvp1: ["Ganket", "Bliv slået ihjel af en anden spiller.", 5],
  pvp10: ["Kanonføde", "Bliv slået ihjel af andre spillere 10 gange.", 15],
  fall: ["Tyngdekraften vinder", "Dø af at falde ned fra en klippe.", 10],
  lava: ["Gulvet er lava", "Dø i lava, ild eller slim.", 10],
  drown: ["Glemte at svømme", "Drukn eller dø af udmattelse.", 10],
  afk_pull: ["AFK midt i en pull", "Gå AFK, mens gruppen er i kamp, eller dø, mens du er AFK.", 15],
  nemesis: ["Ærkefjenden", "Bliv dræbt af den samme fjende 5 gange.", 15],
  triple: ["Hat-trick", "Dø 3 gange på 10 minutter.", 10],
  quick_exit: ["Hurtig exit", "Dø inden for et minut efter du er gået ind i en dungeon.", 10],
  wipe_first: ["Første wipe", "Vær med i dit første wipe.", 5],
  wipe10: ["Wipe-veteran", "Vær med i 10 wipes.", 25],
  healer_gone: ["Healeren er ikke hjemme", "Wipe 3 gange i samme dungeon-besøg.", 15],
  boss_first: ["Første boss", "Dræb din første boss.", 5],
  boss25: ["Bossjæger", "Dræb 25 bosser.", 25],
  clear_first: ["Instance klaret", "Klar en hel instance.", 10],
  clear10: ["Dungeon-diva", "Klar 10 instances.", 25],
  epic_first: ["Lilla fingre", "Vind dit første epic.", 10],
  epic10: ["Lootgoblin", "Vind 10 epics.", 25],
  legend: ["Gylden dag", "Vind et legendary item.", 50],
  need5: ["Need before greed", "Vind 5 items med Need.", 10],
  lvl60: ["Max level", "Nå level 60.", 25],
  lvl70: ["Max level", "Nå level 70.", 25],
  alts5: ["Alt-junkie", "Spil med 5 forskellige karakterer.", 15],
  gold1000: ["Rigmanden", "Eje 1000 guld på tværs af dine karakterer.", 15],
  night: ["Nattergalen", "Log ind mellem klokken 02 og 05 om natten.", 10],
};
export const MILESTONE_NAMES: Record<string, string> = {
  lvl: "Levels tilsammen", max: "Max level-karakterer", dead: "Dødsfald", loot: "Rare loot", gold: "Guld tilsammen",
  boss: "Boss-kills", hours: "Timer spillet", rare: "Rare mobs", haan: "Prutter",
};

export type Char = {
  key: string; name: string; surname?: string; class?: string; level: number; xp: number; zone?: string; seen: number;
};
export type Person = {
  id: string; name: string; color: string; chars: Char[]; main: Char; seen: number;
  gold: number; played: number; levels: number; bosses: number; clears: number; wipes: number;
  deaths: number; pvp: number; loot: number; wins: number; pts: number;
  // Need-rolls: tabt-procent (kun need, null under 5 need-rolls) og de seneste need-rolls som "V"/"T"
  needLoss: number | null; needRec: string;
  trophies: { id: string; name: string; desc: string; pts: number; t: number }[];
  goldHist: [number, number][];
};
export type Death = { who: string; char: string; level: number | string; killer: string; zone: string; pvp: boolean; time: number };
export type Loot = { who: string; name: string; quality: number; how: string; zone: string; time: number };
export type Bar = { id?: string; label: string; v: number };
export type Model = ReturnType<typeof buildModel>;

const list = (x: any): any[] => (Array.isArray(x) ? x : x && typeof x === "object" ? Object.values(x) : []);
const obj = (x: any): Record<string, any> => (x && typeof x === "object" && !Array.isArray(x) ? x : {});
const num = (x: any): number => (typeof x === "number" && isFinite(x) ? x : 0);

// Samlet guld over tid for én ven, som guldgrafen i addonet (ns.GoldTotalSeries): summen af alle
// karakterer, hvor hver karakter tæller med sit senest kendte beløb. 0 lige efter et beløb springes
// over: spillet svarer 0 på GetMoney() ved logout, og ældre versioner gemte det (v0.33.1).
function goldTotalSeries(byChar: any, charsObj: any, oldHist: any[]): [number, number][] {
  const lists: [number, number][][] = [];
  for (const k of Object.keys(charsObj)) {
    const c = obj(charsObj[k]);
    if (c.demo) continue;
    const h: [number, number][] = [];
    for (const smp of list(byChar[k])) {
      if (!Array.isArray(smp) || (smp as any).d) continue;
      const t = num(smp[0]), v = num(smp[1]);
      if (!t) continue;
      if (v === 0 && h.length && h[h.length - 1][1] > 0) continue;
      h.push([t, v]);
    }
    h.sort((a, b) => a[0] - b[0]);
    if (h.length) lists.push(h);
    else if (num(c.gold) > 0) lists.push([[num(c.seen) || 1, num(c.gold)]]);
  }
  if (!lists.some((h) => h.length > 1)) {
    // Ingen målinger pr. karakter: de gamle samlede målinger
    return oldHist.filter((p) => Array.isArray(p) && num(p[1]) > 0).map((p) => [num(p[0]), num(p[1])] as [number, number]);
  }
  const cur = lists.map((h) => h[0][1]);
  let total = cur.reduce((s, v) => s + v, 0);
  const ev = lists.flatMap((h, i) => h.map((p) => [p[0], i, p[1]] as [number, number, number]))
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const pts: [number, number][] = [];
  for (const [t, i, v] of ev) {
    total += v - cur[i];
    cur[i] = v;
    const last = pts[pts.length - 1];
    if (last && last[0] === t) last[1] = total;
    else if (!last || last[1] !== total) pts.push([t, total]);
  }
  return pts;
}

export function buildModel(db: any) {
  const members = obj(db?.group?.members);
  const kicked = obj(db?.group?.kicked);
  const friends = obj(db?.friends);
  // Dublet-ID'er (Groups.lua): følg members[id].dup til det ID, vennens data ligger på. Ældre
  // addon-versioner kunne efterlade en ring (A.dup = B og B.dup = A), når det viste ID skiftede.
  // Så vælges det ID i kæden, der har data i friends, så vennen aldrig forsvinder (v0.33.2).
  const canon = (id: string) => {
    const chain = [id];
    let cur = id;
    for (;;) {
      const d = members[cur]?.dup;
      if (typeof d !== "string" || !members[d] || chain.includes(d)) break;
      chain.push(d);
      cur = d;
    }
    if (friends[cur]) return cur;
    return chain.find((x) => friends[x]) ?? cur;
  };
  const name = (id: string) => String(members[canon(id)]?.n || id);

  const ids = Object.keys(friends).filter((id) => !kicked[id] && canon(id) === id);
  const events = list(db?.events).filter((e) => e && !e.demo && e.friend)
    .sort((a, b) => num(b.time) - num(a.time));
  const loot = list(db?.loot).filter((l) => l && !l.demo && l.friend)
    .sort((a, b) => num(b.time) - num(a.time));

  const people: Person[] = ids.map((id) => {
    const charsObj = obj(friends[id].chars);
    const chars: Char[] = Object.keys(charsObj).map((k) => {
      const c = obj(charsObj[k]);
      return { key: k, name: k, surname: c.surname, class: c.class, level: num(c.level), xp: num(c.xp), zone: c.zone,
        seen: Math.max(num(c.seen), num(c.hb)) };
    }).sort((a, b) => b.level - a.level || b.xp - a.xp || b.seen - a.seen);
    let seen = 0, gold = 0, played = 0, levels = 0;
    for (const c of chars) {
      const raw = obj(charsObj[c.key]);
      seen = Math.max(seen, c.seen);
      // Guldet står som 0, hvis vennen loggede ud på en anden karakter; brug så den seneste måling
      let g = num(raw.gold);
      if (!g) {
        const gh = list(db?.goldChar?.[id]?.[c.key]).filter((x) => x && num(x[1]) > 0);
        if (gh.length) g = num(gh[gh.length - 1][1]);
      }
      gold += g;
      played += num(raw.played?.t);
      levels += c.level;
    }
    const runs = obj(db?.runs?.[id]);
    let bosses = 0, clears = 0, wipes = 0;
    for (const r of Object.values(runs) as any[]) {
      wipes += num(r?.wipes);
      clears += num(r?.clears);
      for (const v of Object.values(obj(r?.boss))) bosses += num(v);
    }
    const mine = events.filter((e) => canon(e.friend) === id);
    const ach = obj(db?.ach?.[id]);
    const trophies = Object.keys(ach).filter((k) => TROPHIES[k])
      .map((k) => ({ id: k, name: TROPHIES[k][0], desc: TROPHIES[k][1], pts: TROPHIES[k][2], t: num(ach[k]) }))
      .sort((a, b) => a.t - b.t);
    const rolls = obj(db?.rolls?.[id]);
    const nr = num(rolls.nr), nw = num(rolls.nw);
    const nh = typeof rolls.nh === "string" && /^[VT]{1,10}$/.test(rolls.nh) ? rolls.nh : "";
    const main = chars[0] || { key: "", name: "?", level: 0, xp: 0, seen: 0 };
    return {
      id, name: name(id), color: CLASS_COLORS[main.class || ""] || "var(--ink)", chars, main, seen, gold, played, levels,
      bosses, clears, wipes, deaths: mine.length, pvp: mine.filter((e) => e.pvp).length,
      loot: loot.filter((l) => canon(l.friend) === id).length, wins: num(rolls.wins),
      needLoss: nr >= 5 ? Math.round((Math.max(0, nr - nw) / nr) * 100) : null, needRec: nh,
      pts: trophies.reduce((s, t) => s + t.pts, 0), trophies,
      goldHist: goldTotalSeries(obj(db?.goldChar?.[id]), charsObj, list(db?.goldHist?.[id])),
    };
  }).sort((a, b) => b.main.level - a.main.level || b.main.xp - a.main.xp);
  const byId: Record<string, Person> = Object.fromEntries(people.map((p) => [p.id, p]));

  const deaths: Death[] = events.map((e) => ({
    who: canon(e.friend), char: [e.name, e.sur].filter(Boolean).join(" "), level: e.level ?? "?",
    killer: e.killer && e.killer !== "Ukendt" ? String(e.killer) : "", zone: String(e.zone || ""), pvp: !!e.pvp, time: num(e.time),
  }));

  // Skammens hat: den, der døde sidst
  const hatHist: { id: string; t: number }[] = [];
  for (const d of deaths) if (!hatHist.length || hatHist[hatHist.length - 1].id !== d.who) hatHist.push({ id: d.who, t: d.time });
  const hat = deaths.length ? { id: deaths[0].who, death: deaths[0], count: deaths.filter((d) => d.who === deaths[0].who).length, before: hatHist.slice(1, 6) } : null;

  // Spilletid i den nyeste uge (Weekly.lua)
  const rep = obj(db?.weekly?.rep);
  const latest = Object.keys(rep).map(Number).sort((a, b) => b - a)[0];
  const weekMap: Record<string, number> = {};
  for (const [id, w] of Object.entries(obj(rep[latest]))) {
    const k = canon(id);
    if (byId[k]) weekMap[k] = Math.max(weekMap[k] || 0, num((w as any)?.p));
  }
  const weekPlay: Bar[] = Object.entries(weekMap).map(([id, p]) => ({ id, label: name(id), v: p / 3600 })).sort((a, b) => b.v - a.v);

  const countBy = (rows: any[], field: string): Bar[] => {
    const c: Record<string, number> = {};
    for (const r of rows) if (r?.[field]) { const k = canon(r[field]); if (byId[k]) c[k] = (c[k] || 0) + 1; }
    return Object.entries(c).map(([id, v]) => ({ id, label: name(id), v })).sort((a, b) => b.v - a.v);
  };

  const killers: Record<string, number> = {};
  for (const d of deaths) if (d.killer) killers[d.killer] = (killers[d.killer] || 0) + 1;
  const topKillers: Bar[] = Object.entries(killers).map(([label, v]) => ({ label, v })).sort((a, b) => b.v - a.v).slice(0, 5);

  const milestones = Object.entries(obj(db?.milestones?.hit)).map(([k, v]) => {
    const [cat, goal] = k.split(":");
    return { cat, name: MILESTONE_NAMES[cat], goal: Number(goal), t: num((v as any)?.t), by: (v as any)?.by ? canon(String((v as any).by)) : "" };
  }).filter((m) => m.name).sort((a, b) => b.t - a.t);

  return {
    people, byId, deaths,
    loot: loot.map((l): Loot => ({ who: canon(l.friend), name: String(l.name || "?"), quality: num(l.quality), how: String(l.how || ""), zone: String(l.zone || ""), time: num(l.time) })),
    hat, weekPlay, farts: countBy(list(db?.haan?.log), "from"), gz: countBy(list(db?.gz?.log), "from"), topKillers, milestones,
    totals: {
      levels: people.reduce((s, p) => s + p.levels, 0),
      deaths: deaths.length,
      bosses: people.reduce((s, p) => s + p.bosses, 0),
      hours: Math.round(people.reduce((s, p) => s + p.played, 0) / 3600),
      gold: Math.floor(people.reduce((s, p) => s + p.gold, 0) / 10000),
    },
  };
}
