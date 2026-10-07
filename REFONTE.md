# Spog — plan de refonte

*Rédigé le 07/10/2026.*

Ce fichier dit **vers quoi on reconstruit l'app, et dans quel ordre**. L'état actuel est dans
[PLAN.md](PLAN.md), les conventions dans [CLAUDE.md](CLAUDE.md) — elles restent valables,
la contrainte fondatrice en tête : rien de codé en dur, aucun pays supposé.

---

## Décisions arrêtées

| | Décision | Pourquoi |
|---|---|---|
| Techno | **Swift natif, SwiftUI** | Caméra, Vision et Core ML sont le cœur de l'app. Même choix que RepLock. |
| Méthode | **Celle de RepLock** : sans Mac, tout passe par la CI | Éprouvée de bout en bout sur RepLock, PodRadar et Dunk It, jusqu'à TestFlight. Voir plus bas. |
| Offre | **5 scans offerts**, puis abonnement | On garde l'offre actuelle : le joueur voit plusieurs cartes avant de payer. |
| Identification | **Appel IA + classifieur embarqué** | L'IA identifie tout dès le premier jour ; le classifieur prend le relais au fil des données et fait baisser le coût. |
| Backend | **Neon**, projet dédié `spog` (`damp-fire-11684360`) | Décidé le 07/10/2026 : même pile que Cyranox (Neon Functions + Postgres). L'ancien projet Supabase était partagé avec Cyranox, en plan gratuit, et bloqué depuis le 12/09/2026. |
| Compte Apple | **Mandalore LLC**, équipe `GXS33F5JT9` | Le compte de l'éditeur. Spog était signé avec une équipe personnelle gratuite. |

## La méthode RepLock, appliquée à Spog

Développement 100 % sous Windows. La boucle :

```
édition sous Windows ──► push GitHub ──► GitHub Actions (macOS) : tests + build signé
                                              │
                         ┌────────────────────┴────────────────────┐
                 export « debugging »                    export « app-store-connect »
                 IPA installée par USB                   envoi direct sur TestFlight
                 (pymobiledevice3, Python 3.12)
```

Ce qu'on reprend tel quel du dépôt RepLock :

- **XcodeGen** : un `project.yml` lisible remplace le `project.pbxproj`, qui n'est plus
  versionné. C'est ce qui rend le projet éditable sans Xcode.
