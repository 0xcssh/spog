// Logique de la fonction "identify", sans dépendance à l'environnement :
// index.ts l'instancie avec process.env, la vraie base et le vrai fetch ;
// les tests l'instancient avec des doublures.
//
// Contrat d'API :
//   POST { imageBase64: string, entitlement?: string, country?: string }
//        `country` : pays de la prise, code ISO à 2 lettres. Facultatif (anciennes versions
//        de l'app) : sans lui, pas de cote.
//        en-têtes : x-install-id (identifiant d'installation, rangé dans le trousseau
//        iOS, il survit à la désinstallation), x-device-id (identifierForVendor)
//   → 200 { make, model, generation, body, color, confidence, is_screen, vehicle_present,
//           price_min, price_max, price_currency,
//           scans_left: number | null, resets_at }   (null = abonné, pas de plafond)
//        Cote d'occasion en fourchette, dans la devise du pays (voir price.ts) ; 0/0 quand
//        on ne sait pas, avec la devise du pays, ou "" si le pays manque ou est inconnu.
//   → 402 { code: "daily_limit", error, scans_left: 0, resets_at }
//        Avec `training_consent: true`, une vraie prise est conservée pour entraîner le
//        classifieur embarqué, et la réponse porte `sample_id`.
//   POST { action: "label", sample_id, vehicle_id, source: "confirmed" | "corrected" }
//   → 200 { ok: true }      (le joueur a désigné le bon modèle : l'étiquette qui fait foi)
//   POST { action: "forget" }
//   → 200 { deleted: n }    (retrait de l'accord : toutes les photos de l'installation)
//   Une vraie prise renvoie aussi `scan_id` : la preuve, pour le classement, que le modèle
//   déclaré ensuite correspond à une photo identifiée ici (voir social.ts).
//   POST { action: "me" | "set_pseudo" | "apple_link" | "catch" | … } → voir social.ts
//   POST { action: "develop", imageBase64, entitlement?, model?, quality?, stream? }
//   → 200 { image: "<jpeg base64, 1024 × 1024>", develops_left: number | null, resets_at, … }
//        Avec `stream: true` (ou `Accept: text/event-stream`) : 200 text/event-stream,
//        `event: partial` { image, index } à chaque image intermédiaire, puis
//        `event: done` { …la réponse JSON ci-dessus… } ou `event: error` { code, error }.
//        Les refus (402, 4xx, 5xx) restent des réponses JSON, avant tout flux.
//   → 402 { code: "develop_limit", develops_left: 0, resets_at }
//        Rendu studio de la voiture photographiée (voir develop.ts) : 1 par jour en gratuit,
//        plafond anti-abus seulement pour Pro et pour DEVELOP_TESTERS.
//   POST { action: "vehicle_art", vehicle_id }
//   → 200 { image: "<jpeg base64, 1024 × 1024>", cached: boolean }
//   → 403 { code: "unknown_vehicle" }   (identifiant absent du catalogue embarqué)
//   → 429 { code: "rate_limited" }       (quota de l'appareil, ou plafond global du jour)
//        Rendu studio carré d'un modèle du catalogue, pour tout ce que l'app montre sans
//        photo du joueur (voir art.ts) : généré une fois par modèle, puis servi depuis le
//        compartiment `art`.
//   → 4xx/5xx { code: string, error: string }
//     `code` est stable et traduit côté app ; `error` n'est qu'un repli lisible.
//
// **Le serveur est l'autorité sur les quotas du joueur gratuit** : 10 scans le premier
// jour, puis 3 par jour, et 1 rendu par jour (REFONTE.md, « Économie »). Tant que le
// décompte vivait dans l'app, une réinstallation le remettait à zéro. Un abonné le prouve
// par sa transaction StoreKit 2 signée par Apple (`entitlement`, vérifiée sans réseau,
// voir entitlement.ts) ; les autres consomment leurs quotas, comptés par installation.
//
// Le serveur ne connaît NI la rareté, NI les points, NI les règles du jeu :
// tout ça vit dans le catalogue embarqué de l'app, donc modifiable sans redéployer
// et sans supposer un pays. Ici on ne fait que lire une photo.

