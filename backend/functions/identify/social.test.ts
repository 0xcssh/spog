// La couche sociale de bout en bout : vraie logique TypeScript, vraies migrations SQL
// (PGlite). Ce sont les règles qui décident qui gagne une ligue : elles se testent
// contre la vraie base, pas contre une doublure.
import { test, describe, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { generateKeyPairSync, randomUUID, sign } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import { createSocial } from "./social";
import { createAppleVerifier, APPLE_ISSUER, BUNDLE_ID } from "./apple";
import { resolve } from "./catalog";

const DIR = new URL("../../migrations/", import.meta.url);
const MIGRATIONS = readdirSync(DIR).filter((f) => f.endsWith(".sql")).sort()
  .map((f) => readFileSync(new URL(f, DIR), "utf8"));

let db: PGlite;
let social: ReturnType<typeof createSocial>;

async function call(action: string, install: string, body: Record<string, unknown> = {}) {
  const res = await social(action, install, body);
  return { status: res.status, body: await res.json() as any };
}

async function scan(install: string, expected: string, candidates: string[] = []) {
  const id = randomUUID();
  await db.query("insert into public.scans (id, install_hash, expected_vehicle, candidate_ids, confidence) values ($1,$2,$3,$4,0.9)",
    [id, install, expected, candidates]);
  return id;
}

async function caught(install: string, vehicle: string, opts: { scan?: string | null; country?: string; located?: boolean } = {}) {
  return call("catch", install, {
    catch_id: randomUUID(), vehicle_id: vehicle, country: opts.country ?? "FR",
    caught_at: new Date().toISOString(), location_verified: opts.located ?? true,
    scan_id: opts.scan === undefined ? await scan(install, vehicle) : opts.scan,
  });
}

beforeEach(async () => {
  db = new PGlite();
  for (const sql of MIGRATIONS) await db.exec(sql);
  social = createSocial({
    db: db as any,
    verifyApple: async (token) => (token === "good" ? { ok: true, sub: "apple-1" } : { ok: false, reason: "bad" }),
  });
});

describe("joueur", () => {
  test("créé à la première requête, sans pseudo", async () => {
    const r = await call("me", "install-a");
    assert.equal(r.status, 200);
    assert.equal(r.body.pseudo, null);
    assert.equal(r.body.catches, 0);
  });

  test("pseudo : forme imposée, unicité", async () => {
    assert.equal((await call("set_pseudo", "a", { pseudo: "x" })).body.code, "pseudo_invalid");
    assert.equal((await call("set_pseudo", "a", { pseudo: "Keno_75" })).status, 200);
    assert.equal((await call("set_pseudo", "b", { pseudo: "keno_75" })).body.code, "pseudo_taken");
  });

  test("supprimer son compte efface pseudo et prises ; la requête suivante repart de zéro", async () => {
    await call("set_pseudo", "a", { pseudo: "Alice" });
    await caught("a", "porsche-macan");
    assert.equal((await call("delete_account", "a")).status, 200);
    const me = await call("me", "a");
    assert.equal(me.body.pseudo, null);
    assert.equal(me.body.catches, 0);
    assert.equal((await call("set_pseudo", "b", { pseudo: "Alice" })).status, 200);   // pseudo libéré
  });

  test("compte Apple : jeton refusé, puis rattachement", async () => {
    assert.equal((await call("apple_link", "a", { identity_token: "bad" })).status, 401);
    const r = await call("apple_link", "a", { identity_token: "good" });
    assert.equal(r.body.apple_linked, true);
  });
});

describe("prises et points", () => {
  test("une prise identifiée ici compte au classement, au tarif du pays", async () => {
    const r = await caught("a", "porsche-macan", { country: "FR" });
    const value = resolve("porsche-macan", "FR").points;
    assert.equal(r.body.vehicle_verified, true);
    assert.equal(r.body.first_spot, true);
    assert.equal(r.body.counted_points, value * 2);   // premier repéreur : valeur doublée
    assert.equal(r.body.league_tier, "bronze");
  });

  test("déclarer une autre voiture que celle identifiée : la carte, pas les points", async () => {
    const s = await scan("a", "renault-clio");
    const r = await caught("a", "ferrari-488-gtb", { scan: s });
    assert.equal(r.body.vehicle_verified, false);
    assert.equal(r.body.counted_points, 0);
    assert.ok(r.body.points > 0);
  });

  test("une proposition montrée au joueur est un choix légitime", async () => {
    const s = await scan("a", "renault-clio", ["renault-clio", "renault-megane"]);
    assert.equal((await caught("a", "renault-megane", { scan: s })).body.vehicle_verified, true);
  });

  test("l'identification d'une autre installation ne sert pas", async () => {
    const s = await scan("b", "porsche-macan");
    assert.equal((await caught("a", "porsche-macan", { scan: s })).body.counted_points, 0);
  });

  test("une identification ne sert qu'une fois", async () => {
    const s = await scan("a", "porsche-macan");
    await caught("a", "porsche-macan", { scan: s });
    assert.equal((await caught("a", "porsche-macan", { scan: s })).body.counted_points, 0);
  });

  test("pays choisi à la main : rien au classement", async () => {
    assert.equal((await caught("a", "porsche-macan", { located: false })).body.counted_points, 0);
  });

  test("corriger vers une proposition rend la prise juste ; vers autre chose, la sort du classement", async () => {
    const s = await scan("a", "renault-clio", ["renault-clio", "renault-megane"]);
    const id = randomUUID();
    await call("catch", "a", { catch_id: id, vehicle_id: "renault-clio", country: "FR", location_verified: true, scan_id: s });
    const ok = await call("reassign", "a", { catch_id: id, vehicle_id: "renault-megane" });
    assert.equal(ok.body.vehicle_verified, true);
    const cheat = await call("reassign", "a", { catch_id: id, vehicle_id: "ferrari-488-gtb" });
    assert.equal(cheat.body.counted_points, 0);
    const league = await call("league", "a");
    assert.equal(league.body.members[0].points, 0);
  });

  test("supprimer une prise retire ses points de la semaine", async () => {
    const id = randomUUID();
    const s = await scan("a", "porsche-macan");
    await call("catch", "a", { catch_id: id, vehicle_id: "porsche-macan", country: "FR", location_verified: true, scan_id: s });
    await call("delete_catch", "a", { catch_id: id });
    assert.equal((await call("league", "a")).body.members[0].points, 0);
    assert.equal((await call("garage", "a")).body.catches.length, 0);
  });

  test("on ne corrige pas la prise d'un autre", async () => {
    const id = randomUUID();
    await call("catch", "a", { catch_id: id, vehicle_id: "renault-clio", country: "FR", location_verified: true });
    assert.equal((await call("reassign", "b", { catch_id: id, vehicle_id: "renault-megane" })).status, 403);
  });
});

describe("ligue", () => {
  test("avant toute prise : pas inscrit, palier de départ annoncé", async () => {
    const r = await call("league", "a");
    assert.equal(r.body.joined, false);
    assert.equal(r.body.tier, "bronze");
  });

  test("classement du groupe, pseudos et position du joueur", async () => {
    await call("set_pseudo", "a", { pseudo: "Alice" });
    await caught("a", "renault-clio");
    await caught("b", "porsche-macan");
    const r = await call("league", "a");
    assert.equal(r.body.joined, true);
    assert.equal(r.body.members.length, 2);
    assert.ok(r.body.members[0].points >= r.body.members[1].points);
    const me = r.body.members.find((m: any) => m.me);
    assert.equal(me.pseudo, "Alice");
    assert.match(r.body.ends_at, /^\d{4}-\d{2}-\d{2}T00:00:00/);
  });
});

describe("jeton Sign in with Apple", () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-kid", alg: "RS256", use: "sig" };
  const keysFetch = (async () => new Response(JSON.stringify({ keys: [jwk] }))) as unknown as typeof fetch;
  const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const token = (claims: Record<string, unknown>, kid = "test-kid") => {
    const head = b64({ alg: "RS256", kid });
    const body = b64({ iss: APPLE_ISSUER, aud: BUNDLE_ID, sub: "001234.abcd", exp: Math.floor(Date.now() / 1000) + 600, ...claims });
    return `${head}.${body}.${sign("RSA-SHA256", Buffer.from(`${head}.${body}`), privateKey).toString("base64url")}`;
  };
  const verify = createAppleVerifier(keysFetch);

  test("un jeton valide donne l'identifiant Apple", async () => {
    assert.deepEqual(await verify(token({})), { ok: true, sub: "001234.abcd" });
  });

  test("destinataire, émetteur, expiration et clé sont vérifiés", async () => {
    assert.equal((await verify(token({ aud: "com.other.app" }))).ok, false);
    assert.equal((await verify(token({ iss: "https://evil.example" }))).ok, false);
    assert.equal((await verify(token({ exp: 1 }))).ok, false);
    assert.equal((await verify(token({}, "unknown-kid"))).ok, false);
  });

  test("une signature altérée est refusée", async () => {
    const t = token({});
    const forged = t.slice(0, t.lastIndexOf(".") + 1) + Buffer.from("nope").toString("base64url");
    assert.equal((await verify(forged)).ok, false);
  });
});

