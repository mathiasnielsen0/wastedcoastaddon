// Lageret: én række pr. spilversion i Neon Postgres med den seneste SavedVariables-fil (gzip,
// base64) og hvem der sendte den. Tabellen oprettes selv første gang.
import { neon } from "@neondatabase/serverless";
import { gunzipSync } from "node:zlib";
import { parseBytes } from "./lua";
import { promises as fs } from "node:fs";
import path from "node:path";

// Til udvikling uden database: WC_LOCAL_STORE=./.lokal-data gemmer filerne i en mappe
const LOCAL = process.env.WC_LOCAL_STORE;
const localFile = (flavor: string) => path.join(LOCAL!, flavor + ".json");

export type Meta = { flavor: string; t: number; size: number; mtime: number; navn: string; konto: string; ver: string };

function sql() {
  const url = process.env.DATABASE_URL || process.env.POSTGRES_URL;
  if (!url) throw new Error("DATABASE_URL er ikke sat (forbind Neon-databasen i Vercel)");
  return neon(url);
}

let ready: Promise<unknown> | null = null;
function ensureTable() {
  ready ??= sql()`CREATE TABLE IF NOT EXISTS savedvars (
    flavor text PRIMARY KEY,
    data text NOT NULL,
    meta jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
  )`.catch((e) => { ready = null; throw e; });
  return ready;
}

export async function saveUpload(flavor: string, gz: Uint8Array, meta: Meta) {
  const b64 = Buffer.from(gz).toString("base64");
  if (LOCAL) {
    await fs.mkdir(LOCAL, { recursive: true });
    return fs.writeFile(localFile(flavor), JSON.stringify({ data: b64, meta }));
  }
  await ensureTable();
  await sql()`INSERT INTO savedvars (flavor, data, meta, updated_at) VALUES (${flavor}, ${b64}, ${JSON.stringify(meta)}, now())
    ON CONFLICT (flavor) DO UPDATE SET data = EXCLUDED.data, meta = EXCLUDED.meta, updated_at = now()`;
}

export async function listFlavors(): Promise<Meta[]> {
  if (LOCAL) {
    const files = await fs.readdir(LOCAL).catch(() => [] as string[]);
    const metas = await Promise.all(files.filter((f) => f.endsWith(".json"))
      .map(async (f) => JSON.parse(await fs.readFile(path.join(LOCAL, f), "utf8")).meta as Meta));
    return metas.sort((a, b) => b.t - a.t);
  }
  await ensureTable();
  const rows = (await sql()`SELECT meta FROM savedvars ORDER BY updated_at DESC`) as { meta: Meta }[];
  return rows.map((r) => r.meta);
}

export async function getGzip(flavor: string): Promise<{ gz: Buffer; meta: Meta } | null> {
  if (LOCAL) {
    const raw = await fs.readFile(localFile(flavor), "utf8").catch(() => null);
    if (!raw) return null;
    const j = JSON.parse(raw);
    return { gz: Buffer.from(j.data, "base64"), meta: j.meta };
  }
  await ensureTable();
  const rows = (await sql()`SELECT data, meta FROM savedvars WHERE flavor = ${flavor}`) as { data: string; meta: Meta }[];
  if (!rows.length) return null;
  return { gz: Buffer.from(rows[0].data, "base64"), meta: rows[0].meta };
}

// Den læste fil gemmes i hukommelsen, så længe den samme upload er den nyeste
const cache = new Map<string, { t: number; db: unknown }>();

export async function getDB(flavor: string, meta: Meta): Promise<unknown> {
  const hit = cache.get(flavor);
  if (hit && hit.t === meta.t) return hit.db;
  const row = await getGzip(flavor);
  if (!row) return null;
  const db = parseBytes(gunzipSync(row.gz)).WastedCoastDB ?? null;
  cache.set(flavor, { t: row.meta.t, db });
  return db;
}
