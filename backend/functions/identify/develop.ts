// « Passer en studio » (action `develop`) : un rendu studio généré À PARTIR de la photo du joueur.
//
// Pas une illustration de catalogue : le rendu garde ce qui fait cette voiture-là — sa
// teinte exacte, ses jantes, son covering, ses kits. C'est la réponse au dilemme du
// 07/10/2026 (la photo du joueur passe avant le rendu studio du modèle) : on n'a plus à
// choisir, le rendu studio EST sa voiture.
//
// Chaque rendu coûte bien plus qu'une identification. Tant que la monnaie de
// développement n'existe pas, l'action n'est ouverte qu'aux installations listées dans
// DEVELOP_TESTERS : elle sert à mesurer coût et qualité, pas encore aux joueurs.

// Le décor est la plaque du studio unique des modèles (`studio-plate.ts`), envoyée en
// seconde image (09/10/2026). Le décor néon violet et cyan d'avant faisait de chaque carte
// passée en studio l'objet d'une autre collection que le catalogue (retour testeur :
// « pourquoi on revient sur ce background et pas sur l'autre ? »).
export const DEVELOP_PROMPT =
  "You are given two images. The FIRST image is a street photo of a car. The SECOND image is an " +
  "empty photo studio. Keep EXACTLY this car from the first image: the exact paint colour and finish, " +
  "wheels, body kit, wing, wrap or livery, decals and any wear. Same car, same viewing angle, nothing " +
  "restyled or replaced. Place it INSIDE THE STUDIO OF THE SECOND IMAGE, parked on its floor. Keep the " +
  "studio exactly as it is: same dark charcoal wall, same soft horizon, same floor, same soft overhead " +
  "light and pool of light on the floor. Do not add anything to the background: no neon, no coloured " +
  "lights, no light strips, no walls, no props. The tyres rest firmly ON the floor, with a dark natural " +
  "contact shadow right under each tyre, a soft ambient shadow under the body and a faint, soft " +
  "reflection on the floor. Square composition: the whole car in frame and centred, occupying about " +
  "80% of the image width; nothing of the car is cropped. The car is brightly and evenly lit, razor " +
  "sharp, photorealistic automotive product photography. Erase the licence plate text. No people, " +
  "no added text or logos.";

/// Carré, comme les rendus du catalogue : la zone image d'une carte l'est presque
/// (rapport 1,02). Le 1536 × 1024 d'avant se montrait en entier entre deux bandes floutées,
/// et coûtait moitié plus de jetons de sortie — donc d'attente.
export const DEVELOP_SIZE = "1024x1024";
/// Images intermédiaires demandées quand l'app sait les afficher (0 à 3 chez OpenAI). Deux
/// suffisent à voir la carte prendre forme ; chacune ajoute des jetons de sortie.
export const DEVELOP_PARTIAL_IMAGES = 2;
export const DEVELOP_URL = "https://api.openai.com/v1/images/edits";

export const DEVELOP_MODELS = ["gpt-image-1", "gpt-image-1-mini"];
export const DEVELOP_QUALITIES = ["low", "medium", "high"];

/// Tarifs publics en $ par million de jetons : entrée texte, entrée image, sortie image.
/// Ne servent qu'à journaliser et à renvoyer une estimation ; la facture fait foi.
export const DEVELOP_PRICES: Record<string, [number, number, number]> = {
  "gpt-image-1": [5.0, 10.0, 40.0],
  "gpt-image-1-mini": [2.0, 2.5, 8.0],
};

export interface ImageUsage {
  input_tokens?: number;
  output_tokens?: number;
  input_tokens_details?: { text_tokens?: number; image_tokens?: number };
}

export function developCost(model: string, usage: ImageUsage): number | null {
  const price = DEVELOP_PRICES[model];
  if (!price) return null;
  const details = usage.input_tokens_details ?? {};
  return ((details.text_tokens ?? 0) * price[0] + (details.image_tokens ?? 0) * price[1] +
    (usage.output_tokens ?? 0) * price[2]) / 1_000_000;
}

/// Liste des installations autorisées, depuis la variable d'environnement.
export function testersFrom(raw: string | undefined): Set<string> {
  return new Set((raw ?? "").split(",").map((s) => s.trim()).filter(Boolean));
}

/// Un événement d'un flux SSE : son nom (`event:`, vide s'il manque) et ses lignes `data:`.
export interface SSEEvent { event: string; data: string }

/// Découpe ce qui est arrivé d'un flux SSE en événements complets, et rend le reste : un
/// événement coupé entre deux paquets réseau. Une image partielle pèse des centaines de
/// kilo-octets en base64, elle arrive toujours en plusieurs morceaux.
export function parseSSE(buffer: string): { events: SSEEvent[]; rest: string } {
  const blocks = buffer.replace(/\r\n/g, "\n").split("\n\n");
  const rest = blocks.pop() ?? "";
  const events: SSEEvent[] = [];
  for (const block of blocks) {
    let event = "";
    const data: string[] = [];
    for (const line of block.split("\n")) {
      if (line.startsWith(":")) continue;   // commentaire, battement de cœur
      const colon = line.indexOf(":");
      const field = colon < 0 ? line : line.slice(0, colon);
      let value = colon < 0 ? "" : line.slice(colon + 1);
      if (value.startsWith(" ")) value = value.slice(1);
      if (field === "event") event = value;
      else if (field === "data") data.push(value);
    }
    if (event || data.length) events.push({ event, data: data.join("\n") });
  }
  return { events, rest };
}

/// Un événement à envoyer à l'app, au format SSE : une seule ligne `data:`, le JSON n'ayant
/// jamais de saut de ligne.
export function sseFrame(event: string, payload: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`;
}
