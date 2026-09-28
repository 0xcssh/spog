#!/usr/bin/env python3
"""Mesure la qualite reelle de l'identification sur des photos de rue.

Le seul chiffre qui compte avant une sortie, et qu'aucun test de simulateur ne
donne : sur trente vraies voitures photographiees par quelqu'un qui ne sait pas
ce que l'app attend, combien sont correctement nommees ?

Usage :
    python3 tools/score-identification.py photos/ --verite verite.csv
    python3 tools/score-identification.py photos/ --dry-run

`verite.csv` decrit ce qui est reellement sur chaque photo, une ligne par fichier :

    fichier,marque,modele,couleur
    IMG_0412.jpg,Renault,Clio,blue
    IMG_0413.jpg,Peugeot,208,white

Sans `--verite`, le script se contente d'afficher ce que l'IA repond : utile pour
un premier coup d'oeil, mais il ne mesure rien.

Chaque photo coute environ un demi-centime de dollar. Le script annonce la facture
et demande confirmation avant le premier appel.
"""
import argparse, base64, csv, io, json, os, sys, time
import urllib.request, urllib.error

ENDPOINT = "https://pymrhossbzvhsertjhtc.supabase.co/functions/v1/identify"
COST_PER_CALL = 0.005          # $ — mesure faite sur les reglages reels d'identify
EXTS = (".jpg", ".jpeg", ".png", ".heic")


def anon_key() -> str:
    """La cle publique de l'app, lue dans le code plutot que recopiee ici."""
    path = os.path.join(os.path.dirname(__file__), "..", "Spog", "Core", "BackendConfig.swift")
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            if "supabaseAnonKey" in line and '"' in line:
                return line.split('"')[1]
    sys.exit("Cle anonyme introuvable dans BackendConfig.swift")


def shrink(path: str, max_side: int = 1280, quality: int = 70) -> str:
    """Meme traitement que l'app : 1280 px, JPEG qualite 0.7.

    Tester sur des images plus grandes fausserait le resultat dans le bon sens —
    on mesurerait une qualite que le telephone n'envoie jamais.
    """
    out = "/tmp/spog-score.jpg"
    os.system(f'sips -Z {max_side} -s format jpeg -s formatOptions {quality} '
              f'"{path}" --out {out} >/dev/null 2>&1')
    with open(out, "rb") as handle:
        return base64.b64encode(handle.read()).decode()


def identify(image_b64: str, key: str, device: str) -> dict:
    payload = json.dumps({"imageBase64": image_b64}).encode()
    request = urllib.request.Request(ENDPOINT, data=payload, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
        "apikey": key,
        "x-device-id": device,
    })
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        return {"_erreur": f"HTTP {error.code}", "_detail": error.read().decode()[:200]}
    except Exception as error:                      # noqa: BLE001
        return {"_erreur": str(error)}


def normalise(text: str) -> str:
    return "".join(c for c in text.lower() if c.isalnum())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dossier")
    parser.add_argument("--verite", help="CSV decrivant ce qui est reellement sur chaque photo")
    parser.add_argument("--dry-run", action="store_true", help="n'appelle rien, annonce seulement la facture")
    parser.add_argument("--yes", action="store_true", help="ne pas demander confirmation")
    args = parser.parse_args()

    photos = sorted(f for f in os.listdir(args.dossier) if f.lower().endswith(EXTS))
    if not photos:
        sys.exit(f"Aucune photo dans {args.dossier}")

    print(f"{len(photos)} photos — coût estimé : ${len(photos) * COST_PER_CALL:.2f}")
    if args.dry_run:
        return
    if not args.yes:
        if input("Lancer ? [o/N] ").strip().lower() not in ("o", "oui", "y"):
            sys.exit("Annulé.")

    verite = {}
    if args.verite:
        with io.open(args.verite, encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                verite[row["fichier"]] = row

    key = anon_key()
    device = f"score-{int(time.time())}"
    lignes, bons, couleurs, refus = [], 0, 0, 0

    for name in photos:
        answer = identify(shrink(os.path.join(args.dossier, name)), key, device)
        if "_erreur" in answer:
            print(f"  ✘ {name:24s} {answer['_erreur']} {answer.get('_detail','')}")
            lignes.append((name, answer, None, None))
            continue

        lu = f"{answer.get('make','')} {answer.get('model','')}".strip()
        conf = answer.get("confidence", 0)
        if not answer.get("vehicle_present", True):
            refus += 1

        juste = couleur_juste = None
        if name in verite:
            attendu = f"{verite[name]['marque']} {verite[name]['modele']}"
            juste = normalise(lu) == normalise(attendu)
            bons += bool(juste)
            if verite[name].get("couleur"):
                couleur_juste = answer.get("color", "") == verite[name]["couleur"]
                couleurs += bool(couleur_juste)
            marque = "✔" if juste else "✘"
            print(f"  {marque} {name:24s} lu « {lu} » ({conf:.2f}) — attendu « {attendu} »")
        else:
            print(f"    {name:24s} lu « {lu} » ({conf:.2f}) couleur {answer.get('color','?')}")
        lignes.append((name, answer, juste, couleur_juste))
        time.sleep(0.4)          # on ne bouscule pas la fonction

    with io.open("resultats-identification.csv", "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["fichier", "marque_lue", "modele_lu", "couleur_lue", "carrosserie",
                         "confiance", "vehicule_present", "ecran", "correct", "couleur_correcte"])
        for name, a, juste, coul in lignes:
            writer.writerow([name, a.get("make", ""), a.get("model", ""), a.get("color", ""),
                             a.get("body", ""), a.get("confidence", ""),
                             a.get("vehicle_present", ""), a.get("is_screen", ""),
                             "" if juste is None else int(juste),
                             "" if coul is None else int(coul)])

    print(f"\nFacture réelle : ${len(photos) * COST_PER_CALL:.2f}")
    if verite:
        n = len([l for l in lignes if l[2] is not None])
        print(f"Identification correcte : {bons}/{n}  ({100*bons/max(n,1):.0f} %)")
        print(f"Couleur correcte        : {couleurs}/{n}  ({100*couleurs/max(n,1):.0f} %)")
    if refus:
        print(f"Photos où l'IA n'a vu aucun véhicule : {refus}")
    print("Détail dans resultats-identification.csv")


if __name__ == "__main__":
    main()
