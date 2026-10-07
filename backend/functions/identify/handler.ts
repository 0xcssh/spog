// Logique de la fonction "identify", sans dépendance à l'environnement :
// index.ts l'instancie avec process.env, la vraie base et le vrai fetch ;
// les tests l'instancient avec des doublures.
//
// Portage de l'ancienne Edge Function Supabase, contrat inchangé pour que l'app
// actuelle n'ait qu'une URL à changer :
//   POST { imageBase64: string }
//   → 200 { make, model, generation, body, color, confidence, is_screen, vehicle_present }
//   → 4xx/5xx { code: string, error: string }
//     `code` est stable et traduit côté app ; `error` n'est qu'un repli lisible.
//
// Le serveur ne connaît NI la rareté, NI les points, NI les règles du jeu :
// tout ça vit dans le catalogue embarqué de l'app, donc modifiable sans redéployer
// et sans supposer un pays. Ici on ne fait que lire une photo.

import { createHash } from "node:crypto";

/** Sous-ensemble de pg.Pool utilisé ici. */
export interface Queryable {
  query(text: string, values?: unknown[]): Promise<{ rows: any[] }>;
}

export interface HandlerDeps {
  openaiKey: string | undefined;
  /** Base des quotas ; null = pas de DATABASE_URL (fail-closed : 503). */
  db: Queryable | null;
  fetch: typeof fetch;
  /** Attente entre deux tentatives OpenAI (remplaçable en test). */
  sleep?: (ms: number) => Promise<void>;
  model?: string;
}

const WINDOW_SECONDS = 60;

// Garde-fous anti-abus : l'URL de la fonction est embarquée dans l'app, donc connue.
// Sans eux, n'importe qui pourrait boucler dessus et faire exploser la facture OpenAI.
// L'en-tête x-device-id vient du client et peut être falsifié : le quota par IP
// rattrape la rotation d'identifiants.
export const DEVICE_DAY_LIMIT = 100;   // par appareil et par jour — personne ne croise 100 voitures
export const DEVICE_WINDOW_LIMIT = 15; // par appareil et par minute

// Les opérateurs mobiles font passer des milliers d'abonnés derrière une seule IP
// publique (CGNAT) : un seuil serré bloquerait des joueurs innocents. Ce quota-là
// ne sert qu'à casser une boucle d'attaque massive.
export const IP_DAY_LIMIT = 20_000;
export const IP_WINDOW_LIMIT = 1_200;

// Plafond de dépense : un compteur unique, partagé par tous. Les deux quotas
// ci-dessus bornent un appareil et une IP, jamais le total.
//
// ⚠️ 5 000/jour est un plafond de PRÉ-LANCEMENT (voir CLAUDE.md, « L'argent »).
// À relever avant la première vraie poussée d'audience, pas après.
export const GLOBAL_DAY_LIMIT = 5_000;
export const GLOBAL_WINDOW_LIMIT = 300;

export const MAX_IMAGE_BASE64 = 8_000_000; // ~6 Mo d'image, au-delà c'est anormal
export const MAX_DEVICE_ID = 128;

export const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
export const DEFAULT_MODEL = "gpt-4o";
const RETRY_DELAYS_MS = [400, 1200]; // 3 tentatives au total

/// Teintes que le modèle a le droit de renvoyer. Liste fermée : l'app doit pouvoir
/// rapprocher la couleur d'une peinture de sa palette sans deviner.
/// ⚠️ Épinglée côté app par ServerContractTests : toute modification se reporte là-bas.
export const COLORS = [
  "white", "black", "silver", "grey", "red", "blue", "dark blue",
  "green", "yellow", "orange", "purple", "teal", "brown", "beige",
];

/// Carrosseries que le modèle a le droit de renvoyer, alignées sur les six
/// géométries que l'app sait dessiner. Même épinglage que COLORS.
export const BODIES = ["hatch", "sedan", "suv", "sport", "pickup", "van"];

/// Tarifs gpt-4o, en dollars par jeton. Ils ne servent qu'à écrire le coût dans les
/// journaux : une valeur périmée fausse la ligne de journal, jamais la facturation.
const PRICE_IN = 2.50 / 1_000_000;
const PRICE_OUT = 10.00 / 1_000_000;

/// Empreinte SHA-256 de la clé de quota : on ne stocke jamais l'ID ni l'IP brute.
export function hashKey(key: string): string {
  return createHash("sha256").update(`spog:${key}`).digest("hex");
}

