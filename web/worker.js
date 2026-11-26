// WC4ever-websitets API (Cloudflare Worker).
//
//   POST /api/upload?flavor=_forever_&konto=SLATER1&navn=Mathias
//        Header: Authorization: Bearer <UPLOAD_KEY>
//        Body:   WastedCoast.lua (SavedVariables), gzip-pakket
//   GET  /api/list                 -> hvilke spilversioner der er data for, og hvornår
//   GET  /api/data?flavor=_forever_ -> den gzip-pakkede fil (siden pakker selv ud og læser den)
//
// Workeren læser ikke Lua-filen, den gemmer den bare (så CPU-forbruget er tæt på nul).
// Alt andet (index.html osv.) serveres fra public/.

const MAX_BYTES = 10 * 1024 * 1024;
const FLAVOR_RE = /^_[a-z_]{1,30}_$/;

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

// Sammenlign nøgler uden at afsløre, hvor mange tegn der passede
function sameKey(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || !b) return false;
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return diff === 0;
}

function short(s, n) {
  return String(s || "").replace(/[^\p{L}\p{N} _#.-]/gu, "").slice(0, n);
}

async function upload(req, env, url) {
  if (!env.UPLOAD_KEY) return json({ ok: false, error: "UPLOAD_KEY er ikke sat på serveren" }, 500);
  const auth = req.headers.get("authorization") || "";
  const key = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!sameKey(key, env.UPLOAD_KEY)) return json({ ok: false, error: "forkert nøgle" }, 401);

  const flavor = url.searchParams.get("flavor") || "";
  if (!FLAVOR_RE.test(flavor)) return json({ ok: false, error: "ugyldig flavor" }, 400);

  const body = new Uint8Array(await req.arrayBuffer());
  if (body.length < 20 || body.length > MAX_BYTES) return json({ ok: false, error: "ugyldig størrelse" }, 413);
  if (body[0] !== 0x1f || body[1] !== 0x8b) return json({ ok: false, error: "forventede gzip" }, 400);

  const meta = {
    t: Date.now(),
    size: body.length,
    mtime: Number(url.searchParams.get("mtime")) || 0,
    navn: short(url.searchParams.get("navn"), 40),
    konto: short(url.searchParams.get("konto"), 40),
    ver: short(url.searchParams.get("ver"), 20),
  };
  await env.WC_DATA.put("sv:" + flavor, body, { metadata: meta });
  return json({ ok: true, flavor, ...meta });
}

async function list(env) {
  const res = await env.WC_DATA.list({ prefix: "sv:" });
  const out = res.keys.map((k) => ({ flavor: k.name.slice(3), ...(k.metadata || {}) }));
  out.sort((a, b) => (b.t || 0) - (a.t || 0));
  return json({ ok: true, flavors: out });
}

async function data(env, url) {
  const flavor = url.searchParams.get("flavor") || "";
  if (!FLAVOR_RE.test(flavor)) return json({ ok: false, error: "ugyldig flavor" }, 400);
  const { value, metadata } = await env.WC_DATA.getWithMetadata("sv:" + flavor, { type: "arrayBuffer" });
  if (!value) return json({ ok: false, error: "ingen data endnu" }, 404);
  return new Response(value, {
    headers: {
      "content-type": "application/octet-stream",
      "cache-control": "no-cache",
      "x-wc-meta": encodeURIComponent(JSON.stringify(metadata || {})),
    },
  });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname.startsWith("/api/")) {
      try {
        if (url.pathname === "/api/upload" && req.method === "POST") return await upload(req, env, url);
        if (url.pathname === "/api/list" && req.method === "GET") return await list(env);
        if (url.pathname === "/api/data" && req.method === "GET") return await data(env, url);
        return json({ ok: false, error: "ukendt" }, 404);
      } catch (e) {
        return json({ ok: false, error: String(e && e.message || e) }, 500);
      }
    }
    return env.ASSETS.fetch(req);
  },
};