describe("duels", () => {
  test("défier, rejoindre, puis chacun marque les points de ses prises pendant le duel", async () => {
    await call("set_pseudo", "b", { pseudo: "Bob" });
    const created = await call("duel_create", "a");
    assert.match(created.body.code, /^[A-Z2-9]{6}$/);
    const joined = await call("duel_join", "b", { code: created.body.code.toLowerCase() });
    assert.equal(joined.status, 200);
    await caught("a", "porsche-macan");
    const view = await call("duels", "a");
    const d = view.body.duels[0];
    assert.equal(d.joined, true);
    assert.equal(d.opponent, "Bob");
    assert.ok(d.my_points > 0);
    assert.equal(d.their_points, 0);
    assert.equal(d.code, null);   // plus besoin de partager un code déjà utilisé
  });

  test("les prises d'avant le duel ne comptent pas", async () => {
    await caught("a", "porsche-macan");
    const { body } = await call("duel_create", "a");
    await call("duel_join", "b", { code: body.code });
    assert.equal((await call("duels", "a")).body.duels[0].my_points, 0);
  });

  test("on ne rejoint ni son propre défi, ni un défi déjà pris, ni un code inconnu", async () => {
    const { body } = await call("duel_create", "a");
    assert.equal((await call("duel_join", "a", { code: body.code })).body.code, "duel_own");
    await call("duel_join", "b", { code: body.code });
    assert.equal((await call("duel_join", "c", { code: body.code })).body.code, "duel_taken");
    assert.equal((await call("duel_join", "c", { code: "ZZZZZZ" })).status, 404);
  });

  test("cinq duels en cours au plus", async () => {
    for (let i = 0; i < 5; i++) assert.equal((await call("duel_create", "a")).status, 200);
    assert.equal((await call("duel_create", "a")).body.code, "too_many_duels");
  });

  test("les codes évitent les caractères qu'on confond", async () => {
    const { duelCode } = await import("./social");
    for (let i = 0; i < 200; i++) assert.doesNotMatch(duelCode(), /[01OIL]/);
  });
});

