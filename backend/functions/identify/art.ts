// Visuel stylisé d'une cible du pack de primes (action `vehicle_art`).
//
// Pourquoi : le pack annonce trois voitures à chasser, mais montrait la même silhouette
// pour les trois. Le joueur devait aller chercher ailleurs à quoi ressemble une
// « Alfa 8C » avant de pouvoir la repérer dans la rue. Un rendu studio par cible règle ça.
//
// Le rendu est généré UNE fois par modèle, puis rangé dans le compartiment privé `art` :
// tous les joueurs de tous les pays partagent la même image, le coût (≈1,4 centime) est
// payé une fois par modèle et jamais par joueur.
//
// **Anti-abus.** L'URL de la fonction est publique. Sans garde, n'importe qui ferait
// générer les 867 modèles du catalogue à nos frais. On n'accepte donc que les modèles qui
// sont une cible de la semaine en cours pour au moins un pays connu de `markets.json` :
// au pire quelques centaines de rendus par semaine, la plupart déjà en cache.

import { createHash } from "node:crypto";
import { weeklyBounties, currentWeek } from "./bounty";
import { vehicle, type Vehicle } from "./catalog";
import marketsFile from "../../../Spog/Catalog/markets.json";

export const ART_MODEL = "gpt-image-1-mini";
export const ART_URL = "https://api.openai.com/v1/images/generations";

/// Clé de l'objet en cache. L'identifiant vient du catalogue (vérifié avant), jamais
/// directement du client : pas de chemin arbitraire possible dans le compartiment.
export function artKey(vehicleId: string): string {
  return `vehicles/${vehicleId}.jpg`;
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

/// Même gabarit que les rendus studio de `CarArt` (supabase/functions/render) : c'est
/// l'unité de style qui fait tenir la collection. Ni logo, ni plaque, ni texte — on ne
/// reproduit pas de marque déposée.
export function artPrompt(v: Pick<Vehicle, "id" | "make" | "model" | "body">): string {
  const shape = BODY_WORDS[v.body] ?? "car";
  // L'orientation d'abord, et répétée : enfouie en milieu de phrase, le modèle ne la
  // suivait qu'une fois sur deux (constat du premier lot de rendus).
  return "IMPORTANT — ORIENTATION: the car FACES LEFT. Its front bumper, grille and headlights are " +
    "on the LEFT side of the frame; its rear is on the RIGHT side. " +
    `Photorealistic photograph of a ${paintFor(v.id)} ${v.make} ${v.model}, ${shape}, ` +
    "in a dark studio, seen from the FRONT-LEFT three-quarter angle, front of the car on the LEFT. " +
    "Camera slightly below the beltline, the whole car in frame with room around it. " +
    "The car is brightly and evenly lit by a large soft key light, every panel readable, " +
    "bright specular highlights along the shoulder line. " +
    "Subtle violet and cyan neon strips glow on the wall behind, mirrored on a polished dark floor, " +
    "staying in the background and never outshining the car. " +
    "High-end automotive product photography, razor sharp, glossy paint. " +
    "No text, no badges, no logos, no licence plate, no people, no props. " +
    "Wide landscape composition, the car filling most of the width, front pointing LEFT.";
}

/// Tous les pays connus de `markets.json`. Le pack accepte n'importe quel code pays, mais
/// l'app ne propose que ceux-là : borner la vérification ici borne aussi le coût.
export const ART_COUNTRIES: string[] = Object.values(
  (marketsFile as { regions: Record<string, string[]> }).regions).flat();

let cachedWeek = "";
let cachedTargets = new Set<string>();

/// Les modèles qui sont une cible cette semaine, quelque part. Recalculé une fois par
/// semaine et par instance : le tirage est déterministe, il n'y a rien à stocker.
export function weeklyTargetIds(now = new Date()): Set<string> {
  const week = currentWeek(now);
  if (week !== cachedWeek) {
    const ids = new Set<string>();
    for (const country of ART_COUNTRIES) {
      for (const target of weeklyBounties(week, country)) ids.add(target.vehicle.id);
    }
    cachedTargets = ids;
    cachedWeek = week;
  }
  return cachedTargets;
}

/// Le modèle demandé, s'il a le droit d'être rendu cette semaine ; sinon undefined.
export function allowedArtVehicle(vehicleId: string, now = new Date()): Vehicle | undefined {
  if (!weeklyTargetIds(now).has(vehicleId)) return undefined;
  return vehicle(vehicleId);
}
