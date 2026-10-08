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

**Mesure du 07/10/2026, sur les 13 photos de `test-photos/` :**

| Modèle | Identification | Couleur | Confiance |
|---|---|---|---|
| `gpt-4o` (en production) | 13/13 | 9/10 | 0,90 à 0,95 |
| `gpt-4.1-mini` | 13/13 | 9/10 | 0,80 à 0,95 |

À qualité égale sur ce jeu, `gpt-4.1-mini` coûte environ deux à trois fois moins par scan
(tarif six fois plus bas, mais il compte plus de jetons par image). Deux réserves avant
d'en changer : sa confiance descend jusqu'au seuil de l'app (0,80 dans `rarity.json`), donc
plus d'écrans de confirmation ; et treize photos d'annonces ne disent rien de la rue. On
garde `gpt-4o` pour le premier vrai test dans la rue, puis on refait la mesure sur ces
photos-là. Changer de modèle ne demande aucun code :
`gh workflow run backend.yml -f deploy=true -f model=gpt-4.1-mini`.

## Le concurrent : Revlo (étudié le 07/10/2026)

Même concept, sorti avant nous. Ce qu'on en retient, **la mécanique, jamais l'habillage** —
le compte Mandalore est déjà sous avertissement 4.3 « copie » (voir Risques) :

- **Le « Develop »** : la carte porte d'abord la photo du joueur, puis un rendu studio généré
  à partir d'elle. Chez eux, quasi instantané : rendu préparé à l'avance pour la démo, et
  vraisemblablement généré en arrière-plan dès la prise.
- **Un modèle gratuit généreux**, qui fait payer ce qui coûte (la génération), pas la prise.
- **Un onboarding jouable** : une fausse prise de démonstration avant même la caméra.
- **Le social** : classements par ville et par saison, fil, crews, carte des prises.

Ce qu'on garde comme différence : **la rareté qui dépend du pays**. Une Clio ne vaut rien à
Paris : chaque ville a ses propres trophées, et les classements locaux ont un sens.

## Économie — décidée le 08/10/2026, pas encore codée

Remplace « 5 scans offerts puis abonnement ».

| | Gratuit | Pro |
|---|---|---|
| Scans | **10 le premier jour, puis 3 par jour** ; +3 par pub récompensée (3 pubs/jour) | Illimités (plafond anti-abus invisible, 100/jour) |
| Rendus « Develop » | **1 par jour**, +1 par pub récompensée | Illimités, meilleure qualité |
| Pub | Récompensée uniquement, jamais imposée | Aucune |
| Pack de primes | 1 par semaine | 1 de plus |

- **Pas de monnaie virtuelle** pour la première version : de simples compteurs tenus par le
  serveur. Des **packs de rendus** payants (consommables) viendront plus tard, s'il y a de
  la demande — ils s'ajouteront aux compteurs sans changer le modèle.
- **Jamais de voitures vendues au hasard** (loot box) : ça tuerait la valeur des vraies prises,
  et c'est interdit ou encadré (Belgique, règle Apple 3.1.1).
- **Régie publicitaire** : la plus rémunératrice (probablement AppLovin MAX), compte à
  décider à la fin. La pub impose une fenêtre ATT, un consentement RGPD, une récompense
  vérifiée côté serveur, et la réécriture de la politique de confidentialité.

**Coût mesuré d'un rendu** (08/10/2026, à travers la fonction Neon, 2 photos de test) :

| Modèle | Qualité | Temps | Coût |
|---|---|---|---|
| `gpt-image-1-mini` | basse | 15 s | 0,44 centime |
| `gpt-image-1-mini` | moyenne | 20–25 s | **1,4 centime** (retenu) |
| `gpt-image-1` | moyenne | 26 s | 6,7 centimes (piste pour Pro) |

Défaut commun : jantes et logos un peu réinventés — à corriger par le prompt et l'option de
fidélité renforcée. Pour l'instantané : rendu préparé pour la démo, génération en
arrière-plan dès la prise pour qui a un rendu disponible, animation « Polaroïd » sinon ;
tester ensuite un modèle plus rapide (Gemini Flash Image, via la passerelle IA de Neon ?).

## Social — décidé le 08/10/2026

**Marques méritées plutôt que finitions au hasard** : « Premier à… » (premier repéreur d'un
modèle dans un pays), « Nocturne », « Chassée » (cible du pack de primes).

Ordre retenu :

1. **Comptes** (sans friction, Sign in with Apple facultatif) et prises enregistrées côté
   serveur — **fait**.
2. **Ligues hebdomadaires** et **premier repéreur** — **faits**.
3. **Pack de primes de la semaine** : chaque lundi, un pack scellé à ouvrir révèle 3 voitures
   à chasser dans la rue ; **le même pack pour toute une ville**, la première personne qui
   trouve la cible prend le gros bonus. Les packs ne se vendent pas.
