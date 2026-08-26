#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Demonstration du moteur de rapprochement et de rarete.
   Sert de reference pour l'implementation Swift.
   Usage: python3 tools/lookup_demo.py ["texte renvoye par l'IA"] [CODE_PAYS]"""
import json, os, re, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load = lambda n: json.load(open(os.path.join(ROOT, "Spog", "Catalog", n), encoding="utf-8"))
markets, rarity, catalog = load("markets.json"), load("rarity.json"), load("vehicles.json")

REGION_OF = {c: r for r, cs in markets["regions"].items() for c in cs}
TIER = {t["id"]: t for t in rarity["tiers"]}

# Jetons de generation a ignorer: chiffres romains, mk4, annees, codes chassis
NOISE = re.compile(r"\b(mk ?\d+|[ivx]{1,4}|19\d{2}|20\d{2}|[a-z]\d{2,3}|gen ?\d+)\b")

def norm(text):
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()

def keys(veh):
    """Toutes les cles de rapprochement d'un vehicule, de la plus precise a la plus large."""
    full  = norm(f"{veh['make']} {veh['model']}")
    out = [full, norm(veh["model"])]
    for a in veh["aliases"]:
        out.append(norm(f"{veh['make']} {a}"))   # "honda fit"
        out.append(norm(a))                       # "fit"
    stripped = NOISE.sub(" ", full)
    out.append(re.sub(r"\s+", " ", stripped).strip())
    return [k for k in out if k]

def match(ai_text):
    target = norm(ai_text)
    loose  = re.sub(r"\s+", " ", NOISE.sub(" ", target)).strip()
    best = None
    for veh in catalog["vehicles"]:
        for rank, key in enumerate(keys(veh)):
            if key == target or key == loose:
                score = (0, rank, -len(key))
                if best is None or score < best[0]:
                    best = (score, veh)
    if best: return best[1]
    # repli: la cle la plus longue presente comme mots entiers dans le texte de l'IA
    candidates = []
    for veh in catalog["vehicles"]:
        for key in keys(veh):
            if len(key) >= 3 and re.search(rf"\b{re.escape(key)}\b", target):
                candidates.append((len(key), veh))
    if candidates:
        return max(candidates, key=lambda c: c[0])[1]
    return None

def resolve(veh, country):
    """Cascade: pays exact -> region -> default."""
    rar = veh["rarity"]
    for step, source in ((country, "pays"), (REGION_OF.get(country), "region"), ("default", "repli mondial")):
        if step and step in rar:
            return rar[step], source, step
    return rar["default"], "repli mondial", "default"

def report(ai_text, country):
    veh = match(ai_text)
    if not veh:
        return f'  "{ai_text}" [{country}] -> inconnu, carte creee en rarete "unknown" ({rarity["unknown"]["points"]} pts)'
    tier, source, step = resolve(veh, country)
    t = TIER[tier]
    return (f'  "{ai_text}" [{country}] -> {veh["make"]} {veh["model"]} · '
            f'{t["id"]} ({t["points"]} pts) · via {source} "{step}"')

if len(sys.argv) > 1:
    print(report(sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "FR").upper()))
    sys.exit()

print("=== La meme voiture, vue depuis deux pays ===")
for text in ["Renault Clio IV", "Ford Mustang GT", "Volkswagen Golf", "Ford F-150",
             "Dacia Sandero", "Chevrolet Corvette C8", "Peugeot 205 GTI", "Toyota Corolla"]:
    for country in ("FR", "US"):
        print(report(text, country))
    print()

print("=== Rares partout, aucun reglage par pays necessaire ===")
for text in ["Ferrari F40", "Lamborghini Huracan", "Porsche 911 GT3 RS"]:
    print(report(text, "FR")); print(report(text, "JP"))

print("\n=== Pays jamais calibre: le repli mondial fait le travail ===")
for country in ("BR", "TH", "MA", "AU"):
    print(report("Renault Clio", country))

print("\n=== Texte libre de l'IA: variantes, casse, generations ===")
for text in ["renault clio", "CLIO 4", "Volkswagen Golf Mk7", "vauxhall corsa",
             "Honda Fit", "Mazda Miata", "Mercedes-Benz G-Class 2022", "Ferrari 250 GTO"]:
    print(report(text, "FR"))
