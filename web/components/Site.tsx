// Hele forsiden, tegnet på serveren ud fra modellen (lib/model.ts).
import Link from "next/link";
import RankTable from "./RankTable";
import { CLASS_NAMES, FLAVOR_NAMES, type Bar, type Model, type Person } from "@/lib/model";
import type { Meta } from "@/lib/store";
import { ago, fmt, goldOf } from "@/lib/format";

function Who({ m, id }: { m: Model; id: string }) {
  const p = m.byId[id];
  return <b style={{ color: p?.color || "var(--ink)" }}>{p?.name || id}</b>;
}

function Sparkline({ hist }: { hist: [number, number][] }) {
  const pts = hist.slice(-60);
  const t0 = pts[0][0], t1 = pts[pts.length - 1][0];
  let lo = Math.min(...pts.map((p) => p[1])), hi = Math.max(...pts.map((p) => p[1]));
  if (hi === lo) hi = lo + 1;
  const W = 200, H = 30;
  const y = (v: number) => H - 2 - ((v - lo) / (hi - lo)) * (H - 4);
  const d = pts.map((p, i) => `${i ? "L" : "M"}${(((p[0] - t0) / (t1 - t0 || 1)) * W).toFixed(1)} ${y(p[1]).toFixed(1)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" role="img" aria-label="Guld over tid">
      <path d={`${d} L${W} ${H} L0 ${H} Z`} fill="rgba(242,182,50,.12)" />
      <path d={d} fill="none" stroke="var(--gold)" strokeWidth={2} vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
      <circle cx={W} cy={y(pts[pts.length - 1][1]).toFixed(1)} r={3} fill="var(--gold)" />
    </svg>
  );
}

function HBars({ m, items, unit }: { m?: Model; items: Bar[]; unit: (v: number) => string }) {
  const max = Math.max(1, ...items.map((x) => x.v));
  return (
    <ul className="hbars">
      {items.map((x) => (
        <li key={x.id || x.label}>
          <span className="n">{m && x.id ? <Who m={m} id={x.id} /> : x.label}</span>
          <span className="t"><i style={{ width: `${((100 * x.v) / max).toFixed(1)}%` }} /></span>
          <span className="v">{unit(x.v)}</span>
        </li>
      ))}
    </ul>
  );
}

function Hero({ m }: { m: Model }) {
  if (!m.hat) {
    return (
      <div className="hero">
        <div className="hatbox"><img src="/skammens-hat.png" alt="" /></div>
        <div><div className="eyebrow">Skammens hat</div><h1>Ingen er døde endnu</h1><p>Hatten venter på den første.</p></div>
      </div>
    );
  }
  const d = m.hat.death;
  return (
    <div className="hero">
      <div className="hatbox"><img src="/skammens-hat.png" alt="Skammens hat" /></div>
      <div>
        <div className="eyebrow">Skammens hat bæres lige nu af</div>
        <h1><span className="who">{m.byId[m.hat.id]?.name || m.hat.id}</span></h1>
        <p>
          {d.char} (level {d.level}) {d.killer ? <>døde til <b>{d.killer}</b></> : "døde af ukendte årsager"}
          {d.zone && <> i <b>{d.zone}</b></>} {ago(d.time)}. Det er dødsfald nummer {m.hat.count}. Hatten sidder fast, til en anden dør.
        </p>
        {m.hat.before.length > 0 && (
          <div className="hat-hist">Før det: {m.hat.before.map((h, i) => <span className="chip" key={i}><Who m={m} id={h.id} /></span>)}</div>
        )}
      </div>
    </div>
  );
}

function Totals({ m }: { m: Model }) {
  const t = m.totals;
  const box = (n: number, l: string) => <div className="total" key={l}><div className="n">{fmt(n)}</div><div className="l">{l}</div></div>;
  return <div className="totals">{[box(t.levels, "Levels tilsammen"), box(t.deaths, "Dødsfald"), box(t.bosses, "Boss-kills"), box(t.hours, "Timer spillet"), box(t.gold, "Guld i alt")]}</div>;
}

// De seneste need-rolls som grønne og røde prikker, nyeste til højre
function NeedRec({ rec, loss }: { rec: string; loss: number | null }) {
  const won = rec.split("").filter((c) => c === "V").length;
  const label = `Seneste ${rec.length} need: ${won} vundet, ${rec.length - won} tabt`;
  return (
    <div className="needrec" title={label}>
      <span>Need</span>
      <span className="dots" role="img" aria-label={label}>
        {rec.split("").map((c, i) => <i key={i} className={c === "V" ? "w" : "l"} />)}
      </span>
      <span>{won}/{rec.length}{loss !== null ? ` · ${loss}% tabt` : ""}</span>
    </div>
  );
}

function Card({ m, p, snapT }: { m: Model; p: Person; snapT: number }) {
  const c = p.main;
  const now = Date.now() / 1000;
  const online = p.seen > 0 && snapT - p.seen < 300 && now - snapT < 1800;
  const hat = m.hat?.id === p.id;
  const xp = Math.max(0, Math.min(100, Math.round(c.xp)));
  return (
    <article className={hat ? "card has-hat" : "card"}>
      <div className="head">
        <span className={online ? "dot on" : "dot"} title={online ? "Online" : "Offline"} />
        <span className="nm" style={{ color: p.color }}>{p.name}</span>
        {hat && <img src="/skammens-hat.png" alt="Bærer Skammens hat" title="Bærer Skammens hat" />}
      </div>
      <div className="char">
        <b>{[c.name, c.surname].filter(Boolean).join(" ")}</b> · {CLASS_NAMES[c.class || ""] || c.class}{c.zone ? ` · ${c.zone}` : ""}
      </div>
      <div className="lvl">
        <span>Level <b>{c.level || "?"}</b></span>
        <span className="bar" title={`${xp}% XP`}><i style={{ width: `${xp}%` }} /></span>
        <span>{xp}%</span>
      </div>
      <div className="stats">
        <div className="d"><b>{p.deaths}</b>døde{p.pvp ? ` (${p.pvp} PvP)` : ""}</div>
        <div><b>{p.loot}</b>loot</div>
        <div><b>{fmt(p.played / 3600)}</b>timer</div>
      </div>
      {p.goldHist.length > 1 && (
        <div className="spark"><Sparkline hist={p.goldHist} /><span>{fmt(goldOf(p.goldHist[p.goldHist.length - 1][1]))} g</span></div>
      )}
      {p.needRec && <NeedRec rec={p.needRec} loss={p.needLoss} />}
      <div className="seen">
        {online ? "Online nu" : `Sidst set ${ago(p.seen)}`} · {p.chars.length} karakter{p.chars.length === 1 ? "" : "er"}
      </div>
    </article>
  );
}

function Columns({ m }: { m: Model }) {
  const q = (n: number) => `q${Math.max(2, Math.min(5, n || 2))}`;
  return (
    <section className="cols">
      <div className="col">
        <h2>Kirkegården</h2>
        <ul className="feed">
          {m.deaths.slice(0, 8).map((d, i) => (
            <li key={i}>
              <span className="what"><Who m={m} id={d.who} /> døde{d.killer && ` til ${d.killer}`}{d.pvp && <span className="pvp">PvP</span>}</span>
              <span className="when">{ago(d.time)}</span>
              <span className="sub">{d.char}, level {d.level}{d.zone && ` · ${d.zone}`}</span>
            </li>
          ))}
          {!m.deaths.length && <li>Ingen døde endnu.</li>}
        </ul>
        {m.topKillers.length > 0 && (
          <div className="minor"><h3>Farligste fjender</h3><HBars items={m.topKillers} unit={(v) => `${v}×`} /></div>
        )}
      </div>
      <div className="col">
        <h2>Loot</h2>
        <ul className="feed">
          {m.loot.slice(0, 8).map((l, i) => (
            <li key={i}>
              <span className="what"><Who m={m} id={l.who} /> fik <span className={q(l.quality)}>[{l.name}]</span></span>
              <span className="when">{ago(l.time)}</span>
              <span className="sub">{l.how && <><span className="how">{l.how}</span> · </>}{l.zone}</span>
            </li>
          ))}
          {!m.loot.length && <li>Intet loot endnu.</li>}
        </ul>
        {m.weekPlay.length > 0 && (
          <div className="minor"><h3>Ugens nolifer (timer i denne uge)</h3>
            <HBars m={m} items={m.weekPlay.slice(0, 8)} unit={(v) => v.toFixed(1).replace(".", ",")} /></div>
        )}
      </div>
      <div className="col">
        <h2>Drillerier</h2>
        {m.farts.length > 0 && <div className="minor first"><h3>Flest prutter sendt</h3><HBars m={m} items={m.farts.slice(0, 6)} unit={fmt} /></div>}
        {m.gz.length > 0 && <div className="minor"><h3>Flest &quot;Gz&quot; sagt</h3><HBars m={m} items={m.gz.slice(0, 6)} unit={fmt} /></div>}
        {m.milestones.length > 0 && (
          <div className="minor"><h3>Bandens milepæle</h3>
            <ul className="feed">
              {m.milestones.slice(0, 5).map((x) => (
                <li key={x.cat + x.goal}>
                  <span className="what">{x.name}: <b>{fmt(x.goal)}</b></span>
                  <span className="when">{ago(x.t)}</span>
                  {x.by && m.byId[x.by] && <span className="sub">Rundet af <Who m={m} id={x.by} /></span>}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </section>
  );
}

function Trophies({ m }: { m: Model }) {
  const people = [...m.people].sort((a, b) => b.pts - a.pts);
  return (
    <section>
      <h2>Trofæskabet <small>Point fra addonets trofæer</small></h2>
      <div className="troph">
        {people.map((p) => (
          <div className="tro" key={p.id}>
            <div className="h"><Who m={m} id={p.id} /><span>{p.pts} p</span></div>
            <div className="list">
              {p.trophies.length ? p.trophies.map((t) => <span key={t.id} title={`${t.desc} (${t.pts} p)`}>{t.name}</span>) : <span>Ingen endnu</span>}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

export function Header({ flavors, current, meta }: { flavors: Meta[]; current?: string; meta?: Meta }) {
  return (
    <header className="top">
      <img src="/wc4ever-logo.png" alt="WC4ever" />
      <div className="brand"><b>Skammens Hat</b><span>Wasted Coast Forever</span></div>
      {flavors.length > 1 && (
        <nav className="flavors" aria-label="Spilversion">
          {flavors.map((f) => (
            <Link key={f.flavor} href={`/?v=${f.flavor}`} aria-current={f.flavor === current ? "page" : undefined}>
              {FLAVOR_NAMES[f.flavor] || f.flavor}
            </Link>
          ))}
        </nav>
      )}
      {meta && <div className="sync">Opdateret <b>{ago(meta.t / 1000)}</b>{meta.navn && ` fra ${meta.navn}`}</div>}
    </header>
  );
}

export default function Site({ m, flavors, meta }: { m: Model; flavors: Meta[]; meta: Meta }) {
  const snapT = meta.mtime || meta.t / 1000;
  const rows = m.people.map((p) => ({
    id: p.id, name: p.name, color: p.color,
    values: { levels: p.levels, deaths: p.deaths, pvp: p.pvp, bosses: p.bosses, clears: p.clears, wipes: p.wipes,
      loot: p.loot, wins: p.wins, needLoss: p.needLoss ?? undefined, pts: p.pts, hours: Math.round(p.played / 3600), gold: goldOf(p.gold) },
  }));
  return (
    <div className="wrap">
      <Header flavors={flavors} current={meta.flavor} meta={meta} />
      <Hero m={m} />
      <Totals m={m} />
      <section>
        <h2>Banden <small>{m.people.length} venner, sorteret efter level</small></h2>
        <div className="cards">{m.people.map((p) => <Card key={p.id} m={m} p={p} snapT={snapT} />)}</div>
      </section>
      <section id="rangliste">
        <h2>Ranglisten <small>Klik på en kolonne for at sortere</small></h2>
        <RankTable rows={rows} />
      </section>
      <Columns m={m} />
      <Trophies m={m} />
      <footer>Data kommer fra WC4ever-addonet og opdateres, når nogen logger ud eller skriver /reload.</footer>
    </div>
  );
}
