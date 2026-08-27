// Edge Function "render" — fabrique l'illustration studio d'un modèle.
//
// Elle existe pour une seule raison : la clé OpenAI vit ici, pas sur la machine de
// développement. Sans elle, le catalogue resterait à huit illustrations sur près de six
// cents, et une voiture scannée n'aurait pas la même allure que celles déjà en garage.
//
// ⚠️ Cette fonction coûte cher par appel — une image, pas quelques jetons de texte.
// Elle n'est donc **pas** appelable par l'app : la clé anon est publique, un endpoint de
// génération d'images ouvert à tous serait un puits sans fond. Il faut en plus le secret
// partagé `RENDER_SECRET`, connu du seul outil local.
//
// Contrat :
//   POST { make, model, body, paint }  + en-tête x-render-secret
//   → 200 { image: "<png en base64>" }
//   → 4xx/5xx { code, error }

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const RENDER_SECRET = Deno.env.get("RENDER_SECRET");

/// Même gabarit que pour les huit premières illustrations : c'est l'unité de style qui
/// fait tenir une collection. Ni logo ni plaque — on ne reproduit pas de marque déposée.
const PROMPT = (make: string, model: string, body: string, paint: string) =>
  `Photorealistic photograph of a ${paint} ${make} ${model}, ${body}, ` +
  "in a dark showroom lit by horizontal neon light bars. " +
  "Three-quarter front view, camera slightly below the beltline, the whole car in frame with room around it. " +
  "Cyan and violet neon strips glowing on the wall behind the car, their light reflected along the flanks " +
  "and mirrored on a wet polished black floor, deep black shadows, cinematic rim lighting on the shoulder line, " +
  "glossy paint with crisp highlights. " +
  "No text, no badges, no logos, no licence plate, no people, no props. " +
  "Wide landscape composition, the car filling most of the width, high-end automotive advertising look.";

const BODY_WORDS: Record<string, string> = {
  hatch: "compact hatchback", sedan: "four-door sedan", suv: "SUV",
  sport: "low sports car", pickup: "pickup truck", van: "panel van",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ code: "method_not_allowed", error: "Method not allowed" }, 405);
  }
  if (!OPENAI_API_KEY || !RENDER_SECRET) {
    return json({ code: "server_misconfigured", error: "Clé ou secret manquant côté serveur" }, 500);
  }
  // Le secret d'abord : rien ne doit atteindre OpenAI sans lui.
  if (req.headers.get("x-render-secret") !== RENDER_SECRET) {
    return json({ code: "forbidden", error: "Secret de rendu invalide" }, 403);
  }

  let body: { make?: string; model?: string; body?: string; paint?: string };
  try {
    body = await req.json();
  } catch {
    return json({ code: "bad_request", error: "Corps de requête invalide" }, 400);
  }

  const make = (body.make ?? "").trim().slice(0, 40);
  const model = (body.model ?? "").trim().slice(0, 40);
  if (!make || !model) {
    return json({ code: "missing_input", error: "Marque ou modèle manquant" }, 400);
  }
  const shape = BODY_WORDS[(body.body ?? "").toLowerCase()] ?? "car";
  const paint = (body.paint ?? "metallic silver").trim().slice(0, 40);

  const payload = {
    model: "gpt-image-1",
    prompt: PROMPT(make, model, shape, paint),
    size: "1536x1024",
    quality: "medium",
    output_format: "png",
    n: 1,
  };

  // Trois tentatives : une surcharge passagère ne doit pas coûter une illustration
  // dans un lot de plusieurs centaines.
  const DELAYS = [1500, 4000];
  let last = "";
  for (let attempt = 0; attempt <= DELAYS.length; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, DELAYS[attempt - 1]));
    try {
      const response = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      if (response.ok) {
        const data = await response.json();
        const image = data?.data?.[0]?.b64_json;
        if (!image) return json({ code: "empty_render", error: "Réponse sans image" }, 502);
        return json({ image });
      }
      last = (await response.text()).slice(0, 300);
      if (response.status !== 429 && response.status < 500) break; // erreur définitive
    } catch (error) {
      last = String(error);
    }
  }
  console.error("rendu impossible", last);
  return json({ code: "render_failed", error: "La génération a échoué" }, 502);
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
