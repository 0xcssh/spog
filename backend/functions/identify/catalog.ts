// Le catalogue, côté serveur : rapprochement du texte de l'IA, propositions, rareté.
//
// Portage fidèle de `Spog/Catalog/CatalogStore.swift`, sur LES MÊMES fichiers JSON : ils
// sont lus dans `Spog/Catalog/` et embarqués au build, il n'en existe aucune copie.
// Pourquoi le serveur s'en mêle désormais : les classements. Tant que les points restaient
// sur l'appareil, l'app pouvait les calculer seule ; dès qu'ils se comparent entre joueurs,
// c'est le serveur qui doit les compter, sinon n'importe qui s'en attribue.
//
// Conséquence assumée : changer l'équilibre du jeu demande désormais un redéploiement du
// backend en plus d'une version de l'app. Les deux lisent les mêmes fichiers, ils ne
// peuvent donc pas diverger — seulement être déployés à des moments différents.
//
// ⚠️ Toute retouche des règles de `CatalogStore.swift` doit être reportée ici ; les tests
// de catalog.test.ts reprennent les mêmes cas que CatalogMatchingTests et RealWorldMatchingTests.

import vehiclesFile from "../../../Spog/Catalog/vehicles.json";
import rarityFile from "../../../Spog/Catalog/rarity.json";
import marketsFile from "../../../Spog/Catalog/markets.json";

export interface Vehicle {
  id: string;
  make: string;
  model: string;
  body: string;
  rarity: Record<string, string>;
  aliases: string[];
}

export interface Tier { id: string; rank: number; points: number }

const fullName = (v: Vehicle) => `${v.make} ${v.model}`;

export const vehicles: Vehicle[] = (vehiclesFile as { vehicles: Vehicle[] }).vehicles;
export const tiers: Tier[] = (rarityFile as { tiers: Tier[] }).tiers.slice().sort((a, b) => a.rank - b.rank);
export const unknownTier: Tier = { id: rarityFile.unknown.id, rank: -1, points: rarityFile.unknown.points };
export const confidenceThreshold: number = rarityFile.confidence_threshold;

const tierById = new Map(tiers.map((t) => [t.id, t]));
const vehicleById = new Map(vehicles.map((v) => [v.id, v]));
const regionOfCountry = new Map<string, string>();
for (const [region, countries] of Object.entries((marketsFile as { regions: Record<string, string[]> }).regions)) {
  for (const country of countries) regionOfCountry.set(country, region);
}

// MARK: Normalisation — mêmes règles que CatalogStore.normalize / stripNoise / containsWord

export function normalize(text: string): string {
  const folded = text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
  let cleaned = "";
  for (const ch of folded) cleaned += /[a-z]/.test(ch) || /\p{N}/u.test(ch) ? ch : " ";
  return cleaned.split(" ").filter(Boolean).join(" ");
}

/// Retire les jetons de génération : chiffres romains, mk4, années, codes châssis.
export function stripNoise(normalized: string): string {
  return normalized.split(" ").filter((t) =>
    !/^mk\d+$/.test(t) && !/^[ivx]{1,4}$/.test(t) && !/^(19|20)\d{2}$/.test(t) && !/^[a-z]\d{2,3}$/.test(t),
  ).join(" ");
}

export function containsWord(needle: string, haystack: string): boolean {
  const at = haystack.indexOf(needle);
  if (at < 0) return false;
  const before = at === 0 ? " " : haystack[at - 1];
  const after = at + needle.length === haystack.length ? " " : haystack[at + needle.length];
  return before === " " && after === " ";
}

export function slug(text: string): string {
  return normalize(text).split(" ").join("-");
}

// MARK: Rapprochement

const matchIndex = new Map<string, Vehicle>();
for (const v of vehicles) {
  const keys = [normalize(fullName(v)), normalize(v.model)];
  for (const alias of v.aliases) {
    keys.push(normalize(`${v.make} ${alias}`));
    keys.push(normalize(alias));
  }
  keys.push(stripNoise(normalize(fullName(v))));
  for (const key of keys) if (key && !matchIndex.has(key)) matchIndex.set(key, v);
}

export function match(text: string): Vehicle | null {
  const target = normalize(text);
  const exact = matchIndex.get(target);
  if (exact) return exact;
  const loose = matchIndex.get(stripNoise(target));
  if (loose) return loose;
  // Repli : la clé la plus longue présente comme mots entiers dans le texte.
  let best: [number, Vehicle] | null = null;
  for (const [key, v] of matchIndex) {
    if (key.length < 3 || !containsWord(key, target)) continue;
    if (!best || key.length > best[0]) best = [key.length, v];
  }
  return best ? best[1] : null;
}

/// Propositions classées pour un texte libre : même score que l'écran de confirmation.
export function candidates(text: string, limit = 5): Vehicle[] {
  const words = new Set(normalize(text).split(" ").filter(Boolean));
  if (words.size === 0) return [];
  const scored: [number, Vehicle][] = [];
  for (const v of vehicles) {
    const keys = [fullName(v), ...v.aliases.map((a) => `${v.make} ${a}`), v.model];
    let best = 0;
    for (const key of keys) {
      const tokens = new Set(normalize(key).split(" ").filter(Boolean));
      if (tokens.size === 0) continue;
      let shared = 0;
      for (const t of tokens) if (words.has(t)) shared++;
      if (shared === 0) continue;
      best = Math.max(best, shared / tokens.size + shared / words.size);
    }
    if (best > 0) scored.push([best, v]);
  }
  const ordered = scored.sort((a, b) => b[0] - a[0]).map(([, v]) => v);
  const exact = match(text);
  if (exact) {
    const at = ordered.indexOf(exact);
    if (at >= 0) ordered.splice(at, 1);
    ordered.unshift(exact);
  }
  return ordered.slice(0, limit);
}

/// Le modèle qu'une identification désigne, comme l'app le retient : le texte complet,
/// puis marque + modèle, sinon l'identifiant que l'app donnerait au modèle appris.
export function expectedVehicleId(make: string, model: string, generation: string): string {
  const full = [make, model, generation].filter(Boolean).join(" ");
  return match(full)?.id ?? match(`${make} ${model}`)?.id ?? slug(`${make} ${model}`);
}

// MARK: Rareté — cascade pays exact → région → repli mondial

export function tierOf(id: string | undefined): Tier {
  return (id && tierById.get(id)) || unknownTier;
}

export function resolve(vehicleId: string, country: string): Tier {
  const v = vehicleById.get(vehicleId);
  // Un modèle appris par l'app n'est pas au catalogue : son palier est inconnu, comme côté app.
  if (!v) return unknownTier;
  if (v.rarity[country]) return tierOf(v.rarity[country]);
  const region = regionOfCountry.get(country);
  if (region && v.rarity[region]) return tierOf(v.rarity[region]);
  return tierOf(v.rarity["default"] ?? "unknown");
}

export function regionOf(country: string): string | undefined {
  return regionOfCountry.get(country);
}

export function vehicle(id: string): Vehicle | undefined {
  return vehicleById.get(id);
}
