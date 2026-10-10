// Rendus studio des modèles : tout le catalogue, une seule fois par modèle, jamais sans
// cache, et jamais plus que le plafond global du jour.
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createHandler, hashKey, ART_GLOBAL_DAY_LIMIT, type HandlerDeps, type Queryable } from "./handler";
import type { ArtStore } from "./storage";
import { weeklyBounties, currentWeek } from "./bounty";
import { vehicles } from "./catalog";
import { artKey, artPrompt, paintFor, allowedArtVehicle, ART_PAINTS, ART_ESTIMATED_USAGE } from "./art";
import { developCost } from "./develop";

const NOW = new Date("2026-10-07T12:00:00Z");
// Une cible de la semaine, et surtout un modèle qui n'en est pas une : depuis le passage au
// format carré, tout le catalogue a droit à son rendu, pas seulement le pack.
const TARGET = weeklyBounties(currentWeek(NOW), "FR")[0].vehicle.id;
const ANY_MODEL = vehicles[vehicles.length - 1].id;

/// Base factice : seuls les quotas anti-abus passent par elle ici. `globalAllowed` règle
/// à part le plafond global des générations, reconnu à l'empreinte de sa clé.
function fakeDb(allowed: boolean | "throw" = true, globalAllowed: boolean | "throw" = true) {
  const keys: unknown[] = [];
  const global = hashKey("art-global");
  const db: Queryable = {
    async query(_text, values = []) {
      keys.push(values[0]);
      const verdict = values[0] === global ? globalAllowed : allowed;
      if (verdict === "throw") throw new Error("connection timeout");
      return { rows: [{ result: { allowed: verdict } }] };
    },
  };
  return { db, keys, globalChecks: () => keys.filter((k) => k === global).length };
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
function imageResponse(withUsage = true): Response {
  return new Response(JSON.stringify({
    data: [{ b64_json: jpeg }],
    ...(withUsage ? { usage: { input_tokens: 300, output_tokens: 4160, input_tokens_details: { text_tokens: 300, image_tokens: 0 } } } : {}),
  }), { status: 200, headers: { "Content-Type": "application/json" } });
}

function spyFetch(responses: Array<Response | Error> = [imageResponse()]) {
  const calls: { url: string; body: any }[] = [];
  const fn = (async (url: unknown, init: RequestInit) => {
    // Formulaire multipart (édition de la plaque) : champs texte, et le nom du fichier joint.
    const raw = init.body;
    const body: Record<string, unknown> = {};
    if (raw instanceof FormData) {
      raw.forEach((value, key) => { body[key] = typeof value === "string" ? value : (value as File).name; });
    } else Object.assign(body, JSON.parse(String(raw)));
    calls.push({ url: String(url), body });
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
  test("un modèle est généré une fois, puis servi depuis le cache", async () => {
    const art = fakeArt();
    const ai = spyFetch();
    const h = handler({ art: art.store, fetch: ai.fn });
    const first = await h(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(first.status, 200);
    assert.deepEqual(await first.json(), { image: jpeg, cached: false });
    assert.ok(art.objects[`vehicles/v5/${TARGET}.jpg`]);

    const second = await h(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.deepEqual(await second.json(), { image: jpeg, cached: true });
    assert.equal(ai.calls.length, 1);
  });

  test("n'importe quel modèle du catalogue est accepté, pas seulement les cibles", async () => {
    const ai = spyFetch();
    const res = await handler({ fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: ANY_MODEL }));
    assert.equal(res.status, 200);
    assert.equal(ai.calls.length, 1);
  });

  test("la requête OpenAI suit le contrat retenu : édition de la plaque, carré, haute qualité", async () => {
    const ai = spyFetch();
    await handler({ fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(ai.calls[0].url, "https://api.openai.com/v1/images/edits");
    const body = ai.calls[0].body;
    assert.equal(body.model, "gpt-image-1-mini");
    assert.equal(body.quality, "high");
    assert.equal(body.size, "1024x1024");
    assert.equal(body.output_format, "jpeg");
    assert.equal(body.output_compression, "90");
    assert.equal(body.n, "1");
    assert.equal(body.image, "studio.png");
    assert.match(body.prompt, /FACES LEFT/);
    assert.match(body.prompt, /WIDE SHOT/);
    assert.match(body.prompt, /no licence plate/i);
  });

  test("les anciens bandeaux en cache ne sont plus resservis", async () => {
    const art = fakeArt({ [`vehicles/${TARGET}.jpg`]: Buffer.from("old-banner") });
    const ai = spyFetch();
    const res = await handler({ art: art.store, fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.deepEqual(await res.json(), { image: jpeg, cached: false });
    assert.equal(ai.calls.length, 1);
  });

  test("un identifiant hors catalogue est refusé, sans toucher au stockage ni à OpenAI", async () => {
    const art = fakeArt();
    const ai = spyFetch();
    const h = handler({ art: art.store, fetch: ai.fn });
    for (const id of ["../../etc/passwd", "renault-clio-inventee", "vehicles/v2/x"]) {
      const res = await h(post({ action: "vehicle_art", vehicle_id: id }));
      assert.equal(res.status, 403);
      assert.equal((await res.json() as any).code, "unknown_vehicle");
    }
    assert.equal((await h(post({ action: "vehicle_art" }))).status, 400);
    assert.equal(ai.calls.length, 0);
    assert.equal(art.gets.length, 0);
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

  test("une réponse sans usage reste servie (le coût est alors estimé)", async () => {
    const ai = spyFetch([imageResponse(false)]);
    const res = await handler({ fetch: ai.fn })(post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 200);
  });

  test("deux demandes simultanées du même modèle ne paient qu'un rendu, et n'entament le plafond qu'une fois", async () => {
    const ai = spyFetch();
    const quotas = fakeDb();
    const h = handler({ fetch: ai.fn, db: quotas.db });
    const [a, b] = await Promise.all([
      h(post({ action: "vehicle_art", vehicle_id: TARGET })),
      h(post({ action: "vehicle_art", vehicle_id: TARGET })),
    ]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    assert.equal(ai.calls.length, 1);
    assert.equal(quotas.globalChecks(), 1);
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

  test("le plafond global atteint bloque les générations, fail-closed", async () => {
    const ai = spyFetch();
    const blocked = await handler({ db: fakeDb(true, false).db, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(blocked.status, 429);
    assert.equal((await blocked.json() as any).code, "rate_limited");
    const down = await handler({ db: fakeDb(true, "throw").db, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(down.status, 503);
    assert.equal(ai.calls.length, 0);
  });

  test("une demande servie par le cache ne compte pas dans le plafond global", async () => {
    const ai = spyFetch();
    const quotas = fakeDb(true, false);
    const art = fakeArt({ [artKey(TARGET)]: Buffer.from("fake-jpeg") });
    const res = await handler({ db: quotas.db, art: art.store, fetch: ai.fn })(
      post({ action: "vehicle_art", vehicle_id: TARGET }));
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { image: jpeg, cached: true });
    assert.equal(quotas.globalChecks(), 0);
    assert.equal(ai.calls.length, 0);
  });
});

describe("gabarit des rendus", () => {
  test("la clé de cache est rangée sous vehicles/v5/", () => {
    assert.equal(artKey("renault-clio"), "vehicles/v5/renault-clio.jpg");
  });

  test("le prompt interdit les emblèmes d'entrée, et laisse de la marge autour de la voiture", () => {
    const prompt = artPrompt({ id: "renault-clio", make: "Renault", model: "Clio", body: "hatch" });
    assert.ok(prompt.startsWith("IMPORTANT — NO EMBLEMS"));
    assert.match(prompt, /at least 15% of the image\s+width/);
  });

  test("la teinte est stable pour un modèle et varie d'un modèle à l'autre", () => {
    assert.equal(paintFor("renault-clio"), paintFor("renault-clio"));
    const paints = new Set(vehicles.slice(0, 60).map((v) => paintFor(v.id)));
    assert.ok(paints.size >= ART_PAINTS.length / 2);
  });

  test("le prompt nomme le modèle, le cadre au centre, et ne demande ni logo ni texte", () => {
    const prompt = artPrompt({ id: "renault-clio", make: "Renault", model: "Clio", body: "hatch" });
    assert.match(prompt, /Renault Clio, compact hatchback/);
    assert.match(prompt, /perfectly centred/);
    assert.match(prompt, /No text, no badges, no logos/);
  });

  test("la voiture est posée dans la plaque du studio, sans néons, pneus au sol", () => {
    const prompt = artPrompt({ id: "renault-clio", make: "Renault", model: "Clio", body: "hatch" });
    assert.match(prompt, /INSIDE THE PROVIDED STUDIO IMAGE/);
    assert.match(prompt, /no neon/);
    assert.match(prompt, /tyres rest firmly ON the floor/);
    assert.doesNotMatch(prompt, /violet|cyan|reflective/i);
  });

  test("tout le catalogue est autorisé, rien d'autre", () => {
    for (const v of vehicles) assert.ok(allowedArtVehicle(v.id));
    assert.equal(allowedArtVehicle(""), undefined);
    assert.equal(allowedArtVehicle("constructor"), undefined);
  });

  test("le coût estimé d'un rendu reste sous 4 centimes, et le pire jour sous 12 $", () => {
    const cost = developCost("gpt-image-1-mini", ART_ESTIMATED_USAGE)!;
    assert.ok(cost > 0.02 && cost < 0.04, `coût estimé ${cost}`);
    assert.ok(cost * ART_GLOBAL_DAY_LIMIT < 12);
  });
});
