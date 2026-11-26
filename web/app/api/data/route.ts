// GET /api/data?flavor=_forever_: den seneste fil, gzip-pakket (til backup eller andre værktøjer)
import { FLAVOR_RE, json } from "@/lib/api";
import { getGzip } from "@/lib/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const flavor = new URL(req.url).searchParams.get("flavor") || "";
  if (!FLAVOR_RE.test(flavor)) return json({ ok: false, error: "ugyldig flavor" }, 400);
  const row = await getGzip(flavor);
  if (!row) return json({ ok: false, error: "ingen data endnu" }, 404);
  return new Response(new Uint8Array(row.gz), {
    headers: {
      "content-type": "application/gzip",
      "content-disposition": `attachment; filename="WastedCoast${flavor}.lua.gz"`,
      "cache-control": "no-store",
    },
  });
}