import { createHash, randomUUID } from "node:crypto";
import type { EntitlementResult } from "./entitlement";
import type { ArtStore, SampleStore } from "./storage";
import { STUDIO_PLATE_PNG } from "./studio-plate";
import { ART_ESTIMATED_USAGE, ART_MODEL, ART_QUALITY, ART_SIZE, ART_URL, allowedArtVehicle, artKey, artPrompt } from "./art";
import {
  DEVELOP_MODELS, DEVELOP_PARTIAL_IMAGES, DEVELOP_PROMPT, DEVELOP_QUALITIES, DEVELOP_SIZE, DEVELOP_URL, developCost,
  parseSSE, sseFrame, type ImageUsage,
} from "./develop";
import { candidates, expectedVehicleId } from "./catalog";
import { createSocial, SOCIAL_ACTIONS } from "./social";
import { currencyOf, marketHint, priceBracket } from "./price";
import type { AppleResult } from "./apple";

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
  /** Quotas du joueur gratuit (défaut : FREE_ALLOWANCE). */
  allowance?: typeof FREE_ALLOWANCE;
  /** Compartiment des photos d'entraînement ; null = collecte désactivée. */
  samples?: SampleStore | null;
  newId?: () => string;
  /** Installations autorisées à développer (tests de coût et de qualité). */
  developTesters?: Set<string>;
  verifyApple?: (token: unknown) => Promise<AppleResult>;
  /** Attente entre deux tentatives OpenAI (remplaçable en test). */
  sleep?: (ms: number) => Promise<void>;
  model?: string;
  /** Cache des rendus des cibles du pack ; null = action indisponible (jamais sans cache). */
  art?: ArtStore | null;
  /** Horloge (remplaçable en test, pour fixer la semaine du pack). */
  now?: () => Date;
  /** Garde l'invocation en vie pour un travail qui survit à la réponse (Neon : waitUntil). */
  waitUntil?: (promise: Promise<unknown>) => void;
}

/// Requêtes `vehicle_art` par appareil, cache compris : le pack, le garage et la fiche
/// demandent chacun leurs modèles, rouverts de temps en temps. Ce plafond ne gêne
/// personne et casse une boucle.
export const ART_DAY_LIMIT = 300;
export const ART_WINDOW_LIMIT = 30;
/// Plafond GLOBAL de générations payées par jour, tous appareils confondus. Le quota par
/// appareil ne suffit pas : mille faux appareils feraient générer tout le catalogue dans
/// l'heure. 300 rendus × ≈3,4 centimes ≈ 10 $ par jour au pire, et le catalogue entier se
/// remplit quand même en trois jours d'usage. Une demande servie par le cache ne compte
/// pas : elle ne coûte rien.
export const ART_GLOBAL_DAY_LIMIT = 300;
export const ART_GLOBAL_WINDOW_LIMIT = 40;

/// Issue d'une génération : l'image, ou la raison pour laquelle on n'a rien payé.
type ArtOutcome = { image: string | null; refusal?: "blocked" | "unavailable" };

/// Quotas du joueur gratuit. Dix scans le premier jour pour accrocher, puis trois par jour
/// pour faire revenir chaque jour ; un rendu par jour. Au-delà viendra la pub récompensée
/// (une pub par scan, toujours après la photo) ; d'ici là, Pro.
export const FREE_ALLOWANCE = { firstDayScans: 10, dailyScans: 3, dailyDevelops: 1 };
/// Plafond anti-abus des rendus d'un abonné : illimité en pratique, borné en coût
/// (50 rendus à 1,4 centime = 0,70 € par jour au pire).
export const PRO_DAILY_DEVELOPS = 50;

