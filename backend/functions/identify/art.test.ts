// Visuels des cibles du pack : seules les cibles de la semaine se génèrent, une seule fois
// par modèle, et jamais sans cache.
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createHandler, type HandlerDeps, type Queryable } from "./handler";
import type { ArtStore } from "./storage";
import { weeklyBounties, currentWeek } from "./bounty";
import { vehicles } from "./catalog";
import { artKey, artPrompt, paintFor, weeklyTargetIds, allowedArtVehicle, ART_PAINTS } from "./art";

// Un lundi fixe : le tirage du pack dépend de la semaine.
const NOW = new Date("2026-10-07T12:00:00Z");
const TARGET = weeklyBounties(currentWeek(NOW), "FR")[0].vehicle.id;
const NOT_TARGET = vehicles.find((v) => !weeklyTargetIds(NOW).has(v.id))!.id;

/// Base factice : seuls les quotas anti-abus passent par elle ici.
function fakeDb(allowed: boolean | "throw" = true) {
  const keys: unknown[] = [];
  const db: Queryable = {
    async query(_text, values = []) {
      keys.push(values[0]);
      if (allowed === "throw") throw new Error("connection timeout");
      return { rows: [{ result: { allowed } }] };
    },
  };
  return { db, keys };
}

function fakeArt(initial: Record<string, Buffer> = {}, failGet = false, failPut = false) {
  const objects = { ...initial };
  const gets: string[] = [];
  const store: ArtStore = {
    async get(key) {
      gets.push(key);
      if (failGet) throw new Error("s3 down");
      return objects[key] ?? null;
    },
    async put(key, bytes) {
      if (failPut) throw new Error("s3 down");
      objects[key] = bytes;
    },
  };
  return { store, objects, gets };
}

const jpeg = Buffer.from("fake-jpeg").toString("base64");
function imageResponse(): Response {
  return new Response(JSON.stringify({
    data: [{ b64_json: jpeg }],
    usage: { input_tokens: 100, output_tokens: 1000, input_tokens_details: { text_tokens: 100, image_tokens: 0 } },
  }), { status: 200, headers: { "Content-Type": "application/json" } });
}

function spyFetch(responses: Array<Response | Error> = [imageResponse()]) {
  const calls: { url: string; body: any }[] = [];
  const fn = (async (url: unknown, init: RequestInit) => {
    calls.push({ url: String(url), body: JSON.parse(String(init.body)) });
    const next = responses[Math.min(calls.length - 1, responses.length - 1)];
    if (next instanceof Error) throw next;
    return next.clone();
  }) as unknown as typeof fetch;
  return { fn, calls };
}

function handler(over: Partial<HandlerDeps> = {}) {
  return createHandler({
    openaiKey: "sk-test",
    db: fakeDb().db,
    fetch: spyFetch().fn,
    verifyEntitlement: async () => ({ ok: false, reason: "missing" }),
    sleep: async () => {},
    art: fakeArt().store,
    now: () => NOW,
    ...over,
  });
}

function post(body: unknown) {
  return new Request("https://fn.test/identify", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-device-id": "device-1", "x-install-id": "install-1", "x-forwarded-for": "1.2.3.4" },
    body: JSON.stringify(body),
  });
}

