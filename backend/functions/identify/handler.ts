// Logique de la fonction "identify", sans dépendance à l'environnement :
// index.ts l'instancie avec process.env, la vraie base et le vrai fetch ;
// les tests l'instancient avec des doublures.
//
// Contrat d'API :
//   POST { imageBase64: string, entitlement?: string }
//        en-têtes : x-install-id (identifiant d'installation, rangé dans le trousseau
//        iOS, il survit à la désinstallation), x-device-id (identifierForVendor)
//   → 200 { make, model, generation, body, color, confidence, is_screen, vehicle_present,
//           free_scans_left: number | null }      (null = abonné, pas de plafond)
//   → 402 { code: "paywall_required", error, free_scans_left: 0 }
//        Avec `training_consent: true`, une vraie prise est conservée pour entraîner le
//        classifieur embarqué, et la réponse porte `sample_id`.
//   POST { action: "label", sample_id, vehicle_id, source: "confirmed" | "corrected" }
//   → 200 { ok: true }      (le joueur a désigné le bon modèle : l'étiquette qui fait foi)
//   POST { action: "forget" }
//   → 200 { deleted: n }    (retrait de l'accord : toutes les photos de l'installation)
//   → 4xx/5xx { code: string, error: string }
//     `code` est stable et traduit côté app ; `error` n'est qu'un repli lisible.
//
// **Le serveur est l'autorité sur les scans offerts.** Tant que le décompte vivait
// dans l'app, une réinstallation rendait les cinq scans et l'URL suffisait à scanner
// gratuitement. Un abonné le prouve par sa transaction StoreKit 2 signée par Apple
// (`entitlement`, vérifiée sans réseau, voir entitlement.ts) ; les autres consomment
// leurs scans offerts, comptés en base par installation.
//
// Le serveur ne connaît NI la rareté, NI les points, NI les règles du jeu :
// tout ça vit dans le catalogue embarqué de l'app, donc modifiable sans redéployer
// et sans supposer un pays. Ici on ne fait que lire une photo.

import { createHash, randomUUID } from "node:crypto";
import type { EntitlementResult } from "./entitlement";
import type { SampleStore } from "./storage";

/** Sous-ensemble de pg.Pool utilisé ici. */
export interface Queryable {
  query(text: string, values?: unknown[]): Promise<{ rows: any[] }>;
}

export interface HandlerDeps {
  openaiKey: string | undefined;
  /** Base des quotas ; null = pas de DATABASE_URL (fail-closed : 503). */
  db: Queryable | null;
  fetch: typeof fetch;
  verifyEntitlement: (jws: unknown) => Promise<EntitlementResult>;
  /** Scans offerts par installation (défaut : FREE_SCANS). */
  freeScans?: number;
  /** Compartiment des photos d'entraînement ; null = collecte désactivée. */
  samples?: SampleStore | null;
  newId?: () => string;
  /** Attente entre deux tentatives OpenAI (remplaçable en test). */
  sleep?: (ms: number) => Promise<void>;
  model?: string;
}

/// Scans offerts avant le paywall. Cinq : assez pour avoir vu plusieurs cartes et
/// compris le jeu, trop peu pour se faire une collection. L'app affiche ce que le
/// serveur lui renvoie ; sa propre constante ne sert plus qu'avant le premier scan.
export const FREE_SCANS = 5;

// Un abonnement peut servir sur plusieurs appareils (Partage familial) : borné
// par la transaction d'origine, infalsifiable, en plus du quota par appareil.
export const SUBSCRIPTION_DAY_LIMIT = 100;
export const SUBSCRIPTION_WINDOW_LIMIT = 15;

// Scans offerts demandés depuis une même IP par jour. L'identifiant d'installation
// vient du client : sans ce plafond, en inventer un nouveau à chaque requête
// donnerait des scans gratuits à l'infini. Large, parce que les opérateurs mobiles
// partagent une IP entre des milliers d'abonnés ; App Attest le remplacera.
export const FREE_IP_DAY_LIMIT = 60;
export const FREE_IP_WINDOW_LIMIT = 20;

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

/// Tarifs en dollars par million de jetons (entrée, sortie), par modèle. Ils ne servent
/// qu'à écrire le coût dans les journaux : une valeur périmée fausse la ligne de journal,
/// jamais la facturation. Un modèle absent de la table est journalisé sans coût plutôt
/// qu'au tarif d'un autre — c'est ce qui se passait quand seul gpt-4o y figurait.
export const PRICES: Record<string, [number, number]> = {
  "gpt-4o": [2.50, 10.00],
  "gpt-4.1-mini": [0.40, 1.60],
};

export function costOf(model: string, promptTokens: number, completionTokens: number): number | null {
  const price = PRICES[model];
  return price ? (promptTokens * price[0] + completionTokens * price[1]) / 1_000_000 : null;
}

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

