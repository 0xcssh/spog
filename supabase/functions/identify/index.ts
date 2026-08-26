// Edge Function "identify" — relais unique entre l'app iOS Spog et OpenAI.
// La clé OpenAI vit ici (variable d'environnement OPENAI_API_KEY), jamais dans l'app.
//
// Contrat d'API :
//   POST { imageBase64: string }
//   → 200 { make, model, generation, color, confidence, is_screen, vehicle_present }
//   → 4xx/5xx { code: string, error: string }
//     `code` est stable et traduit côté app ; `error` n'est qu'un repli lisible.
//
// Le serveur ne connaît NI la rareté, NI les points, NI les règles du jeu :
// tout ça vit dans le catalogue embarqué de l'app, donc modifiable sans redéployer
// et sans supposer un pays. Ici on ne fait que lire une photo.

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

// Garde-fous anti-abus : la clé anon est embarquée dans l'app donc extractible.
// Sans ça, n'importe qui pourrait boucler sur cette fonction et faire exploser
// la facture OpenAI. Deux niveaux, parce que l'en-tête x-device-id vient du
// client et peut être falsifié : le quota par IP rattrape la rotation d'identifiants.
const WINDOW_SECONDS = 60;

const DEVICE_DAY_LIMIT = 200;   // par appareil et par jour — un joueur intensif scanne ~30 fois
const DEVICE_WINDOW_LIMIT = 15; // par appareil et par minute

// Les opérateurs mobiles font passer des milliers d'abonnés derrière une seule IP
// publique (CGNAT) : un seuil serré bloquerait des joueurs innocents. Ce quota-là
// ne sert qu'à casser une boucle d'attaque massive.
const IP_DAY_LIMIT = 20_000;
const IP_WINDOW_LIMIT = 1_200;

const MAX_IMAGE_BASE64 = 8_000_000; // ~6 Mo d'image, au-delà c'est anormal

/// Teintes que le modèle a le droit de renvoyer. Liste fermée : l'app doit pouvoir
/// rapprocher la couleur d'une peinture de sa palette sans deviner.
const COLORS = [
  "white", "black", "silver", "grey", "red", "blue", "dark blue",
  "green", "yellow", "orange", "purple", "teal", "brown", "beige",
];

/// Empreinte SHA-256 de l'identifiant d'appareil : on ne stocke jamais l'ID brut.
/// Le préfixe "spog:" sépare les compteurs de ceux de l'autre app du même projet.
async function hashDevice(deviceId: string): Promise<string> {
  const data = new TextEncoder().encode(`spog:${deviceId}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Incrémente et vérifie un compteur. En cas de panne d'infra on laisse passer
/// (on ne casse pas l'app pour ça), mais un quota dépassé bloque.
async function isWithinQuota(key: string, dayLimit: number, windowLimit: number): Promise<boolean> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return true;
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/check_rate_limit`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({
        p_device_hash: await hashDevice(key),
        p_day_limit: dayLimit,
        p_window_seconds: WINDOW_SECONDS,
        p_window_limit: windowLimit,
      }),
    });
    if (!response.ok) {
      console.error("rate limit rpc failed", response.status, await response.text());
      return true;
    }
    return Boolean((await response.json())?.allowed);
  } catch (error) {
    console.error("rate limit unreachable", error);
    return true;
  }
}

/// Appelle OpenAI avec une nouvelle tentative sur les pannes passagères : un pic
/// chez eux ne doit pas se traduire par une prise perdue pour le joueur.
async function callOpenAI(payload: unknown): Promise<Response | null> {
  const RETRY_DELAYS_MS = [400, 1200]; // 3 tentatives au total
  let lastResponse: Response | null = null;

  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    if (attempt > 0) {
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAYS_MS[attempt - 1]));
      console.warn("OpenAI: nouvelle tentative", attempt);
    }
    try {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      const transient = response.status === 429 || response.status >= 500;
      if (!transient) return response;
      const detail = await response.text();
      console.warn("OpenAI indisponible", response.status, detail.slice(0, 300));
      lastResponse = new Response(detail, { status: response.status });
    } catch (error) {
      console.error("OpenAI injoignable", error);
      lastResponse = null;
    }
  }
  return lastResponse;
}