describe("vehicle_art", () => {
  test("une cible de la semaine est générée une fois, puis servie depuis le cache", async () => {
    const art = fakeArt();
    const ai = spyFetch();
    const h = handler({ art: art.store, fetch: ai.fn });
    const first = await h(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(first.status, 200);
    assert.deepEqual(await first.json(), { image: jpeg, cached: false });
    assert.ok(art.objects[`vehicles/${TARGET}.jpg`]);

    const second = await h(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.deepEqual(await second.json(), { image: jpeg, cached: true });
    assert.equal(ai.calls.length, 1);
  });

  test("la requête OpenAI suit le contrat retenu", async () => {
    const ai = spyFetch();
    await handler({ fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(ai.calls[0].url, "https://api.openai.com/v1/images/generations");
    const body = ai.calls[0].body;
    assert.equal(body.model, "gpt-image-1-mini");
    assert.equal(body.quality, "medium");
    assert.equal(body.size, "1536x1024");
    assert.equal(body.output_format, "jpeg");
    assert.equal(body.output_compression, 85);
    assert.match(body.prompt, /FACES LEFT/);
    assert.match(body.prompt, /no licence plate/i);
  });

  test("un modèle qui n'est la cible d'aucun pays est refusé, sans toucher au stockage", async () => {
    const art = fakeArt();
    const ai = spyFetch();
    const res = await handler({ art: art.store, fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: NOT_TARGET }));
    assert.equal(res.status, 403);
    assert.equal((await res.json() as any).code, "not_a_target");
    assert.equal(ai.calls.length, 0);
    assert.equal(art.gets.length, 0);
  });

  test("un identifiant inventé ou absent est refusé", async () => {
    const h = handler();
    assert.equal((await h(post({ action: "vehicle_art", vehicle_id: "../../etc/passwd" }))).status, 403);
    assert.equal((await h(post({ action: "vehicle_art" }))).status, 400);
  });

  test("la cible d'une autre semaine n'est plus acceptée", async () => {
    const later = new Date("2026-10-21T12:00:00Z");
    const ids = weeklyTargetIds(later);
    const stale = [...weeklyTargetIds(NOW)].find((id) => !ids.has(id))!;
    assert.ok(stale);
    assert.equal(allowedArtVehicle(stale, later), undefined);
    assert.ok(allowedArtVehicle(stale, NOW));
  });

  test("sans cache, rien n'est généré", async () => {
    const ai = spyFetch();
    const res = await handler({ art: null, fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 503);
    assert.equal(ai.calls.length, 0);
  });

  test("un stockage en panne ne déclenche pas de génération payante", async () => {
    const ai = spyFetch();
    const res = await handler({ art: fakeArt({}, true).store, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 503);
    assert.equal(ai.calls.length, 0);
  });

  test("un rendu non mis en cache est quand même rendu au joueur", async () => {
    const res = await handler({ art: fakeArt({}, false, true).store })(
      post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 200);
    assert.equal((await res.json() as any).image, jpeg);
  });

  test("une erreur OpenAI n'est jamais rejouée", async () => {
    const ai = spyFetch([new Response("busy", { status: 503 }), imageResponse()]);
    const res = await handler({ fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 502);
    assert.equal(ai.calls.length, 1);
  });

  test("deux demandes simultanées du même modèle ne paient qu'un rendu", async () => {
    const ai = spyFetch();
    const h = handler({ fetch: ai.fn });
    const [a, b] = await Promise.all([
      h(post({ action: "vehicle_art", vehicle_id: TARGET })),
      h(post({ action: "vehicle_art", vehicle_id: TARGET })),
    ]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    assert.equal(ai.calls.length, 1);
  });

  test("le quota de l'appareil s'applique, fail-closed", async () => {
    const ai = spyFetch();
    assert.equal((await handler({ db: fakeDb(false).db, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }))).status, 429);
    assert.equal((await handler({ db: fakeDb("throw").db, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }))).status, 503);
    assert.equal((await handler({ db: null, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }))).status, 503);
    assert.equal(ai.calls.length, 0);
  });
});

describe("gabarit des rendus", () => {
  test("la clé de cache est rangée sous vehicles/", () => {
    assert.equal(artKey("renault-clio"), "vehicles/renault-clio.jpg");
  });

  test("la teinte est stable pour un modèle et varie d'un modèle à l'autre", () => {
    assert.equal(paintFor("renault-clio"), paintFor("renault-clio"));
    const paints = new Set(vehicles.slice(0, 60).map((v) => paintFor(v.id)));
    assert.ok(paints.size >= ART_PAINTS.length / 2);
  });

  test("le prompt nomme le modèle et ne demande ni logo ni texte", () => {
    const prompt = artPrompt({ id: "renault-clio", make: "Renault", model: "Clio", body: "hatch" });
    assert.match(prompt, /Renault Clio, compact hatchback/);
    assert.match(prompt, /No text, no badges, no logos/);
  });

  test("chaque semaine a des cibles, toutes au catalogue", () => {
    const ids = weeklyTargetIds(NOW);
    assert.ok(ids.size >= 3);
    for (const id of ids) assert.ok(allowedArtVehicle(id, NOW));
  });
});
