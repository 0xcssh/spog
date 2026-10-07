# Spog — conventions du projet

App iOS de collection : on photographie une voiture croisée dans la rue, l'IA l'identifie,
elle devient une carte unique dans un garage.

Ce fichier dit **comment travailler ici**. Pour l'état d'avancement et ce qui bloque, voir
[PLAN.md](PLAN.md). Pour l'architecture détaillée, voir [README.md](README.md).

---

## La contrainte fondatrice

**Rien n'est codé en dur, et rien ne suppose un seul pays ni une seule langue.**

Les identifiants et les données sont en anglais, l'affichage est traduit. Ajouter un marché
doit être **ajouter une donnée**, jamais modifier du code. Les trois fichiers de données —
`markets.json`, `rarity.json`, `vehicles.json` — sont la source de vérité, éditables à la
main, et le code ne connaît aucun pays par son nom.

Cette règle a survécu à toutes les autres. Ne la casse pas pour aller plus vite.

## Direction artistique

Noir et violet, néon, épuré. **Toutes les couleurs vivent dans `Core/Theme.swift`**, jamais
ailleurs — pas de `Color(hex:)` dispersé dans les vues. Les paliers de rareté portent leurs
propres teintes dans `CatalogModels.swift`, et elles servent aussi d'éclairage aux cartes.

## Ce que le visuel d'une carte doit montrer

**La voiture réellement croisée passe avant le modèle du catalogue.**

Ordre de priorité, identique dans la fiche, la grille et l'image de partage :

1. la photo du joueur, mise en scène par `CardArtStylizer` ;
2. à défaut, le rendu studio du modèle (`CarArt`) ;
3. à défaut, la scène de repli avec le volume 3D générique.

C'est une décision du 07/10/2026, et elle renverse l'ordre d'origine. Un rendu studio montre
un exemplaire neuf et standard dans l'une des quatorze teintes de la palette : il ne sait
représenter ni un covering zébré, ni une livrée de taxi, ni un kit large, ni vingt ans de
soleil sur la peinture. Rendre ce rendu à quelqu'un qui a repéré une Porsche zébrée, c'est
lui prendre sa prise pour lui donner une illustration.

Les rendus studio servent donc au **Spogdex** — montrer ce qu'il reste à trouver — et aux
modèles pas encore attrapés. Là, il n'y a rien à trahir.

## L'argent

Le seul coût variable est l'appel d'identification : **0,44 centime d'euro par scan**
(`gpt-4o`, image 1280 px en `detail: "high"`). Chaque appel inscrit son coût réel dans les
journaux Supabase.

Trois garde-fous dans `identify` :

| | Valeur | Rôle |
|---|---|---|
| `DEVICE_DAY_LIMIT` | 100/jour | Personne ne croise cent voitures |
| `IP_DAY_LIMIT` | 20 000/jour | Un réseau partagé n'est pas un tricheur |
| `GLOBAL_DAY_LIMIT` | **5 000/jour** | Mur contre une facture non bornée |

⚠️ **Le plafond global est une valeur de pré-lancement.** Il ne laisse passer que
1 000 nouveaux joueurs par jour, puisque chacun consomme 5 scans offerts. Une campagne
marketing réussie le heurterait et renverrait « service saturé » à tout le monde. À relever
**avant** la première vraie poussée d'audience, pas après.

Les 5 scans offerts coûtent **2,2 centimes par installation**. C'est un coût d'acquisition,
pas un coût de service : budgète-le à côté de la publicité.

## Les secrets

- `OPENAI_API_KEY` → secrets Supabase, **jamais dans le dépôt ni dans l'app**.
- `RENDER_SECRET` → secrets Supabase, et sa contrepartie locale dans `~/.spog/render-secret`.
- La clé `anon` Supabase est dans `Core/BackendConfig.swift` et **c'est normal** : elle est
  publique par conception, extractible de tout binaire iOS, et ne donne droit qu'à appeler
  les fonctions sous leurs quotas.

## Construire et tester

```bash
# Les 63 tests
xcodebuild -project Spog.xcodeproj -scheme Spog \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Vérifier le catalogue après toute édition de vehicles.json
python3 tools/validate_catalog.py
```

⚠️ **Le Bureau est synchronisé par iCloud**, et ses attributs étendus cassent la signature
de code. Construis toujours hors du projet :

```bash
xcodebuild ... SYMROOT=/tmp/spogbuild/sym OBJROOT=/tmp/spogbuild/obj
```

## Deux pièges du simulateur

**Vision ne détoure pas.** `VNGenerateForegroundInstanceMaskRequest` n'y trouve pas de
modèle d'inférence, `SubjectLifter` rend `nil`, et toute carte scannée tombe sur le repli.
On juge alors le repli en croyant juger la mise en scène. Un test le constate
(`SubjectLifterTests`) et préviendra le jour où ça changera.

Pour voir la vraie mise en scène sans iPhone :

```bash
swift tools/preview-stylizer.swift test-photos/peugeot-3008.webp --glow 4C7DF0
```

Cet outil **recopie** la chaîne de `CardArtStylizer` parce que celui-ci importe UIKit.
Toute retouche de l'un doit être reportée sur l'autre.

**StoreKit ne s'applique que lancé depuis Xcode.** `Spog.storekit` est ignoré par
`simctl install`. Le contournement du paywall existe en `#if DEBUG` seulement
(`SubscriptionStore.enableDebugBypass`), et ne peut donc pas partir sur l'App Store.

## Les tests

Ils couvrent les règles **qui se trompent en silence** : la cascade de rareté, le
rapprochement du texte libre de l'IA, les codes de parrainage, la stabilité de la quête du
jour, le décompte des prises offertes, et le contrat de couleurs et de carrosseries entre
l'app et `identify` — deux listes qui vivent dans deux fichiers que rien d'autre ne relie.

`RealWorldMatchingTests` contient les **réponses réelles du modèle** sur treize photos
d'annonces. Elles valent mieux que des exemples imaginés : elles contiennent les formes que
le modèle produit vraiment, y compris des finitions plus fines que le catalogue
(« Peugeot 307 CC » pour une 307). Une identification plus précise que la fiche ne doit
jamais devenir un échec de rapprochement.

## Style du code

Commentaires et messages de commit **en français**, et ils disent **pourquoi**, pas quoi.
Un commentaire qui paraphrase la ligne suivante est du bruit ; un commentaire qui explique
la faute qu'on a commise avant d'écrire cette ligne vaut une demi-journée à celui qui
passera après.

Les textes affichés passent tous par `Localizable.xcstrings`, en français et en anglais.
Aucune chaîne en dur dans une vue.
