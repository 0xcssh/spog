// Le pack de primes de la semaine (REFONTE.md, « Social ») : chaque lundi, trois voitures
// à chasser dans la rue. Le pack ne donne jamais la voiture, il donne une mission.
//
// **Le même pack pour tout un pays.** Tous les joueurs d'un pays chassent les mêmes cibles
// la même semaine : le premier qui en trouve une prend le gros bonus. C'est ce qui fait du
// pack une course entre joueurs, et pas une liste de courses personnelle. (Le pays et non
// la ville : le serveur ne connaît pas encore la ville des prises.)
//
// Le tirage est **déterministe** (semaine + pays) : aucun stockage, le même pack se
// recalcule à l'identique partout, et personne ne peut le relancer pour tomber mieux.
// Les cibles suivent la rareté **locale** — une Clio n'est pas une prime à Paris.

import { createHash } from "node:crypto";
import { vehicles, resolve, type Vehicle, type Tier } from "./catalog";

/// Trois cibles de difficulté croissante, chacune tirée dans une bande de paliers : la
/// première se trouve dans la semaine, la dernière fait rêver. La plus rare est révélée en
/// dernier à l'ouverture.
export const BOUNTY_SLOTS: { tiers: string[]; bonusRatio: number }[] = [
  { tiers: ["regular", "notable"], bonusRatio: 2 },
  { tiers: ["notable", "rare"], bonusRatio: 2 },
  { tiers: ["rare", "exotic"], bonusRatio: 2 },
];
/// Le premier joueur du pays à trouver une cible gagne en plus ce multiple de sa valeur.
export const FIRST_HUNTER_RATIO = 3;

/// Lundi de la semaine en cours, en UTC (AAAA-MM-JJ) : la même borne que `current_week()`.
export function currentWeek(now = new Date()): string {
  const day = (now.getUTCDay() + 6) % 7;
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - day)).toISOString().slice(0, 10);
}

export interface BountyTarget {
  vehicle: Vehicle;
  tier: Tier;
  /// Points ajoutés à la prise d'une cible (en plus de la prise elle-même).
  bonus: number;
  /// Bonus supplémentaire du premier chasseur du pays.
  firstBonus: number;
}

/// Générateur pseudo-aléatoire reproductible : un SHA-256 de la graine, lu par tranches.
function seeded(seed: string) {
  let counter = 0;
  return () => {
    const digest = createHash("sha256").update(`${seed}:${counter++}`).digest();
    return digest.readUInt32BE(0) / 0x1_0000_0000;
  };
}

/// Les cibles de la semaine `week` (lundi, AAAA-MM-JJ) pour le pays `country`.
export function weeklyBounties(week: string, country: string): BountyTarget[] {
  const random = seeded(`bounty:${week}:${country}`);
  const taken = new Set<string>();
  const targets: BountyTarget[] = [];
  for (const slot of BOUNTY_SLOTS) {
    // Les modèles au catalogue dont la rareté locale tombe dans la bande ; à défaut (pays
    // peu calibré), n'importe quel modèle calibré, pour toujours rendre trois cibles.
    let pool = vehicles.filter((v) => !taken.has(v.id) && slot.tiers.includes(resolve(v.id, country).id));
    if (pool.length === 0) pool = vehicles.filter((v) => !taken.has(v.id) && resolve(v.id, country).id !== "unknown");
    if (pool.length === 0) continue;
    const vehicle = pool[Math.floor(random() * pool.length)];
    taken.add(vehicle.id);
    const tier = resolve(vehicle.id, country);
    targets.push({
      vehicle, tier,
      bonus: Math.round(tier.points * slot.bonusRatio),
      firstBonus: Math.round(tier.points * FIRST_HUNTER_RATIO),
    });
  }
  return targets;
}