/// IP du client : premier élément de x-forwarded-for (format « client, proxy1, … »).
export function clientIPFrom(headers: Headers): string {
  const first = (headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  return first ? first.slice(0, 64) : "ip-inconnue";
}

/// Identifiant d'appareil déclaré ; vide ou absent → l'IP (jamais une clé partagée).
export function deviceIdFrom(headers: Headers, clientIP: string): string {
  const raw = (headers.get("x-device-id") ?? "").trim().slice(0, MAX_DEVICE_ID);
  return raw || clientIP;
}

// Identifiants techniques en anglais, jamais affichés tels quels : l'app traduit.
// Aucune règle de jeu ici, et surtout aucune mention de pays — la même réponse
// doit valoir partout.
export const SYSTEM_PROMPT = `You identify a car from a photograph taken in the street. Answer with JSON only.

{
  "vehicle_present": boolean,
  "is_screen": boolean,
  "make": string,
  "model": string,
  "generation": string,
  "body": string,
  "color": string,
  "confidence": number
}

Rules:
- "vehicle_present": false when the photo shows no car at all, or only a part too small to identify.
- "is_screen": true when the photo is not a real car in the real world — a picture of a screen, a monitor, a phone, a printed poster, a magazine, a brochure, a scale model or a toy car. This is the anti-cheat check: be strict, look for moiré, pixels, screen bezels, page edges, unnatural scale.
- "make": the manufacturer in its usual English spelling, e.g. "Volkswagen", "Mercedes-Benz", "Renault". Never an abbreviation, never translated.
- "model": the model name only, without the manufacturer, e.g. "Golf GTI", "Clio", "911". Include the sub-model when you are sure of it.
- "generation": the generation when you are sure of it, e.g. "IV", "Mk7", "992". Empty string otherwise. Never guess.
- "body": exactly one of ${BODIES.map((b) => `"${b}"`).join(", ")}. "hatch" covers superminis and hatchbacks, "van" covers minivans, MPVs and panel vans, "sport" is for coupés and sports cars.
- "color": exactly one of ${COLORS.map((c) => `"${c}"`).join(", ")}. Pick the closest one for the body paint, ignoring wraps of shadow and reflections.
- "confidence": how sure you are of make AND model, from 0 to 1. Be honest: a distant, dark or partial photo deserves a low value. Never inflate it — a wrong card is worse than a confirmation screen.
- When vehicle_present is false or is_screen is true, still return every field, with empty strings and confidence 0.
- Never add any text outside the JSON.`;

export function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

type QuotaStatus = "allowed" | "blocked" | "unavailable";

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  const sleep = deps.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));
  const model = deps.model || DEFAULT_MODEL;

  /// Incrémente et vérifie un compteur. Fail-closed, contrairement à l'ancienne
  /// version Supabase : une base injoignable désactivait tous les quotas, et c'est
  /// exactement ce qui est arrivé pendant la panne de septembre 2026. Mieux vaut un
  /// scan refusé qu'une facture OpenAI sans plafond.
  async function checkQuota(key: string, dayLimit: number, windowLimit: number): Promise<QuotaStatus> {
    if (!deps.db) return "unavailable";
    try {
      const { rows } = await deps.db.query(
        "select public.check_rate_limit($1, $2, $3, $4, $5) as result",
        [hashKey(key), dayLimit, WINDOW_SECONDS, windowLimit, null],
      );
      const result = rows[0]?.result;
      if (result?.allowed === true) return "allowed";
      if (result?.allowed === false) return "blocked";
      return "unavailable";
    } catch (error) {
      console.error("rate limit unavailable", error instanceof Error ? error.message : error);
      return "unavailable";
    }
  }

  /// Appelle OpenAI avec une nouvelle tentative sur les pannes passagères : un pic
  /// chez eux ne doit pas se traduire par une prise perdue pour le joueur.
  async function callOpenAI(payload: unknown): Promise<Response | null> {
    let lastResponse: Response | null = null;
    const body = JSON.stringify(payload);
    for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
      if (attempt > 0) {
        await sleep(RETRY_DELAYS_MS[attempt - 1]);
        console.warn("OpenAI: nouvelle tentative", attempt);
      }
      try {
        const response = await deps.fetch(OPENAI_URL, {
          method: "POST",
          headers: { "Authorization": `Bearer ${deps.openaiKey}`, "Content-Type": "application/json" },
          body,
        });
        const transient = response.status === 429 || response.status >= 500;
        if (!transient) return response;
        const detail = await response.text();
        console.warn("OpenAI indisponible", response.status, detail.slice(0, 300));
        lastResponse = new Response(detail, { status: response.status });
      } catch (error) {
        console.error("OpenAI injoignable", error instanceof Error ? error.message : error);
        lastResponse = null;
      }
    }
    return lastResponse;
  }

  return async function handle(req: Request): Promise<Response> {
    if (req.method !== "POST") {
      return json({ code: "method_not_allowed", error: "Method not allowed" }, 405);
    }
    if (!deps.openaiKey) {
      return json({ code: "server_misconfigured", error: "OPENAI_API_KEY manquante côté serveur" }, 500);
    }

    let body: { imageBase64?: unknown };
    try {
      body = await req.json();
    } catch {
      return json({ code: "bad_request", error: "Corps de requête invalide" }, 400);
    }

    const imageBase64 = typeof body?.imageBase64 === "string" ? body.imageBase64 : "";
    if (!imageBase64) {
      return json({ code: "missing_input", error: "Photo manquante" }, 400);
    }
    if (imageBase64.length > MAX_IMAGE_BASE64) {
      return json({ code: "image_too_large", error: "Cette photo est trop lourde" }, 413);
    }

    const clientIP = clientIPFrom(req.headers);
    const deviceId = deviceIdFrom(req.headers, clientIP);
    const [device, ip, global] = await Promise.all([
      checkQuota(`device:${deviceId}`, DEVICE_DAY_LIMIT, DEVICE_WINDOW_LIMIT),
      checkQuota(`ip:${clientIP}`, IP_DAY_LIMIT, IP_WINDOW_LIMIT),
      checkQuota("global", GLOBAL_DAY_LIMIT, GLOBAL_WINDOW_LIMIT),
    ]);
    if (device === "unavailable" || ip === "unavailable" || global === "unavailable") {
      return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    }
    // Le plafond global est distingué du quota personnel : dire « tu as trop scanné »
    // à quelqu'un qui n'y est pour rien serait un mensonge.
    if (global === "blocked") {
      console.error("plafond global atteint");
      return json({ code: "service_saturated", error: "Le service est saturé. Réessaie plus tard." }, 503);
    }
    if (device === "blocked" || ip === "blocked") {
      return json({ code: "rate_limited", error: "Trop de scans d'affilée. Réessaie un peu plus tard." }, 429);
    }

    const openaiResponse = await callOpenAI({
      model,
      temperature: 0.2, // identification, pas création : on veut la réponse la plus probable
      max_tokens: 200,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            { type: "text", text: "Identify the car in this photo." },
            { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBase64}`, detail: "high" } },
          ],
        },
      ],
    });

    if (!openaiResponse || !openaiResponse.ok) {
      if (openaiResponse) {
        const detail = await openaiResponse.text();
        console.error("OpenAI error", openaiResponse.status, detail.slice(0, 400));
        // Compte sans provision ou clé refusée : ce n'est pas une panne passagère, et
        // réessayer n'y changera rien. Côté joueur, le message reste neutre.
        const unfunded = openaiResponse.status === 401 || openaiResponse.status === 403 ||
          detail.includes("insufficient_quota") || detail.includes("billing");
        if (unfunded) {
          console.error("⚠️ COMPTE OPENAI SANS PROVISION OU CLÉ REFUSÉE — vérifier la facturation");
          return json({ code: "server_misconfigured", error: "Le service est momentanément indisponible." }, 503);
        }
      }
      return json({ code: "identification_failed", error: "L'identification a échoué, réessaie" }, 502);
    }

    const completion = await openaiResponse.json() as any;

    // Coût réel de l'appel, inscrit dans les journaux de la fonction.
    const usage = completion?.usage;
    if (usage) {
      const cost = (usage.prompt_tokens ?? 0) * PRICE_IN + (usage.completion_tokens ?? 0) * PRICE_OUT;
      console.log(`scan: ${usage.prompt_tokens} jetons entrée, ${usage.completion_tokens} sortie, $${cost.toFixed(5)}`);
    }

    try {
      const parsed = JSON.parse(completion.choices[0].message.content);
      const text = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 60) : "");
      const color = text(parsed.color).toLowerCase();
      const bodyType = text(parsed.body).toLowerCase();
      return json({
        make: text(parsed.make),
        model: text(parsed.model),
        generation: text(parsed.generation),
        // Repli sur "sedan" : la silhouette la plus neutre ; une carrosserie absente
        // empêcherait de dessiner la carte.
        body: BODIES.includes(bodyType) ? bodyType : "sedan",
        color: COLORS.includes(color) ? color : "",
        confidence: Math.max(0, Math.min(1, Number(parsed.confidence) || 0)),
        is_screen: parsed.is_screen === true,
        vehicle_present: parsed.vehicle_present !== false,
      });
    } catch {
      console.error("Réponse OpenAI inattendue", completion?.choices?.[0]?.message?.content);
      return json({ code: "unreadable_ai_response", error: "Réponse IA illisible, réessaie" }, 502);
    }
  };
}
