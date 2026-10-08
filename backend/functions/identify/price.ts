// La cote d'occasion : une fourchette, dans la devise du pays de la prise.
//
// Retirée le 28/09/2026 (commit d381c76), revenue le 08/10/2026 à la demande du client.
// Elle était alors en euros pour tout le monde, ce qui contredisait la règle fondatrice
// du projet : une Clio ne se revend pas au même prix à Lyon et à Bangkok, et un joueur
// thaïlandais n'a que faire d'un montant en euros. L'app envoie désormais le pays de la
// prise ; sans lui, pas de cote du tout plutôt qu'une cote d'un marché supposé.
//
// La devise vient de `markets.json` (`currencies`), pas d'une liste écrite ici : l'API
// `Intl` de JavaScript sait formater une devise mais ne dit pas laquelle a cours dans
// un pays, et deviner à partir d'une locale (« en-FR ») se trompe dès que la locale
// n'existe pas. Ajouter un pays reste donc ajouter une donnée.

import marketsFile from "../../../Spog/Catalog/markets.json";

const currencies: Record<string, string> =
  (marketsFile as { currencies?: Record<string, string> }).currencies ?? {};

/// Devise ISO 4217 du pays, ou null quand le pays est absent, mal formé ou inconnu du
/// catalogue. Null veut dire « pas de cote », jamais « euros par défaut ».
export function currencyOf(country: unknown): string | null {
  if (typeof country !== "string") return null;
  const code = country.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return null;
  return currencies[code] ?? null;
}

/// Pays connus de la table des devises (pour les tests).
export function knownCurrencyCountries(): string[] {
  return Object.keys(currencies);
}

/// En dessous, l'identification est trop incertaine pour que la cote d'un modèle
/// peut-être faux ait un sens. Le prompt le demande au modèle ; le serveur le vérifie,
/// parce qu'un modèle ne respecte pas toujours une consigne.
export const PRICE_MIN_CONFIDENCE = 0.7;

/// Plafond, exprimé en dollars par l'IA elle-même (`price_max_usd`). Au-delà de trois
/// millions, on sort du parc automobile qu'on croise dans la rue : c'est plus probablement
/// une hallucination qu'une Bugatti garée. Le plafond ne peut plus être un montant dans la
/// devise de la cote — trois millions de yens, c'est une citadine — et une table de taux
/// de change écrite ici serait fausse en quelques mois (livre libanaise, peso argentin).
/// L'équivalent en dollars sert UNIQUEMENT à ce contrôle et ne part jamais vers l'app.
export const PRICE_MAX_USD = 3_000_000;

/// Une fourchette plus serrée que ±10 % de son centre prétendrait une précision que la
/// photo ne contient pas : ni kilométrage, ni carnet d'entretien, ni état mécanique.
export const PRICE_MIN_SPREAD = 0.2;

/// Consigne ajoutée au message de l'utilisateur quand le pays est connu. Le prompt
/// système reste identique pour tous les pays : il décrit les champs, ce message-ci dit
/// de quel marché il s'agit.
export function marketHint(country: string, currency: string): string {
  return `Market for the price: country ${country}, currency ${currency}.`;
}

export interface PriceFields {
  price_min: number;
  price_max: number;
  price_currency: string;
}

/// Fourchette nettoyée avant de partir vers le téléphone. On refuse plus qu'on
/// n'accepte : rendre 0/0 est une réponse valable, l'app n'affiche alors rien, ce qui
/// vaut mieux qu'un chiffre que le joueur saura faux d'un coup d'œil.
///
/// `currency` est null quand le pays manque ou n'est pas au catalogue : la devise est
/// alors une chaîne vide, pour que le champ existe toujours sans rien affirmer.
export function priceBracket(parsed: Record<string, unknown>, currency: string | null,
                             confidence: number): PriceFields {
  const empty = { price_min: 0, price_max: 0, price_currency: currency ?? "" };
  if (!currency || confidence < PRICE_MIN_CONFIDENCE) return empty;
  const min = Math.round(Number(parsed.price_min) || 0);
  const max = Math.round(Number(parsed.price_max) || 0);
  const maxUSD = Number(parsed.price_max_usd) || 0;
  if (min <= 0 || max <= 0 || max < min) return empty;
  // Sans équivalent en dollars, impossible de vérifier le plafond : on n'affiche rien.
  if (maxUSD <= 0 || maxUSD > PRICE_MAX_USD) return empty;
  if (max - min < ((min + max) / 2) * PRICE_MIN_SPREAD) return empty;
  // Au-delà de ce que JSON et Swift (`Int` 64 bits) relisent sans perte : absurde de toute façon.
  if (max > Number.MAX_SAFE_INTEGER) return empty;
  return { price_min: min, price_max: max, price_currency: currency };
}
