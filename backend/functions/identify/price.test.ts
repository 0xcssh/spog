import { test, describe } from "node:test";
import assert from "node:assert/strict";
import marketsFile from "../../../Spog/Catalog/markets.json";
import { currencyOf, knownCurrencyCountries, priceBracket, PRICE_MAX_USD } from "./price";

const allCountries = Object.values((marketsFile as { regions: Record<string, string[]> }).regions).flat();

describe("devise du pays", () => {
  // Un pays ajouté à une région sans sa devise n'aurait jamais de cote, et rien ne le
  // signalerait : ni erreur, ni journal. Ce test est le seul garde-fou.
  test("chaque pays de markets.json a une devise", () => {
    const missing = allCountries.filter((c) => currencyOf(c) === null);
    assert.deepEqual(missing, []);
  });

  test("aucune devise pour un pays absent des régions", () => {
    const orphans = knownCurrencyCountries().filter((c) => !allCountries.includes(c));
    assert.deepEqual(orphans, []);
  });

  // Une coquille (« EUE ») ferait planter le formatage côté app ou afficher un code brut.
  test("chaque devise est un code ISO 4217 que le moteur Intl connaît", () => {
    const valid = new Set(Intl.supportedValuesOf("currency"));
    const unknown = allCountries.map((c) => currencyOf(c)!).filter((code) => !valid.has(code));
    assert.deepEqual(unknown, []);
  });

  test("quelques pays témoins, sur plusieurs continents", () => {
    assert.equal(currencyOf("FR"), "EUR");
    assert.equal(currencyOf("gb"), "GBP");
    assert.equal(currencyOf(" US "), "USD");
    assert.equal(currencyOf("JP"), "JPY");
    assert.equal(currencyOf("TH"), "THB");
    assert.equal(currencyOf("SN"), "XOF");
  });

  test("pays absent, mal formé ou inconnu : pas de devise, jamais un défaut", () => {
    for (const value of [undefined, null, "", "ZZ", "FRA", "F", 33, {}]) {
      assert.equal(currencyOf(value), null);
    }
  });
});

describe("garde-fous de la fourchette", () => {
  const ok = { price_min: 18_000, price_max: 24_000, price_max_usd: 26_000 };
  const empty = (currency: string) => ({ price_min: 0, price_max: 0, price_currency: currency });

  test("une fourchette honnête passe telle quelle, arrondie", () => {
    assert.deepEqual(priceBracket({ ...ok, price_min: 17_999.6 }, "EUR", 0.9),
                     { price_min: 18_000, price_max: 24_000, price_currency: "EUR" });
  });

  test("sans devise (pas de pays) : rien, devise vide", () => {
    assert.deepEqual(priceBracket(ok, null, 0.9), empty(""));
  });

  test("confiance sous 0,7 : rien", () => {
    assert.deepEqual(priceBracket(ok, "EUR", 0.69), empty("EUR"));
    assert.equal(priceBracket(ok, "EUR", 0.7).price_min, 18_000);
  });

  test("bornes nulles, négatives, absentes ou illisibles : rien", () => {
    assert.deepEqual(priceBracket({ ...ok, price_min: 0 }, "EUR", 0.9), empty("EUR"));
    assert.deepEqual(priceBracket({ ...ok, price_min: -5 }, "EUR", 0.9), empty("EUR"));
    assert.deepEqual(priceBracket({ price_max: 24_000, price_max_usd: 26_000 }, "EUR", 0.9), empty("EUR"));
    assert.deepEqual(priceBracket({ ...ok, price_max: "beaucoup" }, "EUR", 0.9), empty("EUR"));
  });

  test("fourchette inversée : rien", () => {
    assert.deepEqual(priceBracket({ ...ok, price_min: 24_000, price_max: 18_000 }, "EUR", 0.9), empty("EUR"));
  });

  test("plus serrée que ±10 % de son centre : fausse précision, refusée", () => {
    assert.deepEqual(priceBracket({ ...ok, price_min: 20_000, price_max: 22_000 }, "EUR", 0.9), empty("EUR"));
    // Exactement ±10 % : la limite passe.
    assert.equal(priceBracket({ ...ok, price_min: 18_000, price_max: 22_000 }, "EUR", 0.9).price_min, 18_000);
  });

  test("plafond de trois millions, mesuré en dollars quelle que soit la devise", () => {
    assert.deepEqual(priceBracket({ ...ok, price_max_usd: PRICE_MAX_USD + 1 }, "EUR", 0.9), empty("EUR"));
    // Trois millions de yens, c'est une citadine : le plafond ne s'applique pas au montant local.
    const yen = { price_min: 2_000_000, price_max: 3_500_000, price_max_usd: 23_000 };
    assert.deepEqual(priceBracket(yen, "JPY", 0.9),
                     { price_min: 2_000_000, price_max: 3_500_000, price_currency: "JPY" });
  });

  test("sans équivalent en dollars, le plafond est invérifiable : rien", () => {
    assert.deepEqual(priceBracket({ price_min: 18_000, price_max: 24_000 }, "EUR", 0.9), empty("EUR"));
  });
});