/// Identifiant d'installation ; absent (ancienne version de l'app) → l'appareil.
export function installIdFrom(headers: Headers, deviceId: string): string {
  const raw = (headers.get("x-install-id") ?? "").trim().slice(0, MAX_DEVICE_ID);
  return raw || deviceId;
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

export const LABEL_SOURCES = ["confirmed", "corrected"];
const MAX_VEHICLE_ID = 120;

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  const sleep = deps.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));
  const model = deps.model || DEFAULT_MODEL;
  const freeScans = deps.freeScans ?? FREE_SCANS;
  const newId = deps.newId ?? randomUUID;

  /// Conserve une prise pour l'entraînement. Jamais bloquant : un échec de stockage
  /// coûte un exemple au classifieur, il ne doit pas coûter sa carte au joueur.
  async function keepSample(installKey: string, image: Buffer, ai: {
    make: string; model: string; generation: string; body: string; color: string; confidence: number;
  }): Promise<string | null> {
    if (!deps.samples || !deps.db) return null;
    const id = newId();
    const key = `samples/${id}.jpg`;
    try {
      await deps.samples.put(key, image);
      await deps.db.query(
        `insert into public.training_samples
           (id, install_hash, object_key, ai_make, ai_model, ai_generation, ai_body, ai_color, ai_confidence)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [id, hashKey(installKey), key, ai.make, ai.model, ai.generation, ai.body, ai.color, ai.confidence],
      );
      return id;
    } catch (error) {
      console.error("sample not kept", error instanceof Error ? error.message : error);
      return null;
    }
  }

  /// Étiquette du joueur. Limitée aux photos de sa propre installation : sans cette
  /// condition, n'importe qui connaissant un identifiant pourrait fausser le jeu de données.
  async function handleLabel(req: Request, body: Record<string, unknown>): Promise<Response> {
    const sampleId = typeof body.sample_id === "string" ? body.sample_id : "";
    const vehicleId = typeof body.vehicle_id === "string" ? body.vehicle_id.trim().slice(0, MAX_VEHICLE_ID) : "";
    const source = typeof body.source === "string" && LABEL_SOURCES.includes(body.source) ? body.source : "";
    if (!/^[0-9a-f-]{36}$/i.test(sampleId) || !vehicleId || !source) {
      return json({ code: "bad_request", error: "Étiquette invalide" }, 400);
    }
    if (!deps.db) return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    const clientIP = clientIPFrom(req.headers);
    const installKey = installIdFrom(req.headers, deviceIdFrom(req.headers, clientIP));
    try {
      await deps.db.query(
        `update public.training_samples
            set label_vehicle = $3, label_source = $4, labeled_at = now()
          where id = $1 and install_hash = $2`,
        [sampleId, hashKey(installKey), vehicleId, source],
      );
      return json({ ok: true });
    } catch (error) {
      console.error("label not recorded", error instanceof Error ? error.message : error);
      return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    }
  }

  /// Retrait de l'accord : tout ce que cette installation a confié disparaît, images
  /// comprises. Les lignes ne sont effacées qu'une fois les images supprimées, pour ne
  /// jamais laisser une image orpheline qu'aucune ligne ne permettrait plus de retrouver.
  async function handleForget(req: Request): Promise<Response> {
    if (!deps.db) return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    const clientIP = clientIPFrom(req.headers);
    const installHash = hashKey(installIdFrom(req.headers, deviceIdFrom(req.headers, clientIP)));
    try {
      const { rows } = await deps.db.query(
        "select object_key from public.training_samples where install_hash = $1", [installHash]);
      const keys = rows.map((r) => String(r.object_key));
      if (keys.length && deps.samples) await deps.samples.remove(keys);
      await deps.db.query("delete from public.training_samples where install_hash = $1", [installHash]);
      return json({ deleted: keys.length });
    } catch (error) {
      console.error("forget failed", error instanceof Error ? error.message : error);
      return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    }
  }

  /// Scans offerts déjà consommés par cette installation ; null si la base ne répond pas.
  async function freeScansUsed(installKey: string): Promise<number | null> {
    if (!deps.db) return null;
    try {
      const { rows } = await deps.db.query(
        "select used from public.free_scans where install_hash = $1",
        [hashKey(installKey)],
      );
      return Number(rows[0]?.used ?? 0);
    } catch (error) {
      console.error("free scans unavailable", error instanceof Error ? error.message : error);
      return null;
    }
  }

  /// Consomme un scan offert et renvoie le nouveau total. Un échec ici ne prive pas
  /// le joueur de sa carte : l'IA a déjà été payée, autant lui rendre le résultat.
  async function consumeFreeScan(installKey: string): Promise<number | null> {
    if (!deps.db) return null;
    try {
      const { rows } = await deps.db.query(
        "select public.consume_free_scan($1) as used",
        [hashKey(installKey)],
      );
      return Number(rows[0]?.used ?? 0);
    } catch (error) {
      console.error("free scan not recorded", error instanceof Error ? error.message : error);
      return null;
    }
  }

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

    let body: { imageBase64?: unknown; entitlement?: unknown; training_consent?: unknown; action?: unknown };
    try {
      body = await req.json();
    } catch {
      return json({ code: "bad_request", error: "Corps de requête invalide" }, 400);
    }
    if (typeof body !== "object" || body === null) {
      return json({ code: "bad_request", error: "Corps de requête invalide" }, 400);
    }
    if (body.action === "label") return handleLabel(req, body as Record<string, unknown>);
    if (body.action === "forget") return handleForget(req);

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

    // Abonné ou joueur sur ses scans offerts. Une transaction absente ou invalide
    // n'est pas une erreur : c'est le cas normal des cinq premiers scans.
    const entitlement = body.entitlement ? await deps.verifyEntitlement(body.entitlement) : null;
    const installKey = installIdFrom(req.headers, deviceId);
    let freeUsed: number | null = null;

    if (entitlement?.ok) {
      const sub = await checkQuota(`sub:${entitlement.originalTransactionId}`,
        SUBSCRIPTION_DAY_LIMIT, SUBSCRIPTION_WINDOW_LIMIT);
      if (sub === "unavailable") {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (sub === "blocked") {
        return json({ code: "rate_limited", error: "Trop de scans d'affilée. Réessaie un peu plus tard." }, 429);
      }
    } else {
      if (entitlement) console.warn("abonnement refusé:", entitlement.reason);
      freeUsed = await freeScansUsed(installKey);
      if (freeUsed === null) {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (freeUsed >= freeScans) {
        return json({ code: "paywall_required", error: "Les scans offerts sont épuisés.", free_scans_left: 0 }, 402);
      }
      const freeIP = await checkQuota(`free-ip:${clientIP}`, FREE_IP_DAY_LIMIT, FREE_IP_WINDOW_LIMIT);
      if (freeIP === "unavailable") {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (freeIP === "blocked") {
        return json({ code: "rate_limited", error: "Trop de scans d'affilée. Réessaie un peu plus tard." }, 429);
      }
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
      const cost = costOf(model, usage.prompt_tokens ?? 0, usage.completion_tokens ?? 0);
      console.log(`scan ${model}: ${usage.prompt_tokens} jetons entrée, ${usage.completion_tokens} sortie, ` +
                  (cost === null ? "coût inconnu" : `$${cost.toFixed(5)}`));
    }

    try {
      const parsed = JSON.parse(completion.choices[0].message.content);
      const text = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 60) : "");
      const color = text(parsed.color).toLowerCase();
      const bodyType = text(parsed.body).toLowerCase();
      const isScreen = parsed.is_screen === true;
      const vehiclePresent = parsed.vehicle_present !== false;

      // Seule une vraie prise consomme un scan offert : une photo sans voiture ou
      // d'un écran est refusée par l'app, la facturer au joueur serait injuste.
      const realCatch = vehiclePresent && !isScreen && text(parsed.model) !== "";
      let freeScansLeft: number | null = null;
      if (freeUsed !== null) {
        const used = realCatch ? (await consumeFreeScan(installKey)) ?? freeUsed + 1 : freeUsed;
        freeScansLeft = Math.max(0, freeScans - used);
      }
      const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
      const bodyValue = BODIES.includes(bodyType) ? bodyType : "sedan";
      const colorValue = COLORS.includes(color) ? color : "";
      const sampleId = realCatch && body.training_consent === true
        ? await keepSample(installKey, Buffer.from(imageBase64, "base64"), {
          make: text(parsed.make), model: text(parsed.model), generation: text(parsed.generation),
          body: bodyValue, color: colorValue, confidence,
        })
        : null;

      return json({
        make: text(parsed.make),
        model: text(parsed.model),
        generation: text(parsed.generation),
        // Repli sur "sedan" : la silhouette la plus neutre ; une carrosserie absente
        // empêcherait de dessiner la carte.
        body: bodyValue,
        color: colorValue,
        confidence,
        is_screen: isScreen,
        vehicle_present: vehiclePresent,
        free_scans_left: freeScansLeft,
        ...(sampleId ? { sample_id: sampleId } : {}),
      });
    } catch {
      console.error("Réponse OpenAI inattendue", completion?.choices?.[0]?.message?.content);
      return json({ code: "unreadable_ai_response", error: "Réponse IA illisible, réessaie" }, 502);
    }
  };
}
