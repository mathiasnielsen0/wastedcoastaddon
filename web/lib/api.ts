import { timingSafeEqual } from "node:crypto";

export const FLAVOR_RE = /^_[a-z_]{1,30}_$/;
export const MAX_BYTES = 4 * 1024 * 1024; // Vercel tillader 4,5 MB pr. request

export function json(obj: unknown, status = 200) {
  return Response.json(obj, { status, headers: { "cache-control": "no-store" } });
}

export function keyOk(header: string | null): boolean {
  const want = process.env.UPLOAD_KEY || "";
  const got = header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!want || !got) return false;
  const a = Buffer.from(got), b = Buffer.from(want);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function short(s: string | null, n: number) {
  return String(s || "").replace(/[^\p{L}\p{N} _#.-]/gu, "").slice(0, n);
}
