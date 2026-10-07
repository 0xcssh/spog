import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createHandler, hashKey, clientIPFrom, deviceIdFrom, COLORS, BODIES, MAX_IMAGE_BASE64,
  type HandlerDeps, type Queryable,
} from "./handler";

// ---------- Doublures ----------

function fakeDb(decide: (key: unknown) => boolean | "throw" = () => true) {
  const keys: unknown[] = [];
  const db: Queryable = {
    async query(_text, values = []) {
      keys.push(values[0]);
      const d = decide(values[0]);
      if (d === "throw") throw new Error("connection timeout");
      return { rows: [{ result: { allowed: d } }] };
    },
  };
  return { db, keys };
}

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
    sleep: async () => {},
    ...over,
  });
}

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://fn.test/identify", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-device-id": "device-1", "x-forwarded-for": "1.2.3.4", ...headers },
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
    assert.deepEqual(await res.json(), { ...goodCar });
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
