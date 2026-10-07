// Mêmes cas que CatalogMatchingTests, RealWorldMatchingTests et RarityTests côté Swift :
// le serveur compte désormais les points, il doit lire le catalogue exactement comme l'app.
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  normalize, stripNoise, match, candidates, resolve, regionOf, vehicles, unknownTier, expectedVehicleId, slug,
} from "./catalog";

describe("normalisation", () => {
  test("accents, casse et ponctuation ne comptent pas", () => {
    assert.equal(normalize("Citroën C3"), "citroen c3");
    assert.equal(normalize("MERCEDES-BENZ  Classe A"), "mercedes benz classe a");
    assert.equal(normalize("  Renault   Clio  "), "renault clio");
  });

  test("les jetons de génération disparaissent", () => {
    assert.equal(stripNoise("volkswagen golf mk7"), "volkswagen golf");
    assert.equal(stripNoise("renault clio iv"), "renault clio");
    assert.equal(stripNoise("peugeot 208 2019"), "peugeot 208");
    assert.equal(stripNoise("bmw serie 3 e90"), "bmw serie 3");
  });
});

describe("rapprochement", () => {
  test("les formes que l'IA produit vraiment retrouvent la bonne fiche", () => {
    for (const text of ["Renault Clio", "Renault Clio IV", "renault clio 2019", "RENAULT CLIO"]) {
      assert.equal(match(text)?.id, "renault-clio", text);
    }
  });

  // Réponses réelles du modèle, mesure du 28/09/2026 (RealWorldMatchingTests).
  const real: [string, string][] = [
    ["Toyota Aygo", "toyota-aygo"], ["BMW 1 Series", "bmw-serie-1"], ["Citroën C3", "citroen-c3"],
    ["Ford Fiesta", "ford-fiesta"], ["Porsche Macan", "porsche-macan"],
    ["Porsche Panamera Sport Turismo", "porsche-panamera"], ["Opel Meriva", "opel-meriva"],
    ["Peugeot 307 CC", "peugeot-307"], ["Lamborghini Urus", "lamborghini-urus"],
    ["Lamborghini Huracán Performante Spyder", "lamborghini-huracan"],
    ["Bentley Continental GT", "bentley-continental-gt"], ["Peugeot 3008", "peugeot-3008"],
    ["Mazda CX-3", "mazda-cx-3"],
  ];
  for (const [text, expected] of real) {
    test(`« ${text} » → ${expected}`, () => assert.equal(match(text)?.id, expected));
  }

  test("les modèles voisins ne se confondent pas", () => {
    assert.notEqual(match("Mazda CX-3")?.id, match("Mazda CX-30")?.id);
    assert.notEqual(match("Toyota Aygo")?.id, match("Toyota Aygo X")?.id);
    assert.equal(match("Citroen C3")?.id, "citroen-c3");
  });

  test("un texte qui ne ressemble à rien ne trouve rien", () => {
    assert.equal(match(""), null);
    assert.equal(match("xyzzy plover"), null);
  });

  test("chaque véhicule embarqué se retrouve par son propre nom", () => {
    for (const v of vehicles) assert.ok(match(`${v.make} ${v.model}`), `${v.make} ${v.model}`);
  });

  test("le rapprochement exact arrive en tête des propositions, le nom complet bat le modèle seul", () => {
    assert.equal(candidates("Renault Clio")[0]?.id, "renault-clio");
    assert.equal(candidates("Renault Clio IV", 3)[0]?.make, "Renault");
  });

  test("un modèle inconnu reçoit l'identifiant que l'app lui donnerait", () => {
    assert.equal(expectedVehicleId("Spog", "Imaginaire X1", ""), "spog-imaginaire-x1");
    assert.equal(expectedVehicleId("Renault", "Clio", "IV"), "renault-clio");
    assert.equal(slug("Lynk & Co 01"), "lynk-co-01");
  });
});

describe("rareté", () => {
  test("la France est rattachée à l'Europe de l'Ouest", () => {
    assert.equal(regionOf("FR"), "EU_WEST");
  });

  test("la même voiture ne vaut pas la même chose partout", () => {
    // L'intérêt du système : une Clio est banale en France, notable ailleurs.
    assert.ok(resolve("renault-clio", "FR").points < resolve("renault-clio", "VN").points ||
              resolve("renault-clio", "FR").points < resolve("renault-clio", "US").points);
  });

  test("un modèle appris (hors catalogue) vaut le palier inconnu", () => {
    assert.deepEqual(resolve("spog-imaginaire-x1", "VN"), unknownTier);
  });

  test("un pays hors découpage retombe sur le repli mondial", () => {
    const v = vehicles[0];
    assert.equal(resolve(v.id, "ZZ").id, v.rarity["default"]);
  });
});
