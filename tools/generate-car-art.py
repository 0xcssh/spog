#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genere une illustration par vehicule du catalogue, dans un style unique.

La cle n'est jamais ecrite dans le code ni dans git : elle est lue dans
la variable OPENAI_API_KEY, sinon dans ~/.openai/api-key.

  python3 tools/generate-car-art.py --limit 8      # lot d'essai
  python3 tools/generate-car-art.py                # tout le catalogue
  python3 tools/generate-car-art.py --only porsche-911
"""
import argparse, base64, json, os, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Spog", "Catalog", "vehicles.json")
OUTDIR = os.path.join(ROOT, "Spog", "CarArt")
MODEL = "gpt-image-1"

# Un seul gabarit pour les 510 vehicules : c'est ce qui fait tenir la collection.
# Ni logo ni plaque : on ne reproduit pas de marque deposee.
PROMPT = (
    "Photorealistic studio photograph of a {paint} {make} {model}, {body}. "
    "Three-quarter front view, camera slightly below the beltline, car centred and complete in frame. "
    "Seamless dark charcoal studio backdrop, soft top-down spotlight pooling behind the car, "
    "subtle reflection on a polished dark floor, cool cinematic rim lighting along the shoulder line, "
    "glossy paint with crisp highlights. "
    "No text, no badges, no logos, no licence plate, no people, no props. "
    "Square composition, high-end automotive advertising look."
)

BODY_WORDS = {
    "hatch": "compact hatchback", "sedan": "four-door sedan", "suv": "SUV",
    "sport": "low sports car", "pickup": "pickup truck", "van": "panel van",
}

def api_key():
    key = os.environ.get("OPENAI_API_KEY")
    if key: return key.strip()
    path = os.path.expanduser("~/.openai/api-key")
    if os.path.exists(path):
        return open(path).read().strip()
    sys.exit("Cle absente. Mets-la dans ~/.openai/api-key ou exporte OPENAI_API_KEY.")

def generate(vehicle, key, paint="metallic silver"):
    slug = vehicle["id"] + "--" + paint.replace(" ", "-")
    dest = os.path.join(OUTDIR, slug + ".png")
    if os.path.exists(dest):
        return slug, "deja la"

    prompt = PROMPT.format(make=vehicle["make"], model=vehicle["model"],
                           body=BODY_WORDS.get(vehicle["body"], "car"),
                           paint=paint)
    payload = json.dumps({
        "model": MODEL, "prompt": prompt, "size": "1024x1024",
        "quality": "medium", "background": "transparent", "output_format": "png", "n": 1,
    }).encode()

    request = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=payload,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})

    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                data = json.load(response)
            open(dest, "wb").write(base64.b64decode(data["data"][0]["b64_json"]))
            return slug, "ok"
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(4 * (attempt + 1)); continue
            return slug, f"ERREUR {error.code} {error.read()[:160]!r}"
        except Exception as error:
            if attempt < 3:
                time.sleep(4 * (attempt + 1)); continue
            return slug, f"ERREUR {error}"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int)
    parser.add_argument("--only")
    parser.add_argument("--ids", help="identifiants separes par des virgules")
    parser.add_argument("--paint", default="metallic silver",
                        help="teinte de carrosserie, ex. \"racing green\"")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    os.makedirs(OUTDIR, exist_ok=True)
    vehicles = json.load(open(CATALOG, encoding="utf-8"))["vehicles"]
    if args.only:
        vehicles = [v for v in vehicles if v["id"] == args.only]
    if args.ids:
        wanted = {i.strip() for i in args.ids.split(",")}
        vehicles = [v for v in vehicles if v["id"] in wanted]
        missing = wanted - {v["id"] for v in vehicles}
        if missing:
            sys.exit("identifiants inconnus : " + ", ".join(sorted(missing)))
    suffix = "--" + args.paint.replace(" ", "-") + ".png"
    todo = [v for v in vehicles if not os.path.exists(os.path.join(OUTDIR, v["id"] + suffix))]
    if args.limit:
        todo = todo[:args.limit]

    print(f"{len(todo)} illustration(s) a generer — environ {len(todo) * 0.04:.2f} $")
    key, done, failed = api_key(), 0, 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for vid, status in pool.map(lambda v: generate(v, key, args.paint), todo):
            done += 1
            if status.startswith("ERREUR"): failed += 1
            print(f"  [{done}/{len(todo)}] {vid}: {status}")
    print(f"\nTermine. {done - failed} reussite(s), {failed} echec(s).")
    print(f"Fichiers dans {OUTDIR}")

if __name__ == "__main__":
    main()
