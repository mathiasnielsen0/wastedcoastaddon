export const fmt = (n: number) => Math.round(n || 0).toLocaleString("da-DK");
export const goldOf = (copper: number) => Math.floor((copper || 0) / 10000);

export function ago(t: number, now = Date.now() / 1000) {
  if (!t) return "aldrig";
  const s = Math.max(0, now - t);
  if (s < 90) return "lige nu";
  if (s < 3600) return `${Math.round(s / 60)} min siden`;
  if (s < 86400 * 1.5) return `${Math.round(s / 3600)} t siden`;
  if (s < 86400 * 30) return `${Math.round(s / 86400)} d siden`;
  return new Date(t * 1000).toLocaleDateString("da-DK", { day: "numeric", month: "short", timeZone: "Europe/Copenhagen" });
}
