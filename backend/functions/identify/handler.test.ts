import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createHandler, hashKey, clientIPFrom, deviceIdFrom, installIdFrom, COLORS, BODIES, MAX_IMAGE_BASE64,
  FREE_SCANS, type HandlerDeps, type Queryable,
} from "./handler";
import type { EntitlementResult } from "./entitlement";

// ---------- Doublures ----------

/// Base factice : quotas décidés par `decide`, scans offerts tenus en mémoire.
function fakeDb(decide: (key: unknown) => boolean | "throw" = () => true, freeUsed: Record<string, number> = {}) {
  const keys: unknown[] = [];
  let consumed = 0;
  const db: Queryable = {
    async query(text, values = []) {
      keys.push(values[0]);
      const key = String(values[0]);
      if (text.includes("from public.free_scans")) {
        if (decide("free-scans") === "throw") throw new Error("connection timeout");
        return { rows: key in freeUsed ? [{ used: freeUsed[key] }] : [] };
      }
      if (text.includes("consume_free_scan")) {
        consumed++;
        freeUsed[key] = (freeUsed[key] ?? 0) + 1;
        return { rows: [{ used: freeUsed[key] }] };
      }
      const d = decide(values[0]);
      if (d === "throw") throw new Error("connection timeout");
      return { rows: [{ result: { allowed: d } }] };
    },
  };
  return { db, keys, freeUsed, consumed: () => consumed };
}

const noSubscription = async (): Promise<EntitlementResult> => ({ ok: false, reason: "missing" });
const activeSubscription = async (): Promise<EntitlementResult> =>
  ({ ok: true, productId: "com.mandaloregroup.spog.premium.yearly", environment: "Production", originalTransactionId: "2000000999" });

function aiResponse(content: unknown, status = 200): Response {
  return new Response(JSON.stringify({
    choices: [{ message: { content: typeof content === "string" ? content : JSON.stringify(content) } }],
    usage: { prompt_tokens: 1000, completion_tokens: 50 },
  }), { status, headers: { "Content-Type": "application/json" } });
}

function fakeFetch(responses: Array<Response | Error>) {
  let calls = 0;
  const fn = (async () => {
    const next = responses[Math.min(calls++, responses.length - 1)];
    if (next instanceof Error) throw next;
    return next.clone();
  }) as unknown as typeof fetch;
  return { fn, count: () => calls };
}

function handler(over: Partial<HandlerDeps> = {}) {
  return createHandler({
    openaiKey: "sk-test",
    db: fakeDb().db,
    fetch: fakeFetch([aiResponse(goodCar)]).fn,
    verifyEntitlement: noSubscription,
    sleep: async () => {},
    ...over,
  });
}

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://fn.test/identify", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-device-id": "device-1", "x-install-id": "install-1", "x-forwarded-for": "1.2.3.4", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const goodCar = {
  vehicle_present: true, is_screen: false, make: "Peugeot", model: "3008", generation: "II",
  body: "suv", color: "grey", confidence: 0.92,
};

// ---------- Tests ----------

describe("contrat de réponse", () => {
  test("une photo reconnue renvoie les champs attendus par l'app", async () => {
    const res = await handler()(post({ imageBase64: "abc" }));
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ...goodCar, free_scans_left: FREE_SCANS - 1 });
  });

  test("couleur et carrosserie hors liste sont neutralisées", async () => {
    const res = await handler({
      fetch: fakeFetch([aiResponse({ ...goodCar, color: "Matte Zebra", body: "limousine" })]).fn,
    })(post({ imageBase64: "abc" }));
    const out = await res.json() as any;
    assert.equal(out.color, "");
    assert.equal(out.body, "sedan");
  });

  test("la confiance est bornée entre 0 et 1", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse({ ...goodCar, confidence: 7 })]).fn })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).confidence, 1);
  });

  test("une réponse IA illisible donne un code stable", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse("pas du json")]).fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 502);
    assert.equal((await res.json() as any).code, "unreadable_ai_response");
  });

  // L'app épingle ces deux listes dans ServerContractTests : si l'une bouge ici,
  // ce test casse pour rappeler de reporter le changement côté Swift.
  test("listes fermées inchangées", () => {
    assert.deepEqual(BODIES, ["hatch", "sedan", "suv", "sport", "pickup", "van"]);
    assert.equal(COLORS.length, 14);
  });
});

describe("entrées refusées", () => {
  test("photo manquante", async () => {
    const res = await handler()(post({}));
    assert.equal((await res.json() as any).code, "missing_input");
  });

  test("photo trop lourde", async () => {
    const res = await handler()(post({ imageBase64: "a".repeat(MAX_IMAGE_BASE64 + 1) }));
    assert.equal(res.status, 413);
  });

  test("corps illisible", async () => {
    const res = await handler()(post("{pas du json"));
    assert.equal((await res.json() as any).code, "bad_request");
  });

  test("GET refusé", async () => {
    const res = await handler()(new Request("https://fn.test/identify"));
    assert.equal(res.status, 405);
  });
});

