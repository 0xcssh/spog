import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createHandler, hashKey, clientIPFrom, deviceIdFrom, installIdFrom, COLORS, BODIES, MAX_IMAGE_BASE64,
  FREE_ALLOWANCE, PRO_DAILY_DEVELOPS, nextResetAt, type HandlerDeps, type Queryable,
} from "./handler";
import type { EntitlementResult } from "./entitlement";
import type { SampleStore } from "./storage";

// ---------- Doublures ----------

/// Base factice : quotas anti-abus décidés par `decide`, quotas du jour tenus en mémoire
/// (`freeUsed` : scans du jour par empreinte d'installation ; `<empreinte>:develop` pour
/// les rendus). `firstDay` : l'installation en est-elle à son premier jour ?
function fakeDb(decide: (key: unknown) => boolean | "throw" = () => true, freeUsed: Record<string, number> = {},
                sampleKeys: string[] = [], firstDay = true) {
  const keys: unknown[] = [];
  const queries: { text: string; values: unknown[] }[] = [];
  let consumed = 0;
  const db: Queryable = {
    async query(text, values = []) {
      queries.push({ text, values });
      if (text.includes("public.scans")) return { rows: [] };
      if (text.includes("training_samples")) {
        if (decide("training") === "throw") throw new Error("connection timeout");
        if (text.includes("select object_key")) return { rows: sampleKeys.map((object_key) => ({ object_key })) };
        return { rows: [] };
      }
      keys.push(values[0]);
      const key = String(values[0]);
      const slot = values[1] === "develop" ? `${key}:develop` : key;
      if (text.includes("allowance_left")) {
        if (decide("allowance") === "throw") throw new Error("connection timeout");
        const limit = Number(firstDay ? values[2] : values[3]);
        return { rows: [{ left: Math.max(0, limit - (freeUsed[slot] ?? 0)) }] };
      }
      if (text.includes("consume_allowance")) {
        consumed++;
        freeUsed[slot] = (freeUsed[slot] ?? 0) + 1;
        return { rows: [{ used: freeUsed[slot] }] };
      }
      const d = decide(values[0]);
      if (d === "throw") throw new Error("connection timeout");
      return { rows: [{ result: { allowed: d } }] };
    },
  };
  return { db, keys, queries, freeUsed, consumed: () => consumed };
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
    const { scan_id, ...rest } = await res.json() as any;
    // Sans pays (app d'avant la cote), les champs de la cote existent mais n'affirment rien.
    assert.deepEqual(rest, { ...goodCar, price_min: 0, price_max: 0, price_currency: "",
                             scans_left: FREE_ALLOWANCE.firstDayScans - 1, resets_at: nextResetAt() });
    assert.match(scan_id, /^[0-9a-f-]{36}$/);
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

describe("quotas du jour et abonnement", () => {
  const installKey = hashKey("install-1");

  test("premier jour : dix scans, chaque vraie prise en consomme un", async () => {
    const store = fakeDb(() => true, { [installKey]: 2 });
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).scans_left, FREE_ALLOWANCE.firstDayScans - 3);
    assert.equal(store.freeUsed[installKey], 3);
  });

  test("les jours suivants : trois scans", async () => {
    const store = fakeDb(() => true, { [installKey]: 1 }, [], false);
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).scans_left, FREE_ALLOWANCE.dailyScans - 2);
  });

  test("scans du jour épuisés : 402 daily_limit avec l'heure de remise à zéro, sans appel OpenAI", async () => {
    const ai = fakeFetch([aiResponse(goodCar)]);
    const store = fakeDb(() => true, { [installKey]: FREE_ALLOWANCE.dailyScans }, [], false);
    const res = await handler({ db: store.db, fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 402);
    const out = await res.json() as any;
    assert.equal(out.code, "daily_limit");
    assert.equal(out.scans_left, 0);
    assert.equal(out.resets_at, nextResetAt());
    assert.equal(ai.count(), 0);
  });

  test("la remise à zéro tombe à minuit UTC", () => {
    assert.equal(nextResetAt(new Date("2026-10-08T23:59:00Z")), "2026-10-09T00:00:00.000Z");
  });

  test("une photo sans voiture ne coûte pas de scan", async () => {
    const store = fakeDb(() => true, { [installKey]: 1 });
    const empty = { ...goodCar, vehicle_present: false, make: "", model: "", confidence: 0 };
    const res = await handler({ db: store.db, fetch: fakeFetch([aiResponse(empty)]).fn })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).scans_left, FREE_ALLOWANCE.firstDayScans - 1);
    assert.equal(store.consumed(), 0);
  });

  test("une photo d'écran ne coûte pas de scan", async () => {
    const store = fakeDb();
    const screen = { ...goodCar, is_screen: true };
    await handler({ db: store.db, fetch: fakeFetch([aiResponse(screen)]).fn })(post({ imageBase64: "abc" }));
    assert.equal(store.consumed(), 0);
  });

  test("abonné : pas de quota du jour, scans_left nul", async () => {
    const store = fakeDb(() => true, { [installKey]: 99 }, [], false);
    const res = await handler({ db: store.db, verifyEntitlement: activeSubscription })(
      post({ imageBase64: "abc", entitlement: "jws" }));
    assert.equal(res.status, 200);
    const out = await res.json() as any;
    assert.equal(out.scans_left, null);
    assert.equal(out.resets_at, undefined);
    assert.equal(store.consumed(), 0);
  });

  test("abonné : quota anti-abus par transaction d'origine", async () => {
    const subKey = hashKey("sub:2000000999");
    const store = fakeDb((k) => k !== subKey);
    const res = await handler({ db: store.db, verifyEntitlement: activeSubscription })(
      post({ imageBase64: "abc", entitlement: "jws" }));
    assert.equal(res.status, 429);
  });

  test("transaction invalide : retour aux quotas gratuits", async () => {
    const store = fakeDb(() => true, { [installKey]: 3 }, [], false);
    const res = await handler({ db: store.db })(post({ imageBase64: "abc", entitlement: "forged" }));
    assert.equal(res.status, 402);
  });

  test("base des quotas injoignable : refus", async () => {
    const store = fakeDb((k) => (k === "allowance" ? "throw" : true));
    const res = await handler({ db: store.db })(post({ imageBase64: "abc" }));
    assert.equal(res.status, 503);
  });

  test("plafond de scans gratuits par IP", async () => {
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

function fakeSamples(fail = false) {
  const put: string[] = [];
  const removed: string[] = [];
  const store: SampleStore = {
    async put(key) { if (fail) throw new Error("s3 down"); put.push(key); },
    async remove(keys) { removed.push(...keys); },
  };
  return { store, put, removed };
}

const SAMPLE_ID = "11111111-2222-3333-4444-555555555555";

describe("photos d'entraînement", () => {
  test("sans accord, rien n'est conservé", async () => {
    const samples = fakeSamples();
    const res = await handler({ samples: samples.store })(post({ imageBase64: "abc" }));
    assert.equal((await res.json() as any).sample_id, undefined);
    assert.equal(samples.put.length, 0);
  });

  test("avec accord, la prise est conservée et étiquetée par l'IA", async () => {
    const samples = fakeSamples();
    const store = fakeDb();
    const res = await handler({ db: store.db, samples: samples.store, newId: () => SAMPLE_ID })(
      post({ imageBase64: "abc", training_consent: true }));
    assert.equal((await res.json() as any).sample_id, SAMPLE_ID);
    assert.deepEqual(samples.put, [`samples/${SAMPLE_ID}.jpg`]);
    const insert = store.queries.find((q) => q.text.includes("insert into public.training_samples"));
    assert.ok(insert);
    assert.equal(insert!.values[1], hashKey("install-1"));
    assert.equal(insert!.values[4], "3008");
  });

  test("une photo sans voiture n'est jamais conservée", async () => {
    const samples = fakeSamples();
    const empty = { ...goodCar, vehicle_present: false, model: "" };
    await handler({ samples: samples.store, fetch: fakeFetch([aiResponse(empty)]).fn })(
      post({ imageBase64: "abc", training_consent: true }));
    assert.equal(samples.put.length, 0);
  });

  test("un stockage en panne ne coûte pas sa carte au joueur", async () => {
    const res = await handler({ samples: fakeSamples(true).store })(
      post({ imageBase64: "abc", training_consent: true }));
    assert.equal(res.status, 200);
    assert.equal((await res.json() as any).sample_id, undefined);
  });

  test("étiquette du joueur, limitée à sa propre installation", async () => {
    const store = fakeDb();
    const res = await handler({ db: store.db })(
      post({ action: "label", sample_id: SAMPLE_ID, vehicle_id: "peugeot-3008", source: "corrected" }));
    assert.deepEqual(await res.json(), { ok: true });
    const update = store.queries.find((q) => q.text.includes("update public.training_samples"));
    assert.deepEqual(update!.values, [SAMPLE_ID, hashKey("install-1"), "peugeot-3008", "corrected"]);
  });

  test("étiquette invalide refusée", async () => {
    for (const bad of [
      { action: "label", sample_id: "x", vehicle_id: "a", source: "confirmed" },
      { action: "label", sample_id: SAMPLE_ID, vehicle_id: "", source: "confirmed" },
      { action: "label", sample_id: SAMPLE_ID, vehicle_id: "a", source: "guessed" },
    ]) {
      const res = await handler()(post(bad));
      assert.equal(res.status, 400);
    }
  });

  test("retrait de l'accord : images puis lignes effacées", async () => {
    const samples = fakeSamples();
    const store = fakeDb(() => true, {}, ["samples/a.jpg", "samples/b.jpg"]);
    const res = await handler({ db: store.db, samples: samples.store })(post({ action: "forget" }));
    assert.deepEqual(await res.json(), { deleted: 2 });
    assert.deepEqual(samples.removed, ["samples/a.jpg", "samples/b.jpg"]);
    const del = store.queries.find((q) => q.text.startsWith("delete from public.training_samples"));
    assert.deepEqual(del!.values, [hashKey("install-1")]);
  });

  test("les actions ne passent pas par OpenAI ni par les scans offerts", async () => {
    const ai = fakeFetch([aiResponse(goodCar)]);
    const store = fakeDb();
    await handler({ db: store.db, fetch: ai.fn })(post({ action: "forget" }));
    assert.equal(ai.count(), 0);
    assert.equal(store.consumed(), 0);
  });
});

describe("coût journalisé", () => {
  test("au tarif du modèle réellement appelé", async () => {
    const { costOf } = await import("./handler");
    assert.equal(costOf("gpt-4o", 1_000_000, 0), 2.5);
    assert.equal(costOf("gpt-4.1-mini", 1_000_000, 1_000_000), 2.0);
  });

  test("un modèle inconnu n'emprunte pas le tarif d'un autre", async () => {
    const { costOf } = await import("./handler");
    assert.equal(costOf("gpt-9", 1000, 1000), null);
  });
});

describe("développement", () => {
  const png = Buffer.from("fake-png").toString("base64");
  const imageResponse = () => new Response(JSON.stringify({
    data: [{ b64_json: png }],
    usage: { input_tokens: 1300, output_tokens: 1000, input_tokens_details: { text_tokens: 100, image_tokens: 1200 } },
  }), { status: 200, headers: { "Content-Type": "application/json" } });

  test("gratuit : un rendu par jour, le second refusé sans appel OpenAI", async () => {
    const ai = fakeFetch([imageResponse()]);
    const store = fakeDb();
    const first = await handler({ db: store.db, fetch: ai.fn })(post({ action: "develop", imageBase64: "abc" }));
    assert.equal(first.status, 200);
    assert.equal((await first.json() as any).develops_left, 0);
    const second = await handler({ db: store.db, fetch: ai.fn })(post({ action: "develop", imageBase64: "abc" }));
    assert.equal(second.status, 402);
    assert.equal((await second.json() as any).code, "develop_limit");
    assert.equal(ai.count(), 1);
  });

  test("abonné : plafond anti-abus seulement", async () => {
    const store = fakeDb(() => true, { [`${hashKey("install-1")}:develop`]: 5 });
    const res = await handler({ db: store.db, fetch: fakeFetch([imageResponse()]).fn,
                                verifyEntitlement: activeSubscription })(
      post({ action: "develop", imageBase64: "abc", entitlement: "jws" }));
    assert.equal(res.status, 200);
    assert.equal((await res.json() as any).develops_left, null);
    assert.ok(PRO_DAILY_DEVELOPS > 5);
  });

  test("le rendu est demandé en JPEG", async () => {
    let sent: FormData | null = null;
    const fetchSpy = (async (_url: unknown, init: RequestInit) => { sent = init.body as FormData; return imageResponse(); }) as unknown as typeof fetch;
    await handler({ fetch: fetchSpy })(post({ action: "develop", imageBase64: "abc" }));
    assert.equal(sent!.get("output_format"), "jpeg");
  });

  test("un testeur reçoit le rendu et son coût", async () => {
    const ai = fakeFetch([imageResponse()]);
    const res = await handler({ fetch: ai.fn, developTesters: new Set(["install-1"]) })(
      post({ action: "develop", imageBase64: "abc", model: "gpt-image-1-mini", quality: "low" }));
    const out = await res.json() as any;
    assert.equal(res.status, 200);
    assert.equal(out.image, png);
    assert.equal(out.quality, "low");
    assert.equal(out.cost_usd, (100 * 2 + 1200 * 2.5 + 1000 * 8) / 1_000_000);
  });

  test("une erreur OpenAI n'est jamais rejouée", async () => {
    const ai = fakeFetch([new Response("busy", { status: 503 }), imageResponse()]);
    const res = await handler({ fetch: ai.fn, developTesters: new Set(["install-1"]) })(
      post({ action: "develop", imageBase64: "abc" }));
    assert.equal(res.status, 502);
    assert.equal(ai.count(), 1);
  });

  test("un modèle inconnu retombe sur le moins cher", async () => {
    const ai = fakeFetch([imageResponse()]);
    const res = await handler({ fetch: ai.fn, developTesters: new Set(["install-1"]) })(
      post({ action: "develop", imageBase64: "abc", model: "dall-e-9" }));
    assert.equal((await res.json() as any).model, "gpt-image-1-mini");
  });
});

describe("trace des identifications", () => {
  test("une vraie prise laisse le modèle attendu et les propositions", async () => {
    const store = fakeDb();
    await handler({ db: store.db, newId: () => SAMPLE_ID })(post({ imageBase64: "abc" }));
    const insert = store.queries.find((q) => q.text.includes("insert into public.scans"));
    assert.ok(insert);
    assert.equal(insert!.values[2], "peugeot-3008");
    assert.ok((insert!.values[3] as string[]).includes("peugeot-3008"));
  });

  test("une photo sans voiture n'en laisse aucune", async () => {
    const store = fakeDb();
    const empty = { ...goodCar, vehicle_present: false, model: "" };
    await handler({ db: store.db, fetch: fakeFetch([aiResponse(empty)]).fn })(post({ imageBase64: "abc" }));
    assert.equal(store.queries.some((q) => q.text.includes("insert into public.scans")), false);
  });
});

describe("cote d'occasion", () => {
  const pricedCar = { ...goodCar, price_min: 18_000, price_max: 24_000, price_max_usd: 26_000 };

  /// Fetch qui retient le corps envoyé à OpenAI : on vérifie ce que le modèle reçoit.
  function capturingFetch(content: unknown) {
    const bodies: any[] = [];
    const fn = (async (_url: unknown, init?: { body?: unknown }) => {
      bodies.push(JSON.parse(String(init?.body)));
      return aiResponse(content);
    }) as unknown as typeof fetch;
    return { fn, bodies };
  }

  test("avec un pays, la fourchette revient dans la devise de ce pays", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse(pricedCar)]).fn })(post({ imageBase64: "abc", country: "FR" }));
    const out = await res.json() as any;
    assert.equal(out.price_min, 18_000);
    assert.equal(out.price_max, 24_000);
    assert.equal(out.price_currency, "EUR");
    assert.equal(out.price_max_usd, undefined, "l'équivalent en dollars ne sert qu'au contrôle");
  });

  test("le marché et la devise sont dits au modèle, jamais dans le prompt système", async () => {
    const ai = capturingFetch(pricedCar);
    await handler({ fetch: ai.fn })(post({ imageBase64: "abc", country: "jp" }));
    const [system, user] = ai.bodies[0].messages;
    assert.ok(!system.content.includes("JP") && !system.content.includes("JPY"));
    assert.match(user.content[0].text, /country JP, currency JPY/);
  });

  test("sans pays : aucun marché demandé, aucune cote, même si le modèle en invente une", async () => {
    const ai = capturingFetch(pricedCar);
    const res = await handler({ fetch: ai.fn })(post({ imageBase64: "abc" }));
    assert.equal(ai.bodies[0].messages[1].content[0].text, "Identify the car in this photo.");
    const out = await res.json() as any;
    assert.deepEqual([out.price_min, out.price_max, out.price_currency], [0, 0, ""]);
  });

  test("un pays inconnu ou mal formé ne bloque pas l'identification", async () => {
    for (const country of ["ZZ", "FRA", 42, "<script>"]) {
      const res = await handler({ fetch: fakeFetch([aiResponse(pricedCar)]).fn })(post({ imageBase64: "abc", country }));
      assert.equal(res.status, 200);
      const out = await res.json() as any;
      assert.equal(out.model, "3008");
      assert.deepEqual([out.price_min, out.price_max, out.price_currency], [0, 0, ""]);
    }
  });

  test("confiance sous 0,7 : fourchette nulle, devise conservée", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse({ ...pricedCar, confidence: 0.65 })]).fn })(
      post({ imageBase64: "abc", country: "FR" }));
    const out = await res.json() as any;
    assert.deepEqual([out.price_min, out.price_max, out.price_currency], [0, 0, "EUR"]);
  });

  test("une photo d'écran n'a pas de cote", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse({ ...pricedCar, is_screen: true })]).fn })(
      post({ imageBase64: "abc", country: "FR" }));
    const out = await res.json() as any;
    assert.deepEqual([out.price_min, out.price_max], [0, 0]);
  });

  test("les autres champs du contrat ne bougent pas", async () => {
    const res = await handler({ fetch: fakeFetch([aiResponse(pricedCar)]).fn })(post({ imageBase64: "abc", country: "FR" }));
    const { scan_id, price_min, price_max, price_currency, ...rest } = await res.json() as any;
    assert.deepEqual(rest, { ...goodCar, scans_left: FREE_ALLOWANCE.firstDayScans - 1, resets_at: nextResetAt() });
    assert.match(scan_id, /^[0-9a-f-]{36}$/);
  });
});
