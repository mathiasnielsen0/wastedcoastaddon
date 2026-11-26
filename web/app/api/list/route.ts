// GET /api/list: hvilke spilversioner der er data for, og hvornår de blev sendt
import { json } from "@/lib/api";
import { listFlavors } from "@/lib/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return json({ ok: true, flavors: await listFlavors() });
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
}
