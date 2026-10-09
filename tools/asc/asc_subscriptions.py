#!/usr/bin/env python3
"""Crée les abonnements Spog Pro dans App Store Connect.

Lancé par la CI (.github/workflows/asc-subscriptions.yml), avec la clé API App Store
Connect rangée dans les secrets du dépôt : la clé ne passe jamais par un poste.
Idempotent : ce qui existe déjà (groupe, produit, textes, disponibilité, prix, essai)
n'est pas touché, une relance ne fait que combler les manques. Repris du script de
Dunk It (même compte de développeur, même méthode).

Ce qu'il crée : un groupe « Spog Pro », deux abonnements auto-renouvelables, aux
identifiants que l'app attend déjà (Spog/Settings/SubscriptionStore.swift) :
  com.mandaloregroup.spog.premium.yearly    1 an     essai gratuit de 3 jours
  com.mandaloregroup.spog.premium.monthly   1 mois   sans essai

Prix (PLAN.md : 7 €/mois, 60 €/an) : paliers Apple 6,99 € et 59,99 € dans la zone
euro ; 6,99 $ et 59,99 $ aux États-Unis, et l'équivalent calculé par Apple ailleurs.

La capture d'écran de revue (le paywall réel) est facultative ici : sans elle, les
produits restent « Missing Metadata » jusqu'à son ajout (relancer le script une fois
tools/asc/review_paywall.png déposée).

Env : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM), BUNDLE_ID, DRY_RUN.
"""
import hashlib
import os
import pathlib
import sys
import time

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
P8 = os.environ["ASC_KEY_P8"]
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.mandalore-group.spog")
DRY = os.environ.get("DRY_RUN", "0") == "1"
BASE = "https://api.appstoreconnect.apple.com"
GROUP = "Spog Pro"
REVIEW_SHOT = pathlib.Path(__file__).resolve().parent / "review_paywall.png"

EURO = ["AUT", "BEL", "CYP", "DEU", "ESP", "EST", "FIN", "FRA", "GRC", "HRV",
        "IRL", "ITA", "LTU", "LUX", "LVA", "MLT", "NLD", "PRT", "SVK", "SVN"]

# identifiant, nom de référence, période, niveau dans le groupe, essai, USD, EUR
PRODUCTS = [
    ("com.mandaloregroup.spog.premium.yearly", "Spog Pro Yearly", "ONE_YEAR", 1, True, "59.99", "59.99"),
    ("com.mandaloregroup.spog.premium.monthly", "Spog Pro Monthly", "ONE_MONTH", 2, False, "6.99", "6.99"),
]

# Ce que l'App Store affiche dans la feuille d'abonnement et dans les Réglages.
# Nom ≤ 30 caractères, description ≤ 45.
GROUP_NAMES = {"en-US": "Spog Pro", "fr-FR": "Spog Pro"}
SUB_TEXT = {
    "ONE_YEAR": {
        "en-US": ("Spog Pro – Yearly", "Unlimited spotting, no ads"),
        "fr-FR": ("Spog Pro – Annuel", "Repérages illimités, sans pub"),
    },
    "ONE_MONTH": {
        "en-US": ("Spog Pro – Monthly", "Unlimited spotting, no ads"),
        "fr-FR": ("Spog Pro – Mensuel", "Repérages illimités, sans pub"),
    },
}


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      P8, algorithm="ES256", headers={"kid": KEY_ID})


def call(method, path, body=None, params=None):
    url = path if path.startswith("http") else BASE + path
    for attempt in range(5):
        r = requests.request(method, url, json=body, params=params,
                             headers={"Authorization": f"Bearer {token()}"}, timeout=120)
        if r.status_code == 429:
            time.sleep(10 * (attempt + 1))
            continue
        if r.status_code >= 400:
            raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:900]}")
        return r.json() if r.text else {}
    raise RuntimeError(f"{method} {path}: rate limited")


