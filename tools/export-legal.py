#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Exporte les documents légaux de l'app vers des pages web autonomes.

La source est le catalogue de traduction de l'app, et la liste des sections est
lue dans LegalDocument.swift : les pages en ligne ne peuvent donc pas diverger
de ce que lit l'utilisateur dans l'app. C'est tout l'intérêt.

  python3 tools/export-legal.py
"""
import json, os, re, sys, html
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Spog", "Localizable.xcstrings")
SWIFT = os.path.join(ROOT, "Spog", "Settings", "LegalDocument.swift")
OUTDIR = os.path.join(ROOT, "Legal")

# Nom de fichier par document et par langue : des URL lisibles dans chaque langue.
FILENAMES = {
    ("privacy", "fr"): "confidentialite.html", ("privacy", "en"): "privacy.html",
    ("terms",   "fr"): "conditions.html",      ("terms",   "en"): "terms.html",
}
LANG_NAMES = {"fr": "Français", "en": "English"}


def read_sections():
    """Récupère l'ordre des sections depuis le code Swift, pas d'une copie."""
    source = open(SWIFT, encoding="utf-8").read()
    documents = {}
    for match in re.finditer(r'id:\s*"(\w+)",(.*?)sections:\s*\[(.*?)\]\)', source, re.S):
        doc_id, head, body = match.groups()
        title = re.search(r'title:\s*"([^"]+)"', head).group(1)
        keys = re.findall(r'"([\w.]+)"', body)
        documents[doc_id] = {"title_key": title, "sections": keys}
    if not documents:
        sys.exit("Aucun document trouvé dans LegalDocument.swift")
    return documents


def value(strings, key, lang):
    entry = strings.get(key)
    if not entry:
        sys.exit(f"Clé absente du catalogue : {key}")
    unit = entry["localizations"].get(lang, {}).get("stringUnit")
    if not unit:
        sys.exit(f"Traduction {lang} manquante pour : {key}")
    return unit["value"]


PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index, follow">
<title>{title} — Spog</title>
<style>
  :root {{ color-scheme: dark; --bg:#07060B; --surface:#100E17; --line:rgba(255,255,255,.08);
           --text:#F3F1F8; --muted:#9A94AE; --dim:#5D5872; --accent:#C98BFF; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--text);
          font:16px/1.65 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif;
          padding:0 20px 80px; }}
  .wrap {{ max-width:720px; margin:0 auto; }}
  header {{ padding:56px 0 28px; border-bottom:1px solid var(--line); margin-bottom:36px; }}
  .brand {{ display:flex; align-items:center; gap:10px; margin-bottom:26px; }}
  .dot {{ width:9px; height:9px; border-radius:50%;
          background:linear-gradient(160deg,var(--accent),#5B21B6);
          box-shadow:0 0 14px rgba(201,139,255,.75); }}
  .brand span {{ font-weight:800; letter-spacing:.28em; font-size:14px; }}
  h1 {{ font-size:clamp(28px,5vw,40px); line-height:1.15; margin:0 0 12px; letter-spacing:-.02em; }}
  .updated {{ color:var(--dim); font-size:13px;
              font-family:ui-monospace,SFMono-Regular,Menlo,monospace; margin:0; }}
  section {{ margin-bottom:34px; }}
  h2 {{ font-size:19px; margin:0 0 10px; color:var(--text); letter-spacing:-.01em; }}
  p {{ margin:0; color:var(--muted); }}
  footer {{ margin-top:56px; padding-top:26px; border-top:1px solid var(--line);
            color:var(--dim); font-size:13px; display:flex; flex-wrap:wrap;
            gap:8px 18px; align-items:center; }}
  footer a {{ color:var(--accent); text-decoration:none; }}
  footer a:hover {{ text-decoration:underline; }}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="brand"><span class="dot"></span><span>SPOG</span></div>
    <h1>{title}</h1>
    <p class="updated">{updated}</p>
  </header>
  {sections}
  <footer>
    <span>{publisher}</span>
    <a href="mailto:app@mandalore-group.com">app@mandalore-group.com</a>
    {others}
  </footer>
</div>
</body>
</html>
"""


def main():
    strings = json.load(open(CATALOG, encoding="utf-8"))["strings"]
    documents = read_sections()
    os.makedirs(OUTDIR, exist_ok=True)
    written = []

    for doc_id, spec in documents.items():
        for lang in ("fr", "en"):
            body = "\n  ".join(
                "<section><h2>{}</h2><p>{}</p></section>".format(
                    html.escape(value(strings, key + ".title", lang)),
                    html.escape(value(strings, key + ".body", lang)))
                for key in spec["sections"])

            # Liens croisés : l'autre document, et l'autre langue.
            links = []
            for other_id, other_spec in documents.items():
                if other_id == doc_id: continue
                links.append('<a href="{}">{}</a>'.format(
                    FILENAMES[(other_id, lang)],
                    html.escape(value(strings, other_spec["title_key"], lang))))
            other_lang = "en" if lang == "fr" else "fr"
            links.append('<a href="{}">{}</a>'.format(
                FILENAMES[(doc_id, other_lang)], LANG_NAMES[other_lang]))

            page = PAGE.format(
                lang=lang,
                title=html.escape(value(strings, spec["title_key"], lang)),
                updated=html.escape(value(strings, "legal.updated", lang)),
                publisher=html.escape(value(strings, "settings.publisher", lang)),
                sections=body,
                others="\n    ".join(links))

            name = FILENAMES[(doc_id, lang)]
            open(os.path.join(OUTDIR, name), "w", encoding="utf-8").write(page)
            written.append(name)

    print(f"{len(written)} pages écrites dans {OUTDIR}")
    for name in sorted(written):
        size = os.path.getsize(os.path.join(OUTDIR, name))
        print(f"  {name:24} {size // 1024 or 1} Ko")


if __name__ == "__main__":
    main()