/// Prochaine remise à zéro des quotas : minuit UTC.
export function nextResetAt(now = new Date()): string {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
}

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
// doit valoir partout. Le marché de la cote arrive dans le message de l'utilisateur
// (voir price.ts) : ce prompt reste le même pour tous les pays.
export const SYSTEM_PROMPT = `You identify a car from a photograph taken in the street. Answer with JSON only.

{
  "vehicle_present": boolean,
  "is_screen": boolean,
  "make": string,
  "model": string,
  "generation": string,
  "body": string,
  "color": string,
  "confidence": number,
  "price_min": number,
  "price_max": number,
  "price_max_usd": number
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
- "price_min" and "price_max": the typical second-hand resale value of this car today on the market named in the user message, in the currency named there, as a bracket of whole amounts. You cannot see mileage, service history or mechanical condition, so the bracket must be wide enough to be honest — a narrow one you cannot justify is worse than none. Use the visible age, trim and condition. Both 0 when no market is named, when you would be guessing, and whenever confidence is below 0.7: an empty bracket is a valid answer.
- "price_max_usd": price_max expressed roughly in US dollars, 0 when price_max is 0. It is only a sanity check.
- When vehicle_present is false or is_screen is true, still return every field, with empty strings, confidence 0 and every price 0.
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
  const allowance = deps.allowance ?? FREE_ALLOWANCE;
  const newId = deps.newId ?? randomUUID;
  /// Générations en cours, par modèle : deux joueurs qui ouvrent le même pack à la même
  /// seconde ne doivent pas payer deux fois le même rendu, ni entamer deux fois le
  /// plafond global.
  const artInFlight = new Map<string, Promise<ArtOutcome>>();
  const social = createSocial({
    db: deps.db,
    verifyApple: deps.verifyApple ?? (async () => ({ ok: false, reason: "disabled" })),
  });

  /// Trace d'une identification réussie : le modèle retenu et les propositions qu'on
  /// montrerait au joueur. Jamais bloquante — sans elle, la prise reste une carte, mais
  /// n'entre pas au classement.
  async function recordScan(installKey: string, make: string, model: string, generation: string,
                            confidence: number): Promise<string | null> {
    if (!deps.db) return null;
    const id = newId();
    try {
      const full = [make, model, generation].filter(Boolean).join(" ");
      await deps.db.query(
        `insert into public.scans (id, install_hash, expected_vehicle, candidate_ids, confidence)
         values ($1, $2, $3, $4, $5)`,
        [id, hashKey(installKey), expectedVehicleId(make, model, generation),
         candidates(full).map((v) => v.id), confidence]);
      return id;
    } catch (error) {
      console.error("scan not recorded", error instanceof Error ? error.message : error);
      return null;
    }
  }

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

  /// Génère le rendu studio de la voiture photographiée. Une seule tentative : un rendu
  /// coûte cher, et le rejouer automatiquement sur une erreur pourrait le facturer deux fois.
  async function handleDevelop(req: Request, body: Record<string, unknown>): Promise<Response> {
    const clientIP = clientIPFrom(req.headers);
    const installId = installIdFrom(req.headers, deviceIdFrom(req.headers, clientIP));
    const image = typeof body.imageBase64 === "string" ? body.imageBase64 : "";
    if (!image) return json({ code: "missing_input", error: "Photo manquante" }, 400);
    if (image.length > MAX_IMAGE_BASE64) return json({ code: "image_too_large", error: "Cette photo est trop lourde" }, 413);

    // Quota du jour : 1 rendu en gratuit, plafond anti-abus pour Pro et pour les testeurs.
    const tester = isTester(installId);
    const entitlement = !tester && body.entitlement ? await deps.verifyEntitlement(body.entitlement) : null;
    const pro = tester || entitlement?.ok === true;
    const limit = pro ? PRO_DAILY_DEVELOPS : allowance.dailyDevelops;
    const left = await allowanceLeft(installId, "develop", limit, limit);
    if (left === null) return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    if (left <= 0) {
      return json({ code: "develop_limit", error: "Le rendu du jour est déjà utilisé.",
                    develops_left: 0, resets_at: nextResetAt() }, 402);
    }
    const imageModel = typeof body.model === "string" && DEVELOP_MODELS.includes(body.model) ? body.model : "gpt-image-1-mini";
    const quality = typeof body.quality === "string" && DEVELOP_QUALITIES.includes(body.quality) ? body.quality : "medium";
    // Le flux n'est servi qu'à un client qui l'annonce : les builds TestFlight d'avant
    // attendent une seule réponse JSON, et doivent continuer de la recevoir.
    const streaming = body.stream === true || (req.headers.get("accept") ?? "").includes("text/event-stream");

    const form = new FormData();
    form.append("model", imageModel);
    form.append("prompt", DEVELOP_PROMPT);
    form.append("size", DEVELOP_SIZE);
    form.append("quality", quality);
    // JPEG plutôt que le PNG par défaut : 300 Ko au lieu de 3 Mo à télécharger sur mobile.
    form.append("output_format", "jpeg");
    form.append("output_compression", "85");
    // Deux images, sous `image[]` (le nom que l'API attend pour une liste) : la photo du
    // joueur, puis la plaque du studio unique, le même décor que les rendus du catalogue.
    form.append("image[]", new Blob([Buffer.from(image, "base64")], { type: "image/jpeg" }), "car.jpg");
    form.append("image[]", new Blob([Buffer.from(STUDIO_PLATE_PNG, "base64")], { type: "image/png" }), "studio.png");
    if (streaming) {
      form.append("stream", "true");
      form.append("partial_images", String(DEVELOP_PARTIAL_IMAGES));
    }
    const started = Date.now();
    let response: Response;
    try {
      response = await deps.fetch(DEVELOP_URL, {
        method: "POST", headers: { "Authorization": `Bearer ${deps.openaiKey}` }, body: form,
      });
    } catch (error) {
      console.error("develop unreachable", error instanceof Error ? error.message : error);
      return json({ code: "identification_failed", error: "Le rendu a échoué, réessaie" }, 502);
    }
    // Les refus d'OpenAI arrivent avant le flux : ils restent une réponse JSON avec son
    // statut, que l'app lit de la même façon dans les deux modes.
    if (!response.ok) {
      console.error("develop error", response.status, (await response.text()).slice(0, 400));
      return json({ code: "identification_failed", error: "Le rendu a échoué, réessaie" }, 502);
    }

    /// Le rendu final : quota consommé ici seulement, jamais sur une image partielle ni
    /// sur un échec. Rend la charge utile du contrat JSON, identique dans les deux modes.
    const finish = async (jpeg: string, usage: ImageUsage, firstPartialMs: number | null) => {
      const cost = developCost(imageModel, usage);
      console.log(`develop ${imageModel} ${DEVELOP_SIZE} ${quality}${streaming ? " (flux)" : ""}: ` +
                  `${JSON.stringify(usage)}, ` + (cost === null ? "coût inconnu" : `$${cost.toFixed(4)}`) +
                  `, ${Date.now() - started} ms` +
                  (firstPartialMs === null ? "" : `, première image partielle à ${firstPartialMs} ms`));
      const used = await consumeAllowance(installId, "develop");
      return { image: jpeg, model: imageModel, quality, usage, cost_usd: cost,
               develops_left: pro ? null : Math.max(0, limit - (used ?? limit)),
               resets_at: nextResetAt() };
    };

    if (!streaming || !response.body) {
      const result = await response.json() as { data?: { b64_json?: string }[]; usage?: ImageUsage };
      const jpeg = result.data?.[0]?.b64_json;
      if (!jpeg) return json({ code: "unreadable_ai_response", error: "Rendu illisible, réessaie" }, 502);
      return json(await finish(jpeg, result.usage ?? {}, null));
    }
    return relayDevelopStream(response.body, started, finish);
  }

  /// Relaie à l'app le flux d'OpenAI : chaque image partielle dès qu'elle arrive
  /// (`partial`), puis le rendu final avec le décompte (`done`), ou `error`.
  ///
  /// La lecture d'OpenAI ne dépend pas de l'app : si le joueur ferme l'écran en route,
  /// on va quand même jusqu'au rendu final et le quota est consommé. Sinon, couper juste
  /// avant la fin donnerait des images partielles presque nettes sans jamais rien payer.
  function relayDevelopStream(
    upstream: ReadableStream<Uint8Array>, started: number,
    finish: (jpeg: string, usage: ImageUsage, firstPartialMs: number | null) => Promise<Record<string, unknown>>,
  ): Response {
    const encoder = new TextEncoder();
    let clientGone = false;
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    const send = (text: string) => {
      if (clientGone) return;
      try { controller.enqueue(encoder.encode(text)); } catch { clientGone = true; }
    };
    const close = () => {
      if (clientGone) return;
      try { controller.close(); } catch { /* déjà fermé par l'app */ }
    };
    const failed = (code: string, error: string) => sseFrame("error", { code, error });

    async function pump() {
      const reader = upstream.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let firstPartialMs: number | null = null;
      let delivered = false;
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (value) buffer += decoder.decode(value, { stream: true });
          if (done) buffer += decoder.decode() + "\n\n";
          const parsed = parseSSE(buffer);
          buffer = parsed.rest;
          for (const event of parsed.events) {
            if (!event.data || event.data === "[DONE]") continue;
            let payload: { type?: string; b64_json?: string; partial_image_index?: number;
                           usage?: ImageUsage; error?: { message?: string } };
            try { payload = JSON.parse(event.data); } catch { continue; }
            const type = payload.type ?? event.event;
            if (type === "image_edit.partial_image" && payload.b64_json) {
              if (firstPartialMs === null) firstPartialMs = Date.now() - started;
              send(sseFrame("partial", { image: payload.b64_json, index: payload.partial_image_index ?? 0 }));
            } else if (type === "image_edit.completed" && payload.b64_json && !delivered) {
              delivered = true;
              send(sseFrame("done", await finish(payload.b64_json, payload.usage ?? {}, firstPartialMs)));
            } else if (type === "error" || payload.error) {
              console.error("develop stream error", JSON.stringify(payload.error ?? payload).slice(0, 400));
              send(failed("identification_failed", "Le rendu a échoué, réessaie"));
              delivered = true;
            }
          }
          if (done) break;
        }
        if (!delivered) {
          console.error(`develop stream ended without image after ${Date.now() - started} ms`);
          send(failed("unreadable_ai_response", "Rendu illisible, réessaie"));
        }
      } catch (error) {
        console.error("develop stream broken", error instanceof Error ? error.message : error);
        if (!delivered) send(failed("identification_failed", "Le rendu a échoué, réessaie"));
      } finally {
        close();
      }
    }

    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        controller = c;
        // Un premier octet tout de suite : les en-têtes partent, et l'app sait que le
        // flux est ouvert pendant les secondes qui précèdent la première image.
        send(": open\n\n");
        const pumping = pump();
        deps.waitUntil?.(pumping);
      },
      cancel() { clientGone = true; },
    });
    return new Response(stream, {
      status: 200,
      headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache, no-transform" },
    });
  }

  /// Rendu studio d'un modèle du catalogue. Le cache d'abord ; sinon une génération, une
  /// seule tentative (comme `develop` : rejouer une image pourrait la facturer deux fois).
  async function handleVehicleArt(req: Request, body: Record<string, unknown>): Promise<Response> {
    const vehicleId = typeof body.vehicle_id === "string" ? body.vehicle_id.trim().slice(0, MAX_VEHICLE_ID) : "";
    if (!vehicleId) return json({ code: "bad_request", error: "Modèle manquant" }, 400);
    // La vérification du catalogue passe avant tout accès au stockage : c'est elle qui
    // borne ce que l'URL publique peut faire générer (le catalogue embarqué, rien de plus).
    const target = allowedArtVehicle(vehicleId);
    if (!target) return json({ code: "unknown_vehicle", error: "Ce modèle n'est pas au catalogue." }, 403);
    // Sans cache, chaque affichage paierait une image : on refuse plutôt.
    if (!deps.art) return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);

    const ip = clientIPFrom(req.headers);
    const quota = await checkQuota(`art:${deviceIdFrom(req.headers, ip)}`, ART_DAY_LIMIT, ART_WINDOW_LIMIT);
    if (quota === "unavailable") return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    if (quota === "blocked") return json({ code: "rate_limited", error: "Trop de requêtes. Réessaie un peu plus tard." }, 429);

    const key = artKey(target.id);
    let cached: Buffer | null;
    try {
      cached = await deps.art.get(key);
    } catch (error) {
      // Stockage en panne : surtout ne pas regénérer, ce serait payer à chaque appel.
      console.error("art cache unavailable", error instanceof Error ? error.message : error);
      return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    }
    if (cached) return json({ image: cached.toString("base64"), cached: true });

    // La promesse est rangée sans `await` intermédiaire : une deuxième demande arrivée
    // pendant la vérification du plafond global la rejoint au lieu de payer un second rendu.
    let pending = artInFlight.get(key);
    if (!pending) {
      pending = generateArtWithinBudget(target, key).finally(() => artInFlight.delete(key));
      artInFlight.set(key, pending);
    }
    const outcome = await pending;
    if (outcome.image) return json({ image: outcome.image, cached: false });
    if (outcome.refusal === "blocked") {
      return json({ code: "rate_limited", error: "Trop de rendus aujourd'hui. Réessaie demain." }, 429);
    }
    if (outcome.refusal === "unavailable") {
      return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
    }
    return json({ code: "identification_failed", error: "Le rendu a échoué, réessaie" }, 502);
  }

  /// Le plafond global n'est entamé que par une génération réelle : ni une demande servie
  /// par le cache, ni une demande qui rejoint une génération déjà en cours. Fail-closed,
  /// comme les autres quotas : sans base, on ne paie rien.
  async function generateArtWithinBudget(target: Parameters<typeof artPrompt>[0], key: string): Promise<ArtOutcome> {
    const budget = await checkQuota("art-global", ART_GLOBAL_DAY_LIMIT, ART_GLOBAL_WINDOW_LIMIT);
    if (budget !== "allowed") {
      console.warn(`art ${target.id}: plafond global ${budget === "blocked" ? "atteint" : "injoignable"}`);
      return { image: null, refusal: budget };
    }
    return { image: await generateArt(target, key) };
  }

  async function generateArt(target: Parameters<typeof artPrompt>[0], key: string): Promise<string | null> {
    let response: Response;
    try {
      const form = new FormData();
      form.append("model", ART_MODEL);
      form.append("prompt", artPrompt(target));
      form.append("size", ART_SIZE);
      form.append("quality", ART_QUALITY);
      // JPEG : ~250 Ko au lieu de 2 Mo, à stocker comme à télécharger sur mobile.
      // 90 plutôt que 85 : en plein écran, les artefacts se voyaient sur les reflets du sol.
      form.append("output_format", "jpeg");
      form.append("output_compression", "90");
      form.append("n", "1");
      form.append("image", new Blob([Buffer.from(STUDIO_PLATE_PNG, "base64")], { type: "image/png" }), "studio.png");
      response = await deps.fetch(ART_URL, {
        method: "POST", headers: { "Authorization": `Bearer ${deps.openaiKey}` }, body: form,
      });
    } catch (error) {
      console.error("art unreachable", error instanceof Error ? error.message : error);
      return null;
    }
    if (!response.ok) {
      console.error("art error", response.status, (await response.text()).slice(0, 400));
      return null;
    }
    const result = await response.json() as { data?: { b64_json?: string }[]; usage?: ImageUsage };
    const image = result.data?.[0]?.b64_json;
    if (!image) return null;
    // Sans usage renvoyé, on journalise quand même une estimation : le coût de ces rendus
    // doit rester lisible dans les journaux, même approché.
    const usage: ImageUsage = result.usage ?? ART_ESTIMATED_USAGE;
    const cost = developCost(ART_MODEL, usage);
    console.log(`art ${target.id} ${ART_SIZE} ${ART_QUALITY}: ${JSON.stringify(usage)}` +
                (result.usage ? "" : " (estimé)") + ", " +
                (cost === null ? "coût inconnu" : `$${cost.toFixed(4)}`));
    try {
      await deps.art!.put(key, Buffer.from(image, "base64"));
    } catch (error) {
      // Le joueur a son image quand même ; le prochain la regénérera, c'est le seul coût.
      console.error("art not cached", error instanceof Error ? error.message : error);
    }
    return image;
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

  /// Ce qui reste aujourd'hui à cette installation ; null si la base ne répond pas.
  async function allowanceLeft(installKey: string, kind: "scan" | "develop",
                               firstDay: number, daily: number): Promise<number | null> {
    if (!deps.db) return null;
    try {
      const { rows } = await deps.db.query(
        "select public.allowance_left($1, $2, $3, $4) as left",
        [hashKey(installKey), kind, firstDay, daily],
      );
      return Number(rows[0]?.left ?? 0);
    } catch (error) {
      console.error("allowance unavailable", error instanceof Error ? error.message : error);
      return null;
    }
  }

  /// Consomme une unité du jour et renvoie le total consommé. Un échec ici ne prive pas
  /// le joueur de sa carte : l'IA a déjà été payée, autant lui rendre le résultat.
  /// Installation de test : listée dans DEVELOP_TESTERS par son identifiant, ou par son
  /// empreinte (`hashKey`) — la seule chose que la base conserve, donc la seule qu'on
  /// puisse retrouver sans demander l'identifiant au testeur.
  function isTester(installKey: string): boolean {
    const testers = deps.developTesters;
    if (!testers || testers.size === 0) return false;
    return testers.has(installKey) || testers.has(hashKey(installKey));
  }

  async function consumeAllowance(installKey: string, kind: "scan" | "develop"): Promise<number | null> {
    if (!deps.db) return null;
    try {
      const { rows } = await deps.db.query(
        "select public.consume_allowance($1, $2) as used", [hashKey(installKey), kind]);
      return Number(rows[0]?.used ?? 0);
    } catch (error) {
      console.error("allowance not recorded", error instanceof Error ? error.message : error);
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

    let body: { imageBase64?: unknown; entitlement?: unknown; training_consent?: unknown; action?: unknown;
                country?: unknown };
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
    if (typeof body.action === "string" && SOCIAL_ACTIONS.includes(body.action)) {
      const ip = clientIPFrom(req.headers);
      // Les actions sociales ne coûtent rien côté IA, mais restent sous le quota de l'appareil.
      const quota = await checkQuota(`social:${deviceIdFrom(req.headers, ip)}`, 2_000, 120);
      if (quota === "unavailable") {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (quota === "blocked") return json({ code: "rate_limited", error: "Trop de requêtes. Réessaie un peu plus tard." }, 429);
      return social(body.action, hashKey(installIdFrom(req.headers, deviceIdFrom(req.headers, ip))),
                    body as Record<string, unknown>);
    }
    if (body.action === "vehicle_art") return handleVehicleArt(req, body as Record<string, unknown>);
    if (body.action === "develop") {
      if (!deps.openaiKey) return json({ code: "server_misconfigured", error: "OPENAI_API_KEY manquante côté serveur" }, 500);
      return handleDevelop(req, body as Record<string, unknown>);
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

    // Abonné ou joueur gratuit. Une transaction absente ou invalide n'est pas une erreur :
    // c'est le cas normal du joueur gratuit.
    const installKey = installIdFrom(req.headers, deviceId);
    // Les testeurs (DEVELOP_TESTERS) scannent comme des abonnés, sans transaction : le
    // développeur ne doit pas buter sur le quota gratuit en essayant l'app.
    const tester = isTester(installKey);
    const entitlement = !tester && body.entitlement ? await deps.verifyEntitlement(body.entitlement) : null;
    let scansLeft: number | null = null;

    if (tester) {
      // Rien à décompter ; les plafonds par appareil et globaux ci-dessus s'appliquent.
    } else if (entitlement?.ok) {
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
      scansLeft = await allowanceLeft(installKey, "scan", allowance.firstDayScans, allowance.dailyScans);
      if (scansLeft === null) {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (scansLeft <= 0) {
        return json({ code: "daily_limit", error: "Les scans du jour sont épuisés.",
                      scans_left: 0, resets_at: nextResetAt() }, 402);
      }
      const freeIP = await checkQuota(`free-ip:${clientIP}`, FREE_IP_DAY_LIMIT, FREE_IP_WINDOW_LIMIT);
      if (freeIP === "unavailable") {
        return json({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
      }
      if (freeIP === "blocked") {
        return json({ code: "rate_limited", error: "Trop de scans d'affilée. Réessaie un peu plus tard." }, 429);
      }
    }

    // Devise déduite du pays de la prise. Un pays absent ou inconnu ne bloque rien :
    // l'identification part quand même, simplement sans marché, donc sans cote.
    const currency = currencyOf(body.country);
    const market = currency ? ` ${marketHint(String(body.country).trim().toUpperCase(), currency)}` : "";

    const openaiResponse = await callOpenAI({
      model,
      temperature: 0.2, // identification, pas création : on veut la réponse la plus probable
      // 260 plutôt que 200 : les trois montants de la cote allongent la réponse d'une
      // trentaine de jetons, et une réponse tronquée serait un JSON illisible.
      max_tokens: 260,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            { type: "text", text: `Identify the car in this photo.${market}` },
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

      // Seule une vraie prise consomme un scan du jour : une photo sans voiture ou d'un
      // écran est refusée par l'app, la facturer au joueur serait injuste.
      const realCatch = vehiclePresent && !isScreen && text(parsed.model) !== "";
      if (scansLeft !== null && realCatch) {
        await consumeAllowance(installKey, "scan");
        scansLeft = Math.max(0, scansLeft - 1);
      }
      const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
      const bodyValue = BODIES.includes(bodyType) ? bodyType : "sedan";
      const colorValue = COLORS.includes(color) ? color : "";
      const scanId = realCatch
        ? await recordScan(installKey, text(parsed.make), text(parsed.model), text(parsed.generation), confidence)
        : null;
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
        // Pas de cote sans vraie prise : une photo d'écran ou sans voiture n'a rien à coter.
        ...priceBracket(realCatch ? parsed : {}, currency, confidence),
        scans_left: scansLeft,
        ...(scansLeft !== null ? { resets_at: nextResetAt() } : {}),
        ...(sampleId ? { sample_id: sampleId } : {}),
        ...(scanId ? { scan_id: scanId } : {}),
      });
    } catch {
      console.error("Réponse OpenAI inattendue", completion?.choices?.[0]?.message?.content);
      return json({ code: "unreadable_ai_response", error: "Réponse IA illisible, réessaie" }, 502);
    }
  };
}