describe("quotas", () => {
  test("base injoignable : refus, jamais d'appel OpenAI", async () => {
    const ai = fakeFetch([aiResponse(goodCar)]);
    const res = await handler({ db: fakeDb(() => "throw").db, fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 503);
    assert.equal(ai.count(), 0);
  });

  test("pas de base configurée : refus", async () => {
    const res = await handler({ db: null })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 503);
  });

  test("plafond global : service_saturated, pas rate_limited", async () => {
    const globalKey = hashKey("global");
    const res = await handler({ db: fakeDb((k) => k !== globalKey).db })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).code, "service_saturated");
  });

  test("quota appareil dépassé : rate_limited", async () => {
    const deviceKey = hashKey("device:device-1");
    const res = await handler({ db: fakeDb((k) => k !== deviceKey).db })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 429);
  });

  test("les clés stockées sont des empreintes, jamais l'ID ou l'IP", async () => {
    const { db, keys } = fakeDb();
    await handler({ db })(post({ imageBase64: "abc" }));
    for (const key of keys) {
      assert.match(String(key), /^[0-9a-f]{64}$/);
      assert.ok(!String(key).includes("device-1") && !String(key).includes("1.2.3.4"));
    }
  });

  test("sans x-device-id, l'appareil est compté par son IP", () => {
    const headers = new Headers({ "x-forwarded-for": "5.6.7.8, 10.0.0.1" });
    const ip = clientIPFrom(headers);
    assert.equal(ip, "5.6.7.8");
    assert.equal(deviceIdFrom(headers, ip), "5.6.7.8");
  });
});

describe("OpenAI", () => {
  test("une panne passagère est réessayée", async () => {
    const ai = fakeFetch([new Response("busy", { status: 503 }), aiResponse(goodCar)]);
    const res = await handler({ fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 200);
    assert.equal(ai.count(), 2);
  });

  test("compte sans provision : 503 neutre, sans nouvelle tentative", async () => {
    const ai = fakeFetch([new Response('{"error":{"code":"insufficient_quota"}}', { status: 401 })]);
    const res = await handler({ fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 503);
    assert.equal((await res.json() as any).code, "server_misconfigured");
    assert.equal(ai.count(), 1);
  });

  test("clé absente côté serveur", async () => {
    const res = await handler({ openaiKey: undefined })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).code, "server_misconfigured");
  });
});

describe("scans offerts et abonnement", () => {
  const installKey = hashKey("install-1");

  test("chaque vraie prise consomme un scan offert", async () => {
    const store = fakeDb(() => true, { [installKey]: 2 });
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).free_scans_left, FREE_SCANS - 3);
    assert.equal(store.freeUsed[installKey], 3);
  });

  test("scans épuisés : 402 paywall_required, sans appel OpenAI", async () => {
    const ai = fakeFetch([aiResponse(goodCar)]);
    const store = fakeDb(() => true, { [installKey]: FREE_SCANS });
    const res = await handler({ db: store.db, fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 402);
    assert.deepEqual(await res.json(), { code: "paywall_required", error: "Les scans offerts sont épuisés.", free_scans_left: 0 });
    assert.equal(ai.count(), 0);
  });

  test("une photo sans voiture ne coûte pas de scan offert", async () => {
    const store = fakeDb(() => true, { [installKey]: 1 });
    const empty = { ...goodCar, vehicle_present: false, make: "", model: "", confidence: 0 };
    const res = await handler({ db: store.db, fetch: fakeFetch([aiResponse(empty)]).fn })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).free_scans_left, FREE_SCANS - 1);
    assert.equal(store.consumed(), 0);
  });

  test("une photo d'écran ne coûte pas de scan offert", async () => {
    const store = fakeDb();
    const screen = { ...goodCar, is_screen: true };
    await handler({ db: store.db, fetch: fakeFetch([aiResponse(screen)]).fn })(post({ imageBase64: "abc" }));
    assert.equal(store.consumed(), 0);
  });

  test("abonné : pas de plafond de scans offerts, free_scans_left nul", async () => {
    const store = fakeDb(() => true, { [installKey]: 99 });
    const res = await handler({ db: store.db, verifyEntitlement: activeSubscription })(
      post({ imageBase64: "abc", entitlement: "jws" }));
    assert.equal(res.status, 200);
    assert.equal((await res.json() as any).free_scans_left, null);
    assert.equal(store.consumed(), 0);
  });

  test("abonné : quota par transaction d'origine", async () => {
    const subKey = hashKey("sub:2000000999");
    const store = fakeDb((k) => k !== subKey);
    const res = await handler({ db: store.db, verifyEntitlement: activeSubscription })(
      post({ imageBase64: "abc", entitlement: "jws" }));
    assert.equal(res.status, 429);
  });

  test("transaction invalide : retour aux scans offerts", async () => {
    const store = fakeDb(() => true, { [installKey]: FREE_SCANS });
    const res = await handler({ db: store.db })(post({ imageBase64: "abc", entitlement: "forged" }));
    assert.equal(res.status, 402);
  });

  test("base des scans offerts injoignable : refus", async () => {
    const store = fakeDb((k) => (k === "free-scans" ? "throw" : true));
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 503);
  });

  test("plafond de scans offerts par IP", async () => {
    const freeIPKey = hashKey("free-ip:1.2.3.4");
    const store = fakeDb((k) => k !== freeIPKey);
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 429);
  });

  test("sans x-install-id (ancienne app), l'installation est l'appareil", () => {
    assert.equal(installIdFrom(new Headers(), "device-1"), "device-1");
    assert.equal(installIdFrom(new Headers({ "x-install-id": " abc " }), "device-1"), "abc");
  });
});
