// POST /api/upload?flavor=_forever_&konto=SLATER1&navn=Mathias&mtime=...&ver=...
// Header: Authorization: Bearer <UPLOAD_KEY>. Body: WastedCoast.lua, gzip-pakket (fra sync/).
import { FLAVOR_RE, MAX_BYTES, json, keyOk, short } from "@/lib/api";
import { saveUpload } from "@/lib/store";
import { gunzipSync } from "node:zlib";

export const runtime = "nodejs";

export async function POST(req: Request) {
  if (!process.env.UPLOAD_KEY) return json({ ok: false, error: "UPLOAD_KEY er ikke sat på serveren" }, 500);
  if (!keyOk(req.headers.get("authorization"))) return json({ ok: false, error: "forkert nøgle" }, 401);
  const url = new URL(req.url);
  const flavor = url.searchParams.get("flavor") || "";
  if (!FLAVOR_RE.test(flavor)) return json({ ok: false, error: "ugyldig flavor" }, 400);

  const body = new Uint8Array(await req.arrayBuffer());
  if (body.length < 20 || body.length > MAX_BYTES) return json({ ok: false, error: "ugyldig størrelse" }, 413);
  if (body[0] !== 0x1f || body[1] !== 0x8b) return json({ ok: false, error: "forventede gzip" }, 400);
  try {
    const head = gunzipSync(body).subarray(0, 4096).toString("latin1");
    if (!head.includes("WastedCoastDB")) return json({ ok: false, error: "ikke WC4ever-data" }, 400);
  } catch {
    return json({ ok: false, error: "ødelagt gzip" }, 400);
  }

  const meta = {
    flavor,
    t: Date.now(),
    size: body.length,
    mtime: Number(url.searchParams.get("mtime")) || 0,
    navn: short(url.searchParams.get("navn"), 40),
    konto: short(url.searchParams.get("konto"), 40),
    ver: short(url.searchParams.get("ver"), 20),
  };
  try {
    await saveUpload(flavor, body, meta);
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
  return json({ ok: true, ...meta });
}
