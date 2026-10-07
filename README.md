# Spog

*App iOS — nom arrêté le 24/08/2026.*

App iOS de collection de voitures repérées dans la vraie vie : tu photographies une voiture,
l'IA l'identifie, elle devient une carte unique dans ton garage.

État du projet, blocages et décisions en attente : [PLAN.md](PLAN.md).
Conventions de travail : [CLAUDE.md](CLAUDE.md).

## Contrainte fondatrice

**Rien n'est codé en dur, et rien ne suppose un seul pays ni une seule langue.**
Identifiants et données en anglais, affichage traduit. Ajouter un marché doit être
ajouter une donnée, jamais modifier du code.

## Contenu actuel

| Fichier | Rôle |
|---|---|
| `Spog/Catalog/markets.json` | Regroupement des pays en régions, et la liste de celles qui sont réellement calibrées (`populated`). Ajouter un pays = ajouter son code. |
| `Spog/Catalog/rarity.json` | Les 6 paliers de rareté, leurs points, leurs clés de traduction, le seuil de confiance. |
| `Spog/Catalog/vehicles.json` | Le catalogue : 867 véhicules, rareté par région. **Source de vérité, éditable à la main.** |
| `tools/validate_catalog.py` | Vérifie l'intégrité du catalogue. À relancer après chaque ajout. |
| `tools/lookup_demo.py` | Démonstration du rapprochement et de la rareté. Sert de référence pour le futur code Swift. |
| `backend/functions/identify/handler.ts` | Le relais vers l'IA : reçoit une photo, renvoie marque, modèle, couleur et confiance. Aucune règle de jeu, aucun pays. |

## Commandes

Vérifier le catalogue :

    python3 tools/validate_catalog.py

Tester une identification :

    python3 tools/lookup_demo.py "Renault Clio IV" US

Sans argument, `lookup_demo.py` déroule une série d'exemples commentés.

Lancer les tests (cible `SpogTests`) : ils tournent dans la CI à chaque push
(`.github/workflows/ios.yml`). Voir CLAUDE.md pour la boucle sans Mac.

Ils couvrent les règles qui se trompent en silence : la cascade de rareté, le
rapprochement du texte libre de l'IA avec le catalogue, les codes de parrainage,
la stabilité de la quête du jour, et le décompte des prises offertes. Le contrat
de couleurs et de carrosseries entre l'app et la fonction `identify` y est épinglé
des deux côtés — les deux listes vivent dans deux fichiers que rien d'autre ne relie.

## Le backend

Une seule fonction, `identify`, sur Neon Functions, dans un projet dédié à Spog. Les quotas
vivent dans sa base Postgres (`backend/migrations/`). **La clé OpenAI n'existe que là**,
jamais dans l'app.

    cd backend && npm install && npm test          # 18 tests, tournent sous Windows
    gh workflow run backend.yml -f deploy=true      # déploiement

Elle ne renvoie que des données brutes. La rareté, les points et les paliers restent dans
le catalogue embarqué : changer l'équilibre du jeu ne demande jamais de redéployer le
serveur, et ne suppose aucun pays.

## Comment la rareté est résolue

Cascade, du plus précis au plus général : **pays exact → région → `default`**.
Un pays jamais calibré fonctionne donc quand même, sur la valeur `default` du véhicule.

Cinq régions sont calibrées : **`EU_WEST`, `EU_NORTH`, `EU_EAST` et `NA`** — l'Europe et
l'Amérique du Nord, marchés de lancement — plus `ASIA_SE`. Les autres fonctionnent sur le
repli mondial. La même Renault Clio
est *commune* en France et *notable* au Viêt Nam — c'est tout l'intérêt du système, et la
raison pour laquelle une rareté mondiale unique ne peut pas marcher.
