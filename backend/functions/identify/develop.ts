// « Développer » une carte : un rendu studio généré À PARTIR de la photo du joueur.
//
// Pas une illustration de catalogue : le rendu garde ce qui fait cette voiture-là — sa
// teinte exacte, ses jantes, son covering, ses kits. C'est la réponse au dilemme du
// 07/10/2026 (la photo du joueur passe avant le rendu studio du modèle) : on n'a plus à
// choisir, le rendu studio EST sa voiture.
//
// Chaque rendu coûte bien plus qu'une identification. Tant que la monnaie de
// développement n'existe pas, l'action n'est ouverte qu'aux installations listées dans
// DEVELOP_TESTERS : elle sert à mesurer coût et qualité, pas encore aux joueurs.

export const DEVELOP_PROMPT =
  "Turn this street photo into a studio portrait of THIS EXACT car. Keep everything that makes " +
  "this specific car unique: the exact paint colour and finish, wheels, body kit, wing, wrap or " +
  "livery, decals, and any wear. Same car, same angle. Replace the background with a dark studio: " +
  "polished dark floor with a soft reflection, subtle violet and cyan neon light strips on the wall " +
  "behind, staying in the background. The car is brightly and evenly lit, razor sharp, photorealistic " +
  "automotive product photography. Remove the licence plate text and any people. No added text or logos.";

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
