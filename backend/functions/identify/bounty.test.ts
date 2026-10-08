// Le pack de la semaine : tirage reproductible, rareté locale, et course au premier
// chasseur — sur la vraie logique et les vraies migrations (PGlite).
import { test, describe, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { weeklyBounties, currentWeek, BOUNTY_SLOTS } from "./bounty";
import { createSocial } from "./social";

describe("tirage", () => {
  test("le même pack pour tous, la même semaine, dans le même pays", () => {
    const a = weeklyBounties("2026-10-05", "FR").map((t) => t.vehicle.id);
    const b = weeklyBounties("2026-10-05", "FR").map((t) => t.vehicle.id);
    assert.deepEqual(a, b);
    assert.equal(a.length, 3);
    assert.equal(new Set(a).size, 3);
  });

  test("un autre pays ou une autre semaine : un autre pack", () => {
    const fr = weeklyBounties("2026-10-05", "FR").map((t) => t.vehicle.id).join();
    assert.notEqual(fr, weeklyBounties("2026-10-12", "FR").map((t) => t.vehicle.id).join());
    assert.notEqual(fr, weeklyBounties("2026-10-05", "US").map((t) => t.vehicle.id).join());
  });

  test("chaque cible tombe dans sa bande de rareté locale, de la plus facile à la plus rare", () => {
    const targets = weeklyBounties("2026-10-05", "FR");
    targets.forEach((t, i) => assert.ok(BOUNTY_SLOTS[i].tiers.includes(t.tier.id), `${t.vehicle.id} ${t.tier.id}`));
    assert.ok(targets[2].bonus >= targets[0].bonus);
  });

  test("un pays jamais calibré a quand même trois cibles", () => {
    assert.equal(weeklyBounties("2026-10-05", "ZZ").length, 3);
  });

  test("la semaine commence le lundi, en UTC", () => {
    assert.equal(currentWeek(new Date("2026-10-11T23:30:00Z")), "2026-10-05");   // dimanche
    assert.equal(currentWeek(new Date("2026-10-12T00:00:00Z")), "2026-10-12");   // lundi
  });
});

describe("chasse", () => {
  const DIR = new URL("../../migrations/", import.meta.url);
  const MIGRATIONS = readdirSync(DIR).filter((f) => f.endsWith(".sql")).sort()
    .map((f) => readFileSync(new URL(f, DIR), "utf8"));
  let db: PGlite;
  let social: ReturnType<typeof createSocial>;
  const week = currentWeek();
  const target = weeklyBounties(week, "FR")[0];

  const call = async (action: string, install: string, body: Record<string, unknown> = {}) => {
    const res = await social(action, install, body);
    return { status: res.status, body: await res.json() as any };
  };
  const hunt = async (install: string, vehicle = target.vehicle.id) => {
    const scan = randomUUID();
    await db.query("insert into public.scans (id, install_hash, expected_vehicle, candidate_ids, confidence) values ($1,$2,$3,'{}',0.9)",
      [scan, install, vehicle]);
    return call("catch", install, { catch_id: randomUUID(), vehicle_id: vehicle, country: "FR",
                                    location_verified: true, scan_id: scan });
  };

  beforeEach(async () => {
    db = new PGlite();
    for (const sql of MIGRATIONS) await db.exec(sql);
    social = createSocial({ db: db as any, verifyApple: async () => ({ ok: false, reason: "test" }) });
  });

  test("le pack reste scellé jusqu'à l'ouverture", async () => {
    const sealed = await call("bounty", "a", { country: "FR" });
    assert.equal(sealed.body.opened, false);
    assert.equal(sealed.body.targets.length, 0);
    const open = await call("open_bounty", "a", { country: "FR" });
    assert.equal(open.body.opened, true);
    assert.equal(open.body.targets.length, 3);
  });

  test("le premier chasseur du pays prend le gros bonus, le suivant le bonus simple", async () => {
    const first = await hunt("a");
    assert.equal(first.body.bounty.first, true);
    assert.equal(first.body.bounty.bonus, target.bonus + target.firstBonus);
    const second = await hunt("b");
    assert.equal(second.body.bounty.first, false);
    assert.equal(second.body.bounty.bonus, target.bonus);
  });

  test("une cible ne paie qu'une fois par joueur", async () => {
    await hunt("a");
    assert.equal((await hunt("a")).body.bounty, null);
  });

  test("le bonus entre au classement de la semaine", async () => {
    const r = await hunt("a");
    const league = await call("league", "a");
    assert.equal(league.body.members[0].points, r.body.counted_points + r.body.bounty.bonus);
  });

  test("une prise qui ne compte pas au classement ne réclame pas la prime", async () => {
    const r = await call("catch", "a", { catch_id: randomUUID(), vehicle_id: target.vehicle.id, country: "FR",
                                         location_verified: false });
    assert.equal(r.body.bounty, null);
  });

  test("le pack ouvert montre qui a trouvé quoi", async () => {
    await call("set_pseudo", "a", { pseudo: "Alice" });
    await hunt("a");
    await call("open_bounty", "b", { country: "FR" });
    const view = await call("bounty", "b", { country: "FR" });
    const t = view.body.targets.find((x: any) => x.vehicle_id === target.vehicle.id);
    assert.equal(t.hunters, 1);
    assert.equal(t.first_hunter, "Alice");
    assert.equal(t.found, false);
  });
});