// Identifiants techniques en anglais, jamais affichés tels quels : l'app traduit.
// Aucune règle de jeu ici, et surtout aucune mention de pays — la même réponse
// doit valoir partout.
const SYSTEM_PROMPT = `You identify a car from a photograph taken in the street. Answer with JSON only.

{
  "vehicle_present": boolean,
  "is_screen": boolean,
  "make": string,
  "model": string,
  "generation": string,
  "color": string,
  "confidence": number
}

Rules:
- "vehicle_present": false when the photo shows no car at all, or only a part too small to identify.
- "is_screen": true when the photo is not a real car in the real world — a picture of a screen, a monitor, a phone, a printed poster, a magazine, a brochure, a scale model or a toy car. This is the anti-cheat check: be strict, look for moiré, pixels, screen bezels, page edges, unnatural scale.
- "make": the manufacturer in its usual English spelling, e.g. "Volkswagen", "Mercedes-Benz", "Renault". Never an abbreviation, never translated.
- "model": the model name only, without the manufacturer, e.g. "Golf GTI", "Clio", "911". Include the sub-model when you are sure of it.
- "generation": the generation when you are sure of it, e.g. "IV", "Mk7", "992". Empty string otherwise. Never guess.
- "color": exactly one of ${COLORS.map((c) => `"${c}"`).join(", ")}. Pick the closest one for the body paint, ignoring wraps of shadow and reflections.
- "confidence": how sure you are of make AND model, from 0 to 1. Be honest: a distant, dark or partial photo deserves a low value. Never inflate it — a wrong card is worse than a confirmation screen.
- When vehicle_present is false or is_screen is true, still return every field, with empty strings and confidence 0.
- Never add any text outside the JSON.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ code: "method_not_allowed", error: "Method not allowed" }, 405);
  }
  if (!OPENAI_API_KEY) {
    return json({ code: "server_misconfigured", error: "OPENAI_API_KEY manquante côté serveur" }, 500);
  }

  let body: { imageBase64?: string };
  try {
    body = await req.json();
  } catch {
    return json({ code: "bad_request", error: "Corps de requête invalide" }, 400);
  }

  const imageBase64 = body.imageBase64;
  if (!imageBase64) {
    return json({ code: "missing_input", error: "Photo manquante" }, 400);
  }
  if (imageBase64.length > MAX_IMAGE_BASE64) {
    return json({ code: "image_too_large", error: "Cette photo est trop lourde" }, 413);
  }

  const clientIP = (req.headers.get("x-forwarded-for") ?? "ip-inconnue").split(",")[0].trim();
  const deviceId = req.headers.get("x-device-id") ?? clientIP;
  const [deviceOK, ipOK] = await Promise.all([
    isWithinQuota(`device:${deviceId}`, DEVICE_DAY_LIMIT, DEVICE_WINDOW_LIMIT),
    isWithinQuota(`ip:${clientIP}`, IP_DAY_LIMIT, IP_WINDOW_LIMIT),
  ]);
  if (!deviceOK || !ipOK) {
    return json({ code: "rate_limited", error: "Trop de scans d'affilée. Réessaie un peu plus tard." }, 429);
  }

  const openaiResponse = await callOpenAI({
    model: "gpt-4o",
    temperature: 0.2, // identification, pas création : on veut la réponse la plus probable
    max_tokens: 200,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          { type: "text", text: "Identify the car in this photo." },
          {
            type: "image_url",
            image_url: { url: `data:image/jpeg;base64,${imageBase64}`, detail: "high" },
          },
        ],
      },
    ],
  });

  if (!openaiResponse || !openaiResponse.ok) {
    if (openaiResponse) {
      console.error("OpenAI error", openaiResponse.status, await openaiResponse.text());
    }
    return json({ code: "identification_failed", error: "L'identification a échoué, réessaie" }, 502);
  }

  const completion = await openaiResponse.json();
  try {
    const parsed = JSON.parse(completion.choices[0].message.content);
    const text = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 60) : "");
    const color = text(parsed.color).toLowerCase();

    return json({
      make: text(parsed.make),
      model: text(parsed.model),
      generation: text(parsed.generation),
      color: COLORS.includes(color) ? color : "",
      confidence: Math.max(0, Math.min(1, Number(parsed.confidence) || 0)),
      is_screen: parsed.is_screen === true,
      vehicle_present: parsed.vehicle_present !== false,
    });
  } catch {
    console.error("Réponse OpenAI inattendue", completion.choices?.[0]?.message?.content);
    return json({ code: "unreadable_ai_response", error: "Réponse IA illisible, réessaie" }, 502);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
