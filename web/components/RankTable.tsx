"use client";
import { useState } from "react";

export type RankRow = { id: string; name: string; color: string; values: Record<string, number | undefined> };
const COLS: { k: string; l: string; pct?: boolean }[] = [
  { k: "levels", l: "Levels" }, { k: "deaths", l: "Døde" }, { k: "pvp", l: "PvP-døde" }, { k: "bosses", l: "Bosser" },
  { k: "clears", l: "Clears" }, { k: "wipes", l: "Wipes" }, { k: "loot", l: "Loot" }, { k: "wins", l: "Rolls vundet" },
  { k: "needLoss", l: "Need tabt", pct: true },
  { k: "pts", l: "Trofæpoint" }, { k: "hours", l: "Timer" }, { k: "gold", l: "Guld" },
];

export default function RankTable({ rows }: { rows: RankRow[] }) {
  const [sort, setSort] = useState({ k: "pts", dir: -1 });
  const best: Record<string, number> = {};
  for (const c of COLS) best[c.k] = Math.max(...rows.map((r) => r.values[c.k] || 0));
  const sorted = [...rows].sort((a, b) => ((a.values[sort.k] || 0) - (b.values[sort.k] || 0)) * sort.dir || a.name.localeCompare(b.name));
  const click = (k: string) => setSort((s) => (s.k === k ? { k, dir: -s.dir } : { k, dir: -1 }));
  return (
    <div className="tablewrap">
      <table>
        <thead>
          <tr>
            <th>Ven</th>
            {COLS.map((c) => (
              <th key={c.k} aria-sort={c.k === sort.k ? (sort.dir < 0 ? "descending" : "ascending") : undefined}
                tabIndex={0} onClick={() => click(c.k)} onKeyDown={(e) => (e.key === "Enter" || e.key === " ") && click(c.k)}>
                {c.l}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((r, i) => (
            <tr key={r.id}>
              <td><span className="rank">{i + 1}</span><b style={{ color: r.color }}>{r.name}</b></td>
              {COLS.map((c) => {
                const raw = r.values[c.k];
                if (raw === undefined) return <td key={c.k} className="none">–</td>;
                const v = raw || 0;
                return <td key={c.k} className={v && v === best[c.k] ? "best" : undefined}>{v.toLocaleString("da-DK")}{c.pct ? "%" : ""}</td>;
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