- **`.github/workflows/ios.yml`** : runner `macos-15`, Xcode `latest-stable` (le SDK iOS 26
  est exigé par l'App Store), certificats importés par `apple-actions/import-codesign-certs`,
  provisionnement automatique avec la clé API App Store Connect
  (`-allowProvisioningUpdates`), numéro de build = numéro de lancement de la CI.
- **Le découpage en couches** : `Core/` en Swift pur, sans aucune dépendance système, testé à
  chaque push ; `Services/` mince autour des API Apple ; `Features/` pour l'interface. Sans
  Mac, un aller-retour sur iPhone prend un quart d'heure : tout ce qui peut être testé en CI
  doit descendre dans `Core/`.
- **RevenueCat et TelemetryDeck** : RepLock et Dunk It les utilisent déjà. TelemetryDeck
  est anonyme, sans demande de pistage (ATT), et se déclare « non lié à l'identité ».
- **Les workflows App Store Connect sur Linux** (`asc-listing.yml`, `asc-stats.yml`) :
  fiche App Store et statistiques pilotées par l'API, sans minutes macOS.
- **Le parcours d'onboarding RepLock** : accroche → questionnaire → diagnostic →
  projection → permissions → écran « on prépare ton garage » → paywall. Et ses offres de
  rétention (reconquête après résiliation, carte de rétention).

## Ce qu'on garde, ce qu'on jette

**Gardé tel quel ou presque** — c'est là qu'est la valeur :

- `markets.json`, `rarity.json`, `vehicles.json`, la cascade de rareté et le rapprochement
  du texte de l'IA (`CatalogStore`) ;
- le prompt et le contrat de `identify`, l'anti-triche « photo d'écran » ;
- `CardArtStylizer`, `SubjectLifter`, `CardShareRenderer`, `PlateBlurrer` ;
- les tests de rareté, de rapprochement et `RealWorldMatchingTests` ;
- les documents légaux (à mettre à jour : comptes, synchronisation, photos d'entraînement).

**Retiré** :

- `Car3DView` (522 lignes de 3D procédurale) et la chaîne d'illustrations studio
  (`render`, `CarArt`, scripts Python) : depuis que la photo du joueur prime, elles ne
  servent plus qu'au Spogdex. Le Spogdex montrera une silhouette par carrosserie.
- Le décompte des scans dans `UserDefaults` : il se réinitialise à la réinstallation.
- Les emplacements vides de `SocialView` : ils reviennent quand les comptes existent.

## Le défaut à corriger en premier : les scans gratuits ne sont pas protégés

Aujourd'hui, le paywall n'existe **que dans l'app**. `identify` ne vérifie ni abonnement
ni crédits : quiconque extrait la clé `anon` scanne 100 fois par jour à nos frais, et une
réinstallation rend les 5 scans offerts.

Cible — le serveur décide, l'app affiche :

1. **Compte anonyme (Neon Auth)** créé au premier lancement, sans rien demander au joueur.
   Sign in with Apple se greffe dessus plus tard pour retrouver son garage.
2. **App Attest** : chaque appel à `identify` prouve qu'il vient de la vraie app sur un
   vrai iPhone. La clé `anon` seule ne suffit plus.
3. **DeviceCheck** : Apple conserve deux bits par appareil, qui **survivent à la
   réinstallation**. Un bit = « les scans offerts ont été consommés ».
4. **Crédits en base** : `identify` décrémente le solde du compte et refuse à zéro, sauf
   abonnement actif.
5. **Abonnement vérifié côté serveur** : RevenueCat prévient le backend par webhook, une
   table `entitlements` fait foi.

## Architecture cible

### App

```
Spog/
  App/            point d'entrée, navigation, injection des stores
  Core/           thème, composants néon, localisation
  Catalog/        données JSON + rareté + rapprochement (Swift pur, sans UIKit)
  Identify/       pipeline hybride : classifieur → IA → confirmation
  Scanner/        caméra, flou des plaques, sécurité routière
  Cards/          mise en scène, révélation, partage
  Garage/         collection, fiche, correction du modèle
  Account/        session Neon Auth, crédits, abonnement
  Onboarding/     questionnaire, pays, premier scan guidé
  Social/         amis, classement (phase 4)
```

`Catalog/` reste en Swift pur, sans dépendance à iOS : il se teste aussi depuis Windows
avec la chaîne d'outils Swift, ce qui compte tant qu'on n'a pas de Mac sous la main.

### Backend (Neon)

| Table | Contenu |
|---|---|
| `profiles` | pseudo, pays, carrosseries préférées, code de parrainage |
| `catches` | une ligne par prise : modèle, pays, date, vérifiée, teinte |
| `credits` | scans restants par compte |
| `entitlements` | abonnement actif, alimenté par le webhook RevenueCat |
| `training_samples` | photos confirmées par le joueur, avec son consentement |

Photos dans le stockage Neon, deux compartiments : `shots` (privé, la collection du joueur)
et `training` (photos consenties, servent au classifieur).

Fonctions : `identify` (réécrite autour des points ci-dessus), `revenuecat-webhook`,
`referral-redeem`.

### Services tiers

| Rôle | Choix |
|---|---|
| Abonnement | RevenueCat (configuré par son API REST, comme `revenuecat-setup.yml` de Dunk It) |
| Analytics produit | TelemetryDeck |
| Paywall modifiable à distance | Offres RevenueCat d'abord ; Superwall si on veut des A/B tests de paywall |
| Attribution publicitaire | Plus tard, au premier budget pub : elle impose la demande ATT |
| Plantages | Sentry |

## L'identification hybride

```
photo ──► classifieur Core ML (sur l'iPhone, gratuit, instantané)
             │
             ├─ confiance ≥ seuil ──► carte créée, aucun appel serveur
             │
             └─ sinon ──► identify (IA) ──► confirmation du joueur ──► carte
                                                   │
                                                   └─► training_samples (si consenti)
```

Trois étapes, sans brûler aucune :

1. **IA seule.** La v1 sort ainsi. Le circuit de collecte (`training_samples`, case de
   consentement) existe dès le premier jour : sans données, pas de classifieur.
2. **Classifieur en arrière-plan.** Il tourne à chaque scan mais **ne décide rien** : on
   journalise son avis à côté de celui de l'IA. On mesure l'accord réel, sur de vraies rues,
   avant de lui confier quoi que ce soit.
3. **Classifieur en premier.** Activé modèle par modèle, uniquement là où l'accord mesuré
   dépasse le seuil. Le seuil vit dans une configuration distante, pas dans le code.

Entraînement : Create ML ou PyTorch converti avec `coremltools`, sur les photos consenties.
On commence par la trentaine de modèles les plus scannés — ce sont eux qui coûtent.

Le coût de l'appel IA baisse aussi indépendamment : `tools/score-identification.py` permet
de comparer un modèle moins cher que `gpt-4o` sur le jeu de test avant d'en changer.

## Ordre des travaux

| Phase | Contenu | Livrable |
|---|---|---|
| **0. Socle** | Dépôt GitHub, `project.yml`, `ios.yml` repris de RepLock, nouveau bundle ID, projet Neon dédié, `identify` porté sur Neon Functions | Un build TestFlight lancé depuis Windows |
| **1. Comptes et argent** | Compte anonyme, App Attest, DeviceCheck, crédits serveur, RevenueCat | Les 5 scans offerts ne se contournent plus |
| **2. Refonte de l'app** | Nouvelle structure, onboarding questionnaire, Superwall, PostHog, Sentry, synchro du garage | v1 publiable |
| **3. Collecte et classifieur** | Consentement, `training_samples`, classifieur en arrière-plan puis en premier | Coût par scan en baisse |
| **4. Social** | Amis, classement, crews | L'écran Social cesse d'être vide |

## Prérequis hors code

**À obtenir du titulaire du compte Mandalore LLC.** Les certificats et la clé API rangés dans
`~/replock-signing` appartiennent à une autre équipe (`8L8G4P4Z9X`) : ils ne peuvent pas
signer une app de Mandalore.

- **Un accès Admin** dans App Store Connect pour l'équipe `GXS33F5JT9`, ou à défaut une
  **clé API App Store Connect** (fichier `.p8`, identifiant de clé, identifiant d'émetteur)
  générée par lui. C'est elle qui permet à la CI de signer et d'envoyer sur TestFlight.
- **Un certificat Apple Distribution** de l'équipe, exporté en `.p12` avec son mot de passe.
- **Le contrat « Paid Applications »** signé : sans lui, les abonnements ne se chargent pas.
  Le COMPTE-APPLE.md de Cyranox le donne encore comme non signé, à vérifier.
- **Le nouveau bundle ID `com.mandalore-group.spog`.** `com.mandaloregroup.spog` reste réservé
  par l'équipe personnelle gratuite, qui ne peut pas le libérer : même problème que Cyranox.
  Les identifiants d'abonnement peuvent garder `com.mandaloregroup.spog.premium.*`.
- **Les produits App Store Connect** mensuel et annuel, et la fiche de l'app.

Côté développeur : un dépôt GitHub (privé, et l'historique de 37 commits poussé tel quel),
ce qui règle aussi la sauvegarde.

## Risques connus

- **Aucun scan n'a encore été fait dans une vraie rue.** La refonte ne change rien à ce
  risque-là : le premier essai sur iPhone reste prioritaire.
- **Le consentement aux photos d'entraînement** doit être explicite et révocable (RGPD),
  et les plaques floutées avant tout envoi.
- **Le plafond global de 5 000 scans/jour** reste à relever avant toute campagne.
- **Le compte Mandalore est sous avertissement.** Cyranox a été rejetée pour 4.3(a) « Spam »
  le 16/09/2026, avec la mention *Extended Review* : une récidive peut faire exclure le compte
  du programme, et c'est lui qui porte Spog. Spog est un concept original, mais la première
  soumission doit être soignée, et ne partir qu'une fois l'appel de Cyranox tranché.
