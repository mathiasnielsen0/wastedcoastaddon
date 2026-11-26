import { test } from "node:test";
import assert from "node:assert/strict";
import { buildModel } from "../lib/model.ts";

const char = (level: number) => ({ chars: { Murer: { class: "DRUID", level, seen: 100 } } });

test("en ring i dublet-koblingen skjuler ikke vennen (v0.33.2)", () => {
  // Som i Mathias' fil: det gamle og det nye ID peger på hinanden, data ligger på det nye
  const db = {
    group: { members: {
      uNY: { n: "Andreas", dup: "uGAMMEL" },
      uGAMMEL: { n: "Andreas", dup: "uNY" },
      uNICK: { n: "Nick" },
    } },
    friends: { uNY: char(25), uNICK: { chars: { Merry: { class: "ROGUE", level: 32, seen: 100 } } } },
    events: [{ friend: "uGAMMEL", name: "Murer", time: 50 }],
  };
  const m = buildModel(db);
  assert.deepEqual(m.people.map((p) => p.name), ["Nick", "Andreas"]);
  assert.equal(m.totals.levels, 57);
  assert.equal(m.byId.uNY.deaths, 1, "dødsfald på det gamle ID tæller hos vennen");
});

test("en almindelig dublet peger stadig på det viste ID", () => {
  const db = {
    group: { members: { uNY: { n: "Andreas" }, uGAMMEL: { n: "Andreas", dup: "uNY" } } },
    friends: { uNY: char(25), uGAMMEL: char(3) },
  };
  const m = buildModel(db);
  assert.deepEqual(m.people.map((p) => p.id), ["uNY"]);
});