4. **Duels entre amis** (7 jours, le plus de points gagne).
5. Ensuite : **territoires** (le « roi » d'un quartier sur la semaine) et **crews**.

## Ordre des travaux

| Phase | Contenu | État |
|---|---|---|
| **0. Socle** | Dépôt, XcodeGen, CI, signature Mandalore, Neon, `identify` | Fait |
| **1. Argent (serveur)** | Scans offerts et abonnement vérifiés par le serveur | Fait, sauf App Attest |
| **2. Refonte de l'app** | Silhouette, analytics, onboarding jouable | En partie |
| **3. Collecte et classifieur** | Consentement, `training_samples`, classifieur | Collecte faite |
| **4. Social** | Comptes, ligues, premier repéreur → pack de la semaine → duels → territoires, crews | Ligues faites |
| **5. Économie** | 3 scans/jour, Develop, pub récompensée, nouveau Pro | À faire |

## Où on en est — 08/10/2026

Chaque ligne « fait » a été vérifiée en production ou en CI, pas seulement écrite.

**Phase 0 — faite.** Dépôt `0xcssh/spog` (privé), XcodeGen, CI macOS verte, build signé
Mandalore qui produit une IPA. Projet Neon `spog`, `identify` déployé et testé sur une vraie
photo. L'app appelle Neon ; l'ancienne fonction Supabase `identify` est retirée du dépôt.

**Phase 1 — faite, sauf App Attest.**
- Le serveur décompte les scans offerts par installation (`free_scans`), l'identifiant
  d'installation vit dans le trousseau et survit à la réinstallation. Vérifié en production :
  4, 3… puis 402 `paywall_required` à zéro.
- L'abonnement se prouve par la transaction StoreKit 2 signée par Apple, vérifiée côté
  serveur sans réseau (code repris de Cyranox, 27 tests).
- Une photo sans voiture ou d'écran ne coûte pas de scan offert.
- **Pas fait : App Attest.** En attendant, l'invention d'identifiants d'installation est
  bornée à 60 scans offerts par IP et par jour (~0,26 € au pire par IP). À faire avant toute
  campagne : il faut l'activer sur l'App ID et le tester sur un vrai iPhone.
- **Choix : pas de RevenueCat pour l'instant.** La vérification StoreKit côté serveur couvre
  le besoin sans compte tiers. RevenueCat reste utile le jour où l'on voudra des offres
  pilotées à distance ; il faudra alors un compte et sa clé.

**Phase 2 — commencée.**
- Fait : le volume 3D SceneKit (522 lignes) remplacé par une silhouette de carrosserie.
- Fait : analytics TelemetryDeck branchés (tunnel d'onboarding, scans, cartes, paywall,
  achats), **coupés** tant que `Analytics.appID` n'est pas renseigné — il faut créer l'app
  dans TelemetryDeck, et corriger la politique de confidentialité dans le même commit.
- Pas fait : onboarding en questionnaire à la RepLock, Sentry (il faut un DSN), synchro du
  garage (il faut Neon Auth et décider de ce qui part sur le serveur).
- Gardé pour l'instant : les rendus studio (`CarArt`) et leur fabrique. Leur sort dépend
  de la décision « lot d'illustrations » de PLAN.md, toujours ouverte.

**Phase 3 — circuit de collecte fait, classifieur à venir.**
- Avec l'accord du joueur, demandé une fois après sa première carte et modifiable dans les
  réglages, une vraie prise est conservée (compartiment privé `training`, table
  `training_samples`) avec l'étiquette de l'IA, puis celle du joueur quand il confirme ou
  corrige. Retirer l'accord efface tout. Vérifié en production de bout en bout.
- La politique de confidentialité (app et `Legal/*.html`) le dit. **Les pages publiées sur
  le site doivent être remplacées par les nouvelles versions de `Legal/`.**
- Le classifieur lui-même attend des données : quelques centaines de photos étiquetées par
  modèle, sur les modèles les plus scannés.

**Phase 4 — comptes, ligues et premier repéreur faits** (08/10/2026).
- Serveur, vérifié en production : joueurs, pseudo, Sign in with Apple, prises comptées par
  le serveur avec le même catalogue que l'app, premier repéreur, ligues hebdomadaires,
  suppression de compte. 128 tests, dont les migrations SQL sur PGlite.
- App, compilée et signée en CI : prises envoyées au serveur (et renvoyées si le réseau
  manquait), écran « Ligue et rivaux », pseudo, Sign in with Apple, drapeau « premier » sur
  les cartes, suppression de compte dans les réglages. **Pas encore essayée sur un iPhone.**
- Politique de confidentialité mise à jour pour les comptes et les classements.
- Reste : pack de primes, duels, territoires, crews.

**Develop — mesuré, pas encore ouvert aux joueurs.** L'action `develop` existe côté serveur,
réservée aux installations de `DEVELOP_TESTERS` (vide en production).

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

Fait le 07/10/2026 : clé API (`27XC5K46K6`) et certificats Mandalore récupérés dans les
fichiers de Cyranox et posés dans les secrets GitHub ; le build signé fonctionne. Restent
le contrat « Paid Applications », la fiche de l'app et les deux produits dans App Store
Connect.

La CI tourne sur un dépôt privé dont les minutes macOS gratuites sont épuisées : le dépôt
passe en public le temps de chaque CI, puis repasse en privé. Le code n'est poussé que
pendant qu'il est privé.

## Risques connus

- **Aucun scan n'a encore été fait dans une vraie rue.** La refonte ne change rien à ce
  risque-là : le premier essai sur iPhone reste prioritaire.
- **Le consentement aux photos d'entraînement** doit être explicite et révocable (RGPD),
  et les plaques floutées avant tout envoi.
- **Le plafond global de 5 000 scans/jour** reste à relever avant toute campagne.
- **Revlo est sorti avant nous, sur le même concept.** Reprendre ses mécaniques, jamais son
  vocabulaire (« Film », « Develop », « Garage/Rivals »), son déroulé d'onboarding ni son
  esthétique : c'est exactement ce que sanctionne la règle 4.3.
- **Le compte Mandalore est sous avertissement.** Cyranox a été rejetée pour 4.3(a) « Spam »
  le 16/09/2026, avec la mention *Extended Review* : une récidive peut faire exclure le compte
  du programme, et c'est lui qui porte Spog. Spog est un concept original, mais la première
  soumission doit être soignée, et ne partir qu'une fois l'appel de Cyranox tranché.