describe("garage (restauration sur un autre iPhone)", () => {
  const card = { serial: 7, paint: 0x1E3A8A, price: { low: 21000, high: 26000, currency: "EUR" } };

  test("rend chaque carte avec numéro, teinte, cote et identification", async () => {
    const id = randomUUID(), s = await scan("a", "porsche-macan");
    const caughtAt = "2026-10-01T09:30:00.000Z";
    await call("catch", "a", { catch_id: id, vehicle_id: "porsche-macan", country: "FR", caught_at: caughtAt,
                                location_verified: true, scan_id: s, ...card });
    const { body } = await call("garage", "a");
    assert.equal(body.catches.length, 1);
    const c = body.catches[0];
    assert.equal(c.id, id);
    assert.equal(c.vehicle_id, "porsche-macan");
    assert.equal(c.caught_at, caughtAt);
    assert.equal(c.scan_id, s);
    assert.equal(c.serial, 7);
    assert.equal(c.paint, 0x1E3A8A);
    assert.deepEqual(c.price, card.price);
    assert.equal(c.first_spot, true);
    assert.equal(c.location_verified, true);
  });

  test("une deuxième installation rattachée au même compte Apple retrouve les cartes", async () => {
    await call("apple_link", "old-phone", { identity_token: "good" });
    const id = randomUUID();
    await call("catch", "old-phone", { catch_id: id, vehicle_id: "renault-clio", country: "FR",
                                       location_verified: false, ...card });
    assert.equal((await call("garage", "new-phone")).body.catches.length, 0);
    const linked = await call("apple_link", "new-phone", { identity_token: "good" });
    assert.equal(linked.body.catches, 1);   // le compteur que l'app compare à son garage
    const { body } = await call("garage", "new-phone");
    assert.deepEqual(body.catches.map((c: any) => [c.id, c.serial]), [[id, 7]]);
  });

  test("une prise supprimée ne revient pas", async () => {
    const kept = randomUUID(), gone = randomUUID();
    for (const id of [kept, gone]) {
      await call("catch", "a", { catch_id: id, vehicle_id: "renault-clio", country: "FR", location_verified: false });
    }
    await call("delete_catch", "a", { catch_id: gone });
    assert.deepEqual((await call("garage", "a")).body.catches.map((c: any) => c.id), [kept]);
  });

  test("ancien client : sans numéro, teinte ni cote, la prise passe et le garage dit null", async () => {
    assert.equal((await caught("a", "renault-clio")).status, 200);
    const c = (await call("garage", "a")).body.catches[0];
    assert.equal(c.serial, null);
    assert.equal(c.paint, null);
    assert.equal(c.price, null);
  });

  test("champs invalides : ignorés un par un, la prise passe quand même", async () => {
    const cases: Array<[Record<string, unknown>, { serial?: number; paint?: number }, boolean]> = [
      [{ serial: 0, paint: 0x1000000, price: { low: 10, high: 5, currency: "EUR" } }, {}, false],
      [{ serial: 1.5, paint: -1, price: { low: 10, high: 20, currency: "eur" } }, {}, false],
      [{ serial: "3", paint: "16777215", price: "cher" }, {}, false],
      [{ serial: 1_000_001, price: { low: 10, high: Number.MAX_SAFE_INTEGER + 2, currency: "EUR" } }, {}, false],
      [{ serial: 3, paint: 0xFFFFFF, price: { low: 0, high: 20, currency: "EUR" } }, { serial: 3, paint: 0xFFFFFF }, false],
      // Une cote en dongs dépasse un entier 32 bits : elle doit passer intacte.
      [{ paint: 0, price: { low: 1, high: 75_000_000_000, currency: "VND" } }, { paint: 0 }, true],
    ];
    for (const [i, [fields, expected, priced]] of cases.entries()) {
      const install = `invalid-${i}`, label = JSON.stringify(fields);
      const r = await call("catch", install, { catch_id: randomUUID(), vehicle_id: "renault-clio", country: "FR",
                                               location_verified: false, ...fields });
      assert.equal(r.status, 200, label);
      const c = (await call("garage", install)).body.catches[0];
      assert.equal(c.serial, expected.serial ?? null, label);
      assert.equal(c.paint, expected.paint ?? null, label);
      assert.equal(c.price !== null, priced, label);
      if (priced) assert.equal(c.price.high, 75_000_000_000);
    }
  });

  test("une prise renvoyée ne réécrit pas la carte déjà gardée", async () => {
    const base = { catch_id: randomUUID(), vehicle_id: "renault-clio", country: "FR", location_verified: false };
    await call("catch", "a", { ...base, ...card });
    await call("catch", "a", { ...base, serial: 99, paint: 0, price: { low: 1, high: 2, currency: "USD" } });
    const c = (await call("garage", "a")).body.catches[0];
    assert.equal(c.serial, 7);
    assert.equal(c.paint, 0x1E3A8A);
    assert.deepEqual(c.price, card.price);
  });

  test("on ne pose pas de décor sur la prise d'un autre", async () => {
    const id = randomUUID();
    await call("catch", "a", { catch_id: id, vehicle_id: "renault-clio", country: "FR", location_verified: false });
    const r = await call("catch", "b", { catch_id: id, vehicle_id: "renault-clio", country: "FR", ...card });
    assert.equal(r.status, 403);
    assert.equal((await call("garage", "a")).body.catches[0].serial, null);
  });
});
