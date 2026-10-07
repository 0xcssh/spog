import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { X509Certificate, createPrivateKey, sign } from "node:crypto";
import { verifyEntitlement, appleRootCertificate, APPLE_ROOT_CA_G3_SHA256 } from "./entitlement";
import {
  TEST_ROOT_B64, TEST_INTERMEDIATE_B64, TEST_LEAF_B64, TEST_ROGUE_LEAF_B64,
  TEST_LEAF_KEY, TEST_ROGUE_KEY, TEST_INTERMEDIATE_KEY,
} from "./test-fixtures";

const testRoot = new X509Certificate(Buffer.from(TEST_ROOT_B64, "base64"));
const NOW = Date.now();
const DAY = 86_400_000;

const b64url = (v: unknown) => Buffer.from(typeof v === "string" ? v : JSON.stringify(v)).toString("base64url");

function transaction(extra: Record<string, unknown> = {}) {
  return {
    transactionId: "2000000999",
    originalTransactionId: "2000000123",
    bundleId: "com.mandalore-group.spog",
    productId: "com.mandaloregroup.spog.premium.yearly",
    purchaseDate: NOW - 10 * DAY,
    expiresDate: NOW + 355 * DAY,
    type: "Auto-Renewable Subscription",
    environment: "Production",
    signedDate: NOW,
    ...extra,
  };
}

function makeJWS(
  payload: unknown,
  { x5c = [TEST_LEAF_B64, TEST_INTERMEDIATE_B64, TEST_ROOT_B64], key = TEST_LEAF_KEY, alg = "ES256" as unknown } = {},
): string {
  const h = b64url({ alg, x5c });
  const p = b64url(payload);
  const sig = sign("sha256", Buffer.from(`${h}.${p}`), { key: createPrivateKey(key), dsaEncoding: "ieee-p1363" });
  return `${h}.${p}.${sig.toString("base64url")}`;
}

const verify = (jws: unknown, opts: Parameters<typeof verifyEntitlement>[1] = {}) =>
  verifyEntitlement(jws, { trustedRoot: testRoot, ...opts });

function quiet<T>(fn: () => Promise<T>): Promise<T> {
  const orig = console.error;
  console.error = () => {};
  return fn().finally(() => { console.error = orig; });
}

describe("racine Apple embarquée", () => {
  test("correspond à l'empreinte SHA-256 publiée d'Apple Root CA - G3", () => {
    const root = appleRootCertificate();
    assert.equal(root.fingerprint256.replace(/:/g, ""), APPLE_ROOT_CA_G3_SHA256);
    assert.match(root.subject, /CN=Apple Root CA - G3/);
    assert.ok(root.ca);
    assert.ok(Date.parse(root.validTo) > Date.parse("2039-01-01"));
  });

  test("une chaîne de test est rejetée avec la vraie racine Apple (untrusted_root)", async () => {
    const res = await verifyEntitlement(makeJWS(transaction()));
    assert.deepEqual(res, { ok: false, reason: "untrusted_root" });
  });
});

describe("format", () => {
  test("absent, vide, mauvais type → missing", async () => {
    for (const v of [undefined, null, "", 42, {}, ["a.b.c"]]) {
      assert.deepEqual(await verify(v), { ok: false, reason: "missing" });
    }
  });

  test("pas 3 segments ou segment vide → missing", async () => {
    for (const v of ["a.b", "a.b.c.d", "a..c", ".b.c"]) {
      assert.deepEqual(await verify(v), { ok: false, reason: "missing" });
    }
  });

  test("JWS démesuré (> 20 000 caractères) → missing, sans décodage", async () => {
    assert.deepEqual(await verify(`${"a".repeat(10_000)}.${"b".repeat(10_000)}.c`), { ok: false, reason: "missing" });
  });

  test("en-tête sans x5c Apple → bad_header", async () => {
    assert.deepEqual(await verify(`${b64url({ alg: "ES256" })}.${b64url({ productId: "x" })}.sig`), { ok: false, reason: "bad_header" });
  });

  test("alg différent de ES256 (dont none) → bad_header", async () => {
    for (const alg of ["none", "HS256", "RS256"]) {
      const h = b64url({ alg, x5c: [TEST_LEAF_B64, TEST_INTERMEDIATE_B64, TEST_ROOT_B64] });
      assert.deepEqual(await verify(`${h}.${b64url(transaction())}.sig`), { ok: false, reason: "bad_header" });
    }
  });

  test("x5c de longueur ≠ 3 ou non-chaînes → bad_header", async () => {
    for (const x5c of [[TEST_LEAF_B64, TEST_ROOT_B64], [TEST_LEAF_B64, TEST_INTERMEDIATE_B64, TEST_ROOT_B64, TEST_ROOT_B64], [1, 2, 3]]) {
      const h = b64url({ alg: "ES256", x5c });
      assert.deepEqual(await verify(`${h}.${b64url(transaction())}.sig`), { ok: false, reason: "bad_header" });
    }
  });

  test("en-tête non-JSON ou certificats corrompus → invalid", async () => {
    await quiet(async () => {
      assert.deepEqual(await verify("%%%.e30.sig"), { ok: false, reason: "invalid" });
      const h = b64url({ alg: "ES256", x5c: ["AAAA", "AAAA", "AAAA"] });
      assert.deepEqual(await verify(`${h}.e30.sig`), { ok: false, reason: "invalid" });
    });
  });
});