def get_all(path, params=None):
    out, included = [], []
    page = call("GET", path, params=dict(params or {}, limit=200))
    while True:
        out += page.get("data", [])
        included += page.get("included", [])
        nxt = page.get("links", {}).get("next")
        if not nxt:
            return out, included
        page = call("GET", nxt)


def post(kind, attributes, relationships, label):
    print(f"    + {label}")
    if DRY:
        return {"id": f"dry-{kind}"}
    rels = {k: {"data": v} for k, v in relationships.items()}
    return call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": attributes,
                                                 "relationships": rels}})["data"]


def ref(kind, id_):
    return {"type": kind, "id": id_}


def price_point(sub_id, territory, price):
    points, _ = get_all(f"/v1/subscriptions/{sub_id}/pricePoints",
                        {"filter[territory]": territory})
    for p in points:
        if p["attributes"]["customerPrice"] == price:
            return p
    sys.exit(f"no {territory} price point at {price}")


def main():
    apps = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"no app with bundle id {BUNDLE_ID}")
    app_id = apps[0]["id"]
    print(f"app {app_id}")

    groups, _ = get_all(f"/v1/apps/{app_id}/subscriptionGroups")
    group = next((g for g in groups if g["attributes"]["referenceName"] == GROUP), None)
    if group is None:
        print(f"group {GROUP}: CREATE")
        group = post("subscriptionGroups", {"referenceName": GROUP}, {"app": ref("apps", app_id)}, GROUP)
    else:
        print(f"group {GROUP}: exists ({group['id']})")
    have_g = set()
    if not DRY or not group["id"].startswith("dry"):
        locs, _ = get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")
        have_g = {l["attributes"]["locale"] for l in locs}
    for locale, name in GROUP_NAMES.items():
        if locale not in have_g:
            post("subscriptionGroupLocalizations", {"locale": locale, "name": name},
                 {"subscriptionGroup": ref("subscriptionGroups", group["id"])}, f"group name {locale}")

    territories = [t["id"] for t in get_all("/v1/territories")[0]]
    print(f"{len(territories)} territories")

    existing = {}
    if not group["id"].startswith("dry"):
        subs, _ = get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptions")
        existing = {s["attributes"]["productId"]: s for s in subs}

    for product_id, ref_name, period, level, trial, usd, eur in PRODUCTS:
        print(f"{product_id}")
        sub = existing.get(product_id)
        if sub is None:
            sub = post("subscriptions", {"name": ref_name, "productId": product_id,
                                         "subscriptionPeriod": period, "groupLevel": level,
                                         "familySharable": False},
                       {"group": ref("subscriptionGroups", group["id"])}, "subscription")
        if DRY and sub["id"].startswith("dry"):
            print(f"    + localizations {sorted(SUB_TEXT[period])}, availability, "
                  f"prices {usd} USD / {eur} EUR" + (", 3-day free trial" if trial else ""))
            continue
        sid = sub["id"]

        locs, _ = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        have = {l["attributes"]["locale"] for l in locs}
        for locale, (name, desc) in SUB_TEXT[period].items():
            if locale not in have:
                post("subscriptionLocalizations", {"locale": locale, "name": name, "description": desc},
                     {"subscription": ref("subscriptions", sid)}, f"localization {locale}")

        try:
            avail = call("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability")["data"]
        except RuntimeError:
            avail = None
        if not avail:
            post("subscriptionAvailabilities", {"availableInNewTerritories": True},
                 {"subscription": ref("subscriptions", sid),
                  "availableTerritories": [ref("territories", t) for t in territories]},
                 f"available in {len(territories)} territories")

        prices, inc = get_all(f"/v1/subscriptions/{sid}/prices", {"include": "territory"})
        priced = {p["relationships"]["territory"]["data"]["id"] for p in prices
                  if p.get("relationships", {}).get("territory", {}).get("data")}
        if len(priced) < len(territories):
            base = price_point(sid, "USA", usd)
            eq, _ = get_all(f"/v1/subscriptionPricePoints/{base['id']}/equalizations",
                            {"include": "territory"})
            target = {"USA": base["id"]}
            for p in eq:
                t = p["relationships"]["territory"]["data"]["id"]
                target[t] = p["id"]
            for t in EURO:
                if t in target:
                    target[t] = price_point(sid, t, eur)["id"]
            todo = [t for t in target if t not in priced]
            print(f"    + prices for {len(todo)} territories ({usd} USD, {eur} EUR)")
            for t in todo:
                if not DRY:
                    call("POST", "/v1/subscriptionPrices", {"data": {
                        "type": "subscriptionPrices",
                        "attributes": {"preserveCurrentPrice": False},
                        "relationships": {
                            "subscription": {"data": ref("subscriptions", sid)},
                            "subscriptionPricePoint": {"data": ref("subscriptionPricePoints", target[t])},
                        }}})

        try:
            shot = call("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
        except RuntimeError:
            shot = None
        if not shot and not REVIEW_SHOT.exists():
            print("    ! review screenshot missing (tools/asc/review_paywall.png): product stays MISSING_METADATA")
        elif not shot:
            data = REVIEW_SHOT.read_bytes()
            print(f"    + review screenshot ({len(data)} bytes)")
            if not DRY:
                made = call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {
                    "type": "subscriptionAppStoreReviewScreenshots",
                    "attributes": {"fileName": REVIEW_SHOT.name, "fileSize": len(data)},
                    "relationships": {"subscription": {"data": ref("subscriptions", sid)}}}})["data"]
                for op in made["attributes"]["uploadOperations"]:
                    chunk = data[op["offset"]:op["offset"] + op["length"]]
                    headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
                    requests.request(op["method"], op["url"], data=chunk, headers=headers,
                                     timeout=300).raise_for_status()
                call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{made['id']}", {"data": {
                    "type": "subscriptionAppStoreReviewScreenshots", "id": made["id"],
                    "attributes": {"uploaded": True,
                                   "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})

        if trial:
            offers, _ = get_all(f"/v1/subscriptions/{sid}/introductoryOffers")
            if not offers:
                # One offer per territory: the API ties each to a territory.
                for t in territories:
                    if not DRY:
                        call("POST", "/v1/subscriptionIntroductoryOffers", {"data": {
                            "type": "subscriptionIntroductoryOffers",
                            "attributes": {"duration": "THREE_DAYS", "offerMode": "FREE_TRIAL",
                                           "numberOfPeriods": 1},
                            "relationships": {
                                "subscription": {"data": ref("subscriptions", sid)},
                                "territory": {"data": ref("territories", t)},
                            }}})
                print(f"    + 3-day free trial in {len(territories)} territories")
    if not group["id"].startswith("dry"):
        for s_ in get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptions")[0]:
            a = s_["attributes"]
            n_price = len(get_all(f"/v1/subscriptions/{s_['id']}/prices")[0])
            n_intro = len(get_all(f"/v1/subscriptions/{s_['id']}/introductoryOffers")[0])
            n_loc = len(get_all(f"/v1/subscriptions/{s_['id']}/subscriptionLocalizations")[0])
            try:
                rs = call("GET", f"/v1/subscriptions/{s_['id']}/appStoreReviewScreenshot").get("data") or {}
                shot_state = ((rs.get("attributes") or {}).get("assetDeliveryState") or {}).get("state")
            except RuntimeError:
                shot_state = None
            print(f"state {a['productId']}: {a.get('state')} · review shot {shot_state} · "
                  f"{a.get('subscriptionPeriod')} · "
                  f"level {a.get('groupLevel')} · {n_price} prices · {n_intro} intro offers · "
                  f"{n_loc} localizations")
    print("dry run, nothing written" if DRY else "done")


if __name__ == "__main__":
    main()
