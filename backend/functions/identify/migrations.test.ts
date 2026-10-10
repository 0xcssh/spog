// Exécute les vraies migrations SQL sur un Postgres embarqué (PGlite, WASM) : pas de
// serveur à lancer, ni en local ni en CI. La logique des ligues et des prises vit en SQL
// parce qu'elle doit tenir face aux requêtes simultanées ; c'est donc là qu'on la teste.
import { test, describe, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";

const DIR = new URL("../../migrations/", import.meta.url);
const MIGRATIONS = readdirSync(DIR).filter((f) => f.endsWith(".sql")).sort()
  .map((f) => readFileSync(new URL(f, DIR), "utf8"));

let db: PGlite;

async function fresh() {
  db = new PGlite();
  for (const sql of MIGRATIONS) await db.exec(sql);
}

async function player(install = randomUUID()): Promise<string> {
  const { rows } = await db.query<{ id: string }>("select public.player_for_install($1) as id", [install]);
  return rows[0].id;
}

async function record(p: string, opts: Partial<{ id: string; vehicle: string; country: string; loc: boolean;
  veh: boolean; points: number; bonus: number }> = {}) {
  const { rows } = await db.query<{ r: any }>(
    "select public.record_catch($1,$2,$3,$4,now(),$5,$6,null,'rare',$7,$8) as r",
    [opts.id ?? randomUUID(), p, opts.vehicle ?? "porsche-macan", opts.country ?? "FR",
     opts.loc ?? true, opts.veh ?? true, opts.points ?? 150, opts.bonus ?? 100]);
  return rows[0].r;
}

/// Simule une semaine passée : déplace les inscriptions de la semaine courante d'une semaine en arrière.
async function endWeek() {
  await db.exec("update public.league_members set week = week - 7");
}

describe("migrations", () => {
  test("idempotentes : rejouables sur une base existante", async () => {
    await fresh();
    for (const sql of MIGRATIONS) await db.exec(sql);
    const { rows } = await db.query<{ n: number }>("select count(*)::int as n from pg_proc where proname = 'record_catch'");
    assert.equal(rows[0].n, 1);
  });
});

describe("joueurs", () => {
  beforeEach(fresh);

  test("une installation donne toujours le même joueur", async () => {
    const install = randomUUID();
    assert.equal(await player(install), await player(install));
    assert.notEqual(await player(install), await player());
  });

  test("pseudo unique sans tenir compte de la casse", async () => {
    const a = await player(), b = await player();
    await db.query("update public.players set pseudo = 'Keno' where id = $1", [a]);
    await assert.rejects(db.query("update public.players set pseudo = 'keno' where id = $1", [b]));
  });

  test("Sign in with Apple : une nouvelle installation retrouve le joueur et y apporte ses prises", async () => {
    const phone = randomUUID(), newPhone = randomUUID();
    const owner = await player(phone);
    await db.query("select public.link_apple($1, 'apple-sub-1')", [phone]);
    const anonymous = await player(newPhone);
    await record(anonymous, { vehicle: "renault-clio" });
    const { rows } = await db.query<{ id: string }>("select public.link_apple($1, 'apple-sub-1') as id", [newPhone]);
    assert.equal(rows[0].id, owner);
    assert.equal(await player(newPhone), owner);
    const catches = await db.query<{ n: number }>("select count(*)::int as n from public.catches where player_id = $1", [owner]);
    assert.equal(catches.rows[0].n, 1);
  });
});

describe("prises", () => {
  beforeEach(fresh);

  test("idempotente : la même prise renvoyée ne compte qu'une fois", async () => {
    const p = await player(), id = randomUUID();
    await record(p, { id });
    const again = await record(p, { id });
    assert.equal(again.duplicate, true);
    const { rows } = await db.query<{ points: number }>("select points from public.league_members where player_id = $1", [p]);
    assert.equal(rows[0].points, 150 + 100);
  });

  test("le premier repéreur d'un modèle dans un pays prend le bonus, pas le second", async () => {
    const a = await player(), b = await player();
    assert.equal((await record(a)).first_spot, true);
    const second = await record(b);
    assert.equal(second.first_spot, false);
    assert.equal(second.counted_points, 150);
  });

  test("un autre pays a son propre premier repéreur", async () => {
    const a = await player(), b = await player();
    await record(a, { country: "FR" });
    assert.equal((await record(b, { country: "US" })).first_spot, true);
  });

  test("pays non vérifié ou modèle non vérifié : la carte existe, rien au classement", async () => {
    const p = await player();
    for (const opts of [{ loc: false }, { veh: false }]) {
      const r = await record(p, opts);
      assert.equal(r.counted_points, 0);
      assert.equal(r.first_spot, false);
    }
    const { rows } = await db.query("select * from public.league_members where player_id = $1", [p]);
    assert.equal(rows.length, 0);
  });

  test("champs de carte (008) : facultatifs, record_catch inchangé les laisse vides", async () => {
    const p = await player(), id = randomUUID();
    await record(p, { id });
    const { rows } = await db.query<any>(
      "select serial, paint, price_low, price_high, price_currency from public.catches where id = $1", [id]);
    assert.deepEqual(rows[0], { serial: null, paint: null, price_low: null, price_high: null, price_currency: null });
  });

  test("on ne rejoue pas la prise d'un autre joueur", async () => {
    const a = await player(), b = await player(), id = randomUUID();
    await record(a, { id });
    assert.equal((await record(b, { id })).error, "not_owner");
  });

  test("retirer une prise de la semaine retire ses points", async () => {
    const p = await player(), id = randomUUID();
    await record(p, { id });
    await db.query("select public.uncount_catch($1)", [id]);
    const { rows } = await db.query<{ points: number }>("select points from public.league_members where player_id = $1", [p]);
    assert.equal(rows[0].points, 0);
  });
});

describe("ligues", () => {
  beforeEach(fresh);

  test("des groupes de 30 au plus", async () => {
    for (let i = 0; i < 31; i++) await record(await player(), { vehicle: `car-${i}` });
    const { rows } = await db.query<{ group_no: number; n: number }>(
      "select group_no, count(*)::int as n from public.league_members group by group_no order by group_no");
    assert.deepEqual(rows.map((r) => r.n), [30, 1]);
  });

  test("les 7 premiers montent, les 5 derniers descendent, le milieu reste", async () => {
    // Un groupe de 20 au palier 2 : points décroissants avec le rang.
    const ids: string[] = [];
    for (let i = 0; i < 20; i++) ids.push(await player());
    for (let i = 0; i < 20; i++) {
      await db.query("insert into public.league_members (week, player_id, tier, group_no, points, joined_at) " +
        "values (public.current_week() - 7, $1, 2, 1, $2, now())", [ids[i], 1000 - i * 10]);
    }
    const tierOf = async (p: string) => (await db.query<{ t: number }>(
      "select public.league_tier_for($1, public.current_week()) as t", [p])).rows[0].t;
    assert.equal(await tierOf(ids[0]), 3);   // 1er
    assert.equal(await tierOf(ids[6]), 3);   // 7e
    assert.equal(await tierOf(ids[7]), 2);   // 8e
    assert.equal(await tierOf(ids[14]), 2);  // 15e
    assert.equal(await tierOf(ids[15]), 1);  // 16e, dans les 5 derniers
    assert.equal(await tierOf(ids[19]), 1);
  });

  test("un nouveau joueur commence au premier palier", async () => {
    const p = await player();
    const r = await record(p);
    assert.equal(r.league_tier, 0);
  });

  test("la semaine suivante, le promu entre au palier supérieur", async () => {
    const p = await player();
    await record(p);       // seul de son groupe : 1er avec des points
    await endWeek();
    const r = await record(p, { vehicle: "renault-clio" });
    assert.equal(r.league_tier, 1);
  });
});

describe("quotas du jour", () => {
  beforeEach(fresh);

  const left = async (install: string, kind = "scan") => (await db.query<{ n: number }>(
    "select public.allowance_left($1, $2, 10, 3) as n", [install, kind])).rows[0].n;
  const consume = (install: string, kind = "scan") =>
    db.query("select public.consume_allowance($1, $2)", [install, kind]);

  test("premier jour : 10, et chaque consommation en retire un", async () => {
    assert.equal(await left("i1"), 10);
    await consume("i1"); await consume("i1");
    assert.equal(await left("i1"), 8);
  });

  test("les jours suivants : 3", async () => {
    await left("i2");
    await db.exec("update public.install_days set first_day = first_day - 1 where install_hash = 'i2'");
    assert.equal(await left("i2"), 3);
  });

  test("hier ne compte plus aujourd'hui", async () => {
    await left("i3");
    await consume("i3");
    await db.exec("update public.usage_days set day = day - 1 where install_hash = 'i3'");
    assert.equal(await left("i3"), 10);
  });

  test("les rendus se comptent à part des scans", async () => {
    await consume("i4", "scan");
    assert.equal(await left("i4", "develop"), 10);
  });
});