describe("chaîne et signature", () => {
  test("transaction valide (Production) → ok avec originalTransactionId", async () => {
    assert.deepEqual(await verify(makeJWS(transaction())), {
      ok: true, productId: "com.mandaloregroup.spog.premium.yearly", environment: "Production", originalTransactionId: "2000000123",
    });
  });

  test("formule mensuelle acceptée", async () => {
    const res = await verify(makeJWS(transaction({ productId: "com.mandaloregroup.spog.premium.monthly" })));
    assert.equal(res.ok, true);
  });

  test("racine fournie ≠ racine de confiance → untrusted_root", async () => {
    const res = await verify(makeJWS(transaction(), { x5c: [TEST_LEAF_B64, TEST_INTERMEDIATE_B64, TEST_INTERMEDIATE_B64] }));
    assert.deepEqual(res, { ok: false, reason: "untrusted_root" });
  });

  test("maillons inversés → bad_chain", async () => {
    const res = await verify(makeJWS(transaction(), { x5c: [TEST_INTERMEDIATE_B64, TEST_LEAF_B64, TEST_ROOT_B64], key: TEST_INTERMEDIATE_KEY }));
    assert.deepEqual(res, { ok: false, reason: "bad_chain" });
  });

  test("certificats hors période de validité → bad_chain", async () => {
    assert.deepEqual(await verify(makeJWS(transaction()), { now: Date.parse("2200-01-01") }), { ok: false, reason: "bad_chain" });
    assert.deepEqual(await verify(makeJWS(transaction()), { now: Date.parse("2000-01-01") }), { ok: false, reason: "bad_chain" });
  });

  test("feuille valide sous la racine mais sans l'OID StoreKit → not_storekit", async () => {
    // Le cas d'attaque : un certificat légitimement émis sous la racine Apple
    // (ex. certificat de développeur) mais qui n'est pas un certificat StoreKit.
    const res = await verify(makeJWS(transaction(), { x5c: [TEST_ROGUE_LEAF_B64, TEST_INTERMEDIATE_B64, TEST_ROOT_B64], key: TEST_ROGUE_KEY }));
    assert.deepEqual(res, { ok: false, reason: "not_storekit" });
  });

  test("signature par une autre clé que la feuille → bad_signature", async () => {
    const res = await verify(makeJWS(transaction(), { key: TEST_ROGUE_KEY }));
    assert.deepEqual(res, { ok: false, reason: "bad_signature" });
  });

  test("payload modifié après signature → bad_signature", async () => {
    const [h, , s] = makeJWS(transaction()).split(".");
    const forged = `${h}.${b64url(transaction({ productId: "com.mandaloregroup.spog.premium.yearly", expiresDate: NOW + 9999 * DAY }))}.${s}`;
    assert.deepEqual(await verify(forged), { ok: false, reason: "bad_signature" });
  });
});

describe("contenu de la transaction", () => {
  test("autre bundle → bundle", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ bundleId: "com.evil.app" }))), { ok: false, reason: "bundle" });
  });

  test("produit inconnu ou absent → product", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ productId: "com.mandaloregroup.spog.tip" }))), { ok: false, reason: "product" });
    assert.deepEqual(await verify(makeJWS(transaction({ productId: undefined }))), { ok: false, reason: "product" });
  });

  test("révoquée (remboursement) → revoked", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ revocationDate: NOW - DAY, revocationReason: 0 }))), { ok: false, reason: "revoked" });
  });

  test("expirée au-delà de la tolérance de 10 min → expired", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ expiresDate: NOW - 11 * 60_000 }))), { ok: false, reason: "expired" });
  });

  test("expirée depuis moins de 10 min → acceptée (renouvellement en cours)", async () => {
    assert.equal((await verify(makeJWS(transaction({ expiresDate: NOW - 5 * 60_000 })))).ok, true);
  });

  test("expiresDate absent ou non numérique → expired", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ expiresDate: undefined }))), { ok: false, reason: "expired" });
    assert.deepEqual(await verify(makeJWS(transaction({ expiresDate: String(NOW + DAY) }))), { ok: false, reason: "expired" });
  });

  test("Sandbox acceptée par défaut (TestFlight, revue Apple)", async () => {
    const res = await verify(makeJWS(transaction({ environment: "Sandbox" })));
    assert.equal(res.ok, true);
    assert.equal(res.ok && res.environment, "Sandbox");
  });

  test("Sandbox refusée si allowSandbox=false", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ environment: "Sandbox" })), { allowSandbox: false }), { ok: false, reason: "environment" });
    assert.equal((await verify(makeJWS(transaction()), { allowSandbox: false })).ok, true);
  });

  test("environnement Xcode ou absent → environment", async () => {
    assert.deepEqual(await verify(makeJWS(transaction({ environment: "Xcode" }))), { ok: false, reason: "environment" });
    assert.deepEqual(await verify(makeJWS(transaction({ environment: undefined }))), { ok: false, reason: "environment" });
  });

  test("payload JSON non-objet → invalid", async () => {
    await quiet(async () => {
      assert.deepEqual(await verify(makeJWS("[]")), { ok: false, reason: "invalid" });
    });
  });
});
