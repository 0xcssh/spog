#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verifie l'integrite du catalogue. A relancer apres chaque ajout de vehicules.
   Usage: python3 tools/validate_catalog.py"""
import json, os, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def load(name):
    return json.load(open(os.path.join(ROOT, "Spog", "Catalog", name), encoding="utf-8"))

markets  = load("markets.json")
rarity   = load("rarity.json")
vehicles = load("vehicles.json")

tier_ids   = {t["id"] for t in rarity["tiers"]}
region_ids = set(markets["regions"])
errors, warnings = [], []

# -- pays: aucun code present dans deux regions, format ISO alpha-2 --
country_of = {}
for region, countries in markets["regions"].items():
    for code in countries:
        if len(code) != 2 or not code.isupper():
            errors.append(f"code pays invalide '{code}' dans {region} (attendu ISO alpha-2)")
        if code in country_of:
            errors.append(f"pays {code} present dans {country_of[code]} ET {region}")
        country_of[code] = region

# -- devises de la cote : un pays oublie ici n'aurait jamais de cote, sans aucune erreur
#    visible ; un code qui n'est pas un pays du fichier ne servirait a rien --
currencies = markets.get("currencies", {})
for code in country_of:
    if code not in currencies:
        errors.append(f"pays {code} sans devise dans 'currencies'")
for code, currency in currencies.items():
    if code not in country_of:
        errors.append(f"devise donnee pour un pays inconnu: {code}")
    if len(currency) != 3 or not currency.isalpha() or not currency.isupper():
        errors.append(f"devise invalide '{currency}' pour {code} (attendu ISO 4217)")

for region in markets["populated"]:
    if region not in region_ids:
        errors.append(f"region peuplee inconnue: {region}")

# -- vehicules --
ids, pairs = set(), {}
for veh in vehicles["vehicles"]:
    vid = veh["id"]
    if vid in ids:
        errors.append(f"identifiant duplique: {vid}")
    ids.add(vid)
    if vid != vid.lower() or " " in vid:
        errors.append(f"identifiant mal forme (minuscules et tirets attendus): {vid}")

    pair = (veh["make"].lower(), veh["model"].lower())
    if pair in pairs:
        errors.append(f"doublon marque+modele: {veh['make']} {veh['model']} ({vid} et {pairs[pair]})")
    pairs[pair] = vid

    rar = veh["rarity"]
    if "default" not in rar:
        errors.append(f"{vid}: cle 'default' manquante — indispensable comme repli mondial")
    for key, value in rar.items():
        if key != "default" and key not in region_ids and key not in country_of:
            errors.append(f"{vid}: marche inconnu '{key}'")
        if value not in tier_ids:
            errors.append(f"{vid}: rarete inconnue '{value}'")

    for alias in veh["aliases"]:
        if alias != alias.lower():
            warnings.append(f"{vid}: alias non normalise '{alias}' (minuscules attendues)")

if vehicles.get("count") != len(vehicles["vehicles"]):
    warnings.append(f"champ 'count' desynchronise ({vehicles.get('count')} vs {len(vehicles['vehicles'])})")

# -- rapport --
print(f"{len(vehicles['vehicles'])} vehicules · {len(country_of)} pays · {len(region_ids)} regions")
for w in warnings: print("  avertissement:", w)
for e in errors:   print("  ERREUR:", e)
if errors:
    print(f"\n{len(errors)} erreur(s). Catalogue invalide.")
    sys.exit(1)
print("\nCatalogue valide.")

# -- couverture: quelles marques, et ou la rarete reste au repli --
by_make = collections.Counter(v["make"] for v in vehicles["vehicles"])
print(f"{len(by_make)} marques. Top 10: " + ", ".join(f"{m} ({n})" for m, n in by_make.most_common(10)))
fallback = [v["id"] for v in vehicles["vehicles"] if set(v["rarity"]) == {"default"}]
print(f"{len(fallback)} vehicules sans reglage regional (meme rarete partout) — normal pour les voitures rares mondialement.")
