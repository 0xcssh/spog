// Rendu studio d'un modèle du catalogue (action `vehicle_art`).
//
// Pourquoi : les rendus embarqués de l'app (`Spog/CarArt/*.jpg`) font 660 × 290. Dans une
// carte presque carrée, la voiture n'occupait que la moitié haute, floue dès qu'on
// l'agrandissait (retour du testeur du 08/10/2026 : « même le cadrage est nul »). Les
// rendus d'ici sont carrés et haute définition, au format exact des cartes : l'app les
// affiche en plein cadre, et seul le fond de studio est rogné, jamais la voiture.
//
// Le rendu est généré UNE fois par modèle, puis rangé dans le compartiment privé `art` :
// tous les joueurs de tous les pays partagent la même image, le coût est payé une fois par
// modèle et jamais par joueur.
//
// **Coût borné.** N'importe quel modèle du catalogue embarqué peut être demandé — le pack,
// le garage, la fiche et le partage en ont besoin, pas seulement les cibles de la semaine.
// 867 modèles × ≈3,4 centimes de dollar ≈ 30 $, payés une seule fois. Ce qui empêcherait
// une boucle de tout générer d'un coup vit dans handler.ts : quota par appareil, et un
// plafond GLOBAL de générations par jour (ART_GLOBAL_DAY_LIMIT).

import { createHash } from "node:crypto";
import { vehicle, type Vehicle } from "./catalog";

export const ART_MODEL = "gpt-image-1-mini";
/// Édition, pas génération libre (09/10/2026) : la voiture est peinte DANS la plaque du
/// studio unique (`studio-plate.ts`). Le décor est le même pour tout le catalogue, et la
/// voiture y a sa vraie ombre et son vrai reflet. Détourer puis poser sur un décor dessiné
/// donnait une voiture « en suspension » (retour testeur) : l'ombre inventée ne collait
/// jamais à la perspective ni à la lumière du rendu.
export const ART_URL = "https://api.openai.com/v1/images/edits";
/// Carré : la zone image d'une carte l'est presque (rapport 1,02). Un bandeau 3:2 forçait
/// l'app à choisir entre couper la voiture et la montrer en timbre-poste.
export const ART_SIZE = "1024x1024";
/// `high` : 4 160 jetons de sortie en 1024², soit ≈3,3 centimes de dollar au tarif de
/// `gpt-image-1-mini` (8 $ le million) — sous le plafond de 4 centimes fixé pour ces
/// rendus. `medium` (1 056 jetons, ≈0,9 centime) laissait des jantes et des optiques
/// pâteuses, visibles dès que la carte occupe l'écran.
export const ART_QUALITY = "high";
/// Estimation journalisée quand OpenAI ne renvoie pas d'usage : jetons de sortie d'un
/// rendu 1024² en qualité `high`, un prompt d'environ 300 jetons et la plaque en entrée.
export const ART_ESTIMATED_USAGE = {
  input_tokens: 1600, output_tokens: 4160,
  input_tokens_details: { text_tokens: 300, image_tokens: 1300 },
};

/// Clé de l'objet en cache. L'identifiant vient du catalogue (vérifié avant), jamais
/// directement du client : pas de chemin arbitraire possible dans le compartiment.
/// Préfixe `v4/` : sans emblème, voiture un peu plus petite dans le cadre (10/10/2026 —
/// les `v3/` montraient encore les logos Suzuki et Renault, et le Jimny touchait presque
/// les bords). Avant, `v3/` : rendus faits dans la plaque du studio unique. Les `v2/` (décors néon
/// tous différents) et les bandeaux d'avant restent dans le compartiment, jamais resservis.
export function artKey(vehicleId: string): string {
  return `vehicles/v4/${vehicleId}.jpg`;
}

const BODY_WORDS: Record<string, string> = {
  hatch: "compact hatchback", sedan: "four-door sedan", suv: "SUV",
  sport: "low sports car", pickup: "pickup truck", van: "van",
};

/// Teintes de série, choisies de façon stable d'après l'identifiant : trois cibles de la
/// même semaine n'ont presque jamais la même couleur, ce qui les distingue d'un coup d'œil
/// — le reproche fait au pack était justement « trois cartes identiques ».
export const ART_PAINTS = [
  "metallic silver", "gloss black", "pearl white", "deep metallic red", "metallic dark blue",
  "graphite grey", "racing green", "bright yellow", "electric blue", "burnt orange",
];

export function paintFor(vehicleId: string): string {
  const digest = createHash("sha256").update(`paint:${vehicleId}`).digest();
  return ART_PAINTS[digest.readUInt32BE(0) % ART_PAINTS.length];
}

/// Gabarit unique pour tout le catalogue : c'est l'unité de style qui fait tenir la
/// collection. Ni logo, ni plaque, ni texte — on ne reproduit pas de marque déposée.
export function artPrompt(v: Pick<Vehicle, "id" | "make" | "model" | "body">): string {
  const shape = BODY_WORDS[v.body] ?? "car";
  // L'orientation d'abord, et répétée : enfouie en milieu de phrase, le modèle ne la
  // suivait qu'une fois sur deux (constat du premier lot de rendus).
  // L'interdiction des emblèmes en tête, et formulée en geste concret : enfouie à la fin
  // (« no logos »), le modèle redessinait les logos de calandre une fois sur deux.
  return "IMPORTANT — NO EMBLEMS: remove every manufacturer emblem, badge and model lettering. " +
    "The grille, bonnet, wheels and tailgate are plain and smooth where a logo would be; " +
    "no letters or symbols anywhere on the car. " +
    "IMPORTANT — ORIENTATION: the car FACES LEFT. Its front bumper, grille and headlights are " +
    "on the LEFT side of the frame; its rear is on the RIGHT side. " +
    `Photorealistic photograph of a ${paintFor(v.id)} ${v.make} ${v.model}, ${shape}, ` +
    "seen from the FRONT-LEFT three-quarter angle, front of the car on the LEFT. " +
    // Le cadrage est le reproche du testeur : la voiture doit être entière, centrée, et
    // assez grande pour que l'app puisse remplir une carte sans rien couper.
    "Square composition. The WHOLE car is in frame and perfectly centred, occupying about 72% " +
    "of the image width, with a small even margin of studio around it; nothing of the car is cropped. " +
    "Camera slightly below the beltline. " +
    // Le décor est l'image fournie, et doit le rester : c'est ce qui rend toutes les
    // cartes du catalogue identiques en dehors de la voiture.
    "Place the car INSIDE THE PROVIDED STUDIO IMAGE, parked on its floor. Keep the studio exactly " +
    "as it is: same dark charcoal wall, same soft horizon, same floor, same soft overhead light and " +
    "the same pool of light on the floor. Do not add anything to the background: no neon, no coloured " +
    "lights, no light strips, no walls, no props. " +
    "The tyres rest firmly ON the floor, in the pool of light, with a dark natural contact shadow " +
    "right under each tyre, a soft ambient shadow under the body and a faint, soft reflection on the floor. " +
    "Crisp, clean key lighting that reveals the bodywork: every panel readable, " +
    "bright specular highlights along the shoulder line, detailed wheels and headlights. " +
    "High-end automotive product photography, extremely detailed, razor sharp, glossy paint. " +
    "No text, no badges, no logos, no licence plate, no people, no props.";
}

/// Le modèle demandé s'il est au catalogue embarqué ; sinon undefined. Un identifiant
/// inventé (ou un chemin) ne peut donc rien faire générer ni lire dans le compartiment.
export function allowedArtVehicle(vehicleId: string): Vehicle | undefined {
  return vehicle(vehicleId);
}
