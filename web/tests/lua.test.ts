import { test } from "node:test";
import assert from "node:assert/strict";
import { parseBytes } from "../lib/lua.ts";

const enc = (s: string) => new TextEncoder().encode(s);

test("læser SavedVariables med arrays, objekter, tal og æøå", () => {
  const src = 'WastedCoastDB = {\r\n["me"] = "Søren",\r\n["n"] = -1.5e2,\r\n["list"] = {\r\n"a", -- [1]\r\n"b\\"c", -- [2]\r\n},\r\n["tom"] = {\r\n},\r\n[5] = true,\r\n}\r\nAndet = nil\r\n';
  const out = parseBytes(enc(src));
  const db = out.WastedCoastDB as Record<string, unknown>;
  assert.equal(db.me, "Søren");
  assert.equal(db.n, -150);
  assert.deepEqual(db.list, ["a", 'b"c']);
  assert.deepEqual(db.tom, []);
  assert.equal(db["5"], true);
});

test("tabeller med huller bliver til objekter", () => {
  const db = parseBytes(enc('X = { "a", [3] = "c", y = 1 }')).X as Record<string, unknown>;
  assert.deepEqual(db, { "1": "a", "3": "c", y: 1 });
});

test("escape-koder i strenge", () => {
  const db = parseBytes(enc('X = "linje\\nto \\195\\166"')).X;
  assert.equal(db, "linje\nto æ");
});
