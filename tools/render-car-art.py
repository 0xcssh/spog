#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fabrique les illustrations de carte pour tout le catalogue.

La cle OpenAI n'est pas sur cette machine : elle vit chez Supabase. Ce script passe donc
par la fonction `render`, protegee par un secret partage lu dans ~/.spog/render-secret.

  python3 tools/render-car-art.py --limit 5      # lot d'essai
  python3 tools/render-car-art.py --ids toyota-corolla,ford-f-150
  python3 tools/render-car-art.py                # tout ce qui manque

Chaque image coute un appel de generation : le script affiche le compte avant de partir,
et n'ecrase jamais une illustration deja presente.
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Spog", "Catalog", "vehicles.json")
OUTDIR = os.path.join(ROOT, "Spog", "CarArt")
FIT = os.path.join(ROOT, "tools", "fit-car-art.swift")
ENDPOINT = "https://pymrhossbzvhsertjhtc.supabase.co/functions/v1/render"
ANON = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB5bXJob3Nz"
        "Ynp2aHNlcnRqaHRjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjgxNjAsImV4cCI6MjEwMDA0NDE2MH0."
        "0_MV0CDHLOB0_Topq5t-WdGfQiN5Cshz2V2BB5grSnk")


def secret():
    path = os.path.expanduser("~/.spog/render-secret")
    if not os.path.exists(path):
        sys.exit("Secret absent. Il doit se trouver dans ~/.spog/render-secret "
                 "et correspondre a RENDER_SECRET cote Supabase.")
    return open(path).read().strip()


def already_there(vid):
    return any(os.path.exists(os.path.join(OUTDIR, vid + ext)) for ext in (".jpg", ".png"))


def render(vehicle, token):
    vid = vehicle["id"]
    payload = json.dumps({"make": vehicle["make"], "model": vehicle["model"],
                          "body": vehicle["body"], "paint": "metallic silver"}).encode()
    request = urllib.request.Request(
        ENDPOINT, data=payload,
        headers={"Authorization": f"Bearer {ANON}", "Content-Type": "application/json",
                 "x-render-secret": token})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        return vid, f"ERREUR {error.code} {error.read()[:120]!r}"
    except Exception as error:
        return vid, f"ERREUR {error}"

    raw = os.path.join(tempfile.gettempdir(), vid + "-raw.png")
    open(raw, "wb").write(base64.b64decode(data["image"]))
    out = os.path.join(OUTDIR, vid + ".jpg")
    result = subprocess.run(["xcrun", "swift", FIT, raw, out],
                            capture_output=True, text=True)
    os.remove(raw)
    if result.returncode != 0:
        return vid, "ERREUR cadrage " + result.stderr.strip()[:120]
    return vid, f"ok ({os.path.getsize(out) // 1024} Ko)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int)
    parser.add_argument("--ids", help="identifiants separes par des virgules")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--yes", action="store_true", help="ne pas demander confirmation")
    args = parser.parse_args()

    os.makedirs(OUTDIR, exist_ok=True)
    vehicles = json.load(open(CATALOG, encoding="utf-8"))["vehicles"]
    if args.ids:
        wanted = {i.strip() for i in args.ids.split(",")}
        vehicles = [v for v in vehicles if v["id"] in wanted]
    todo = [v for v in vehicles if not already_there(v["id"])]
    # `--limit 0` doit vouloir dire « rien », pas « tout » : la nuance coute cher
    # quand chaque element du lot est une generation d'image facturee.
    if args.limit is not None:
        todo = todo[:args.limit]
    if not todo:
        print("Rien a generer : tout est deja illustre.")
        return

    print(f"{len(todo)} illustration(s) a generer, une generation d'image chacune.")
    if not args.yes:
        if input("Continuer ? [o/N] ").strip().lower() not in ("o", "oui", "y", "yes"):
            sys.exit("Annule.")

    token, done, failed = secret(), 0, 0
    start = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for vid, status in pool.map(lambda v: render(v, token), todo):
            done += 1
            if status.startswith("ERREUR"):
                failed += 1
            print(f"  [{done}/{len(todo)}] {vid}: {status}")
    print(f"\nTermine en {(time.time() - start) / 60:.0f} min. "
          f"{done - failed} reussite(s), {failed} echec(s).")


if __name__ == "__main__":
    main()
