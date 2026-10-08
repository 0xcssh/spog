# Spog — conventions du projet

App iOS de collection : on photographie une voiture croisée dans la rue, l'IA l'identifie,
elle devient une carte unique dans un garage.

Ce fichier dit **comment travailler ici**. Pour l'état d'avancement et ce qui bloque, voir
[PLAN.md](PLAN.md) ; pour la refonte en cours (sans Mac, backend Neon, social, économie),
[REFONTE.md](REFONTE.md). Pour l'architecture détaillée, voir [README.md](README.md).

---

## La contrainte fondatrice

**Rien n'est codé en dur, et rien ne suppose un seul pays ni une seule langue.**

Les identifiants et les données sont en anglais, l'affichage est traduit. Ajouter un marché
doit être **ajouter une donnée**, jamais modifier du code. Les trois fichiers de données —
`markets.json`, `rarity.json`, `vehicles.json` — sont la source de vérité, éditables à la
main, et le code ne connaît aucun pays par son nom.

Cette règle a survécu à toutes les autres. Ne la casse pas pour aller plus vite.

**Ces trois fichiers sont lus aussi par le serveur**, embarqués au build de la fonction
(`backend/functions/identify/catalog.ts`) : depuis les classements, c'est lui qui compte
les points. Il n'en existe aucune copie — mais changer l'équilibre du jeu demande désormais
de redéployer le backend en plus de publier l'app. Toute retouche des règles de
`CatalogStore.swift` (rapprochement, rareté) doit être reportée dans `catalog.ts`, dont les
tests reprennent les mêmes cas que les tests Swift.

## Direction artistique

Noir neutre, anthracite, filets fins, **un seul accent violet**. **Toutes les couleurs vivent
dans `Core/Theme.swift`**, jamais ailleurs — pas de `Color(hex:)` dispersé dans les vues. Les
paliers de rareté portent leurs propres teintes dans `CatalogModels.swift`.

Sobriété décidée le 09/10/2026 (« trop de couleurs, ça part dans tous les sens ») : le violet
sert au bouton principal, au déclencheur, à la jauge de niveau, et presque à rien d'autre ;
les couleurs de rareté ne vont que sur de petits marqueurs (bande et jauge de la carte,
pastille de filtre) ; pas de halo coloré, de lueur portée ni de dégradé multicolore. Les
alertes prennent l'ambre `Theme.warning`, pas l'or des trophées. Labels en capitales
espacées (`Overline`), chiffres en monospace.

L'écran d'accueil (« Ton garage ») a une structure de tableau de bord inspirée du genre ;
comme pour toute la mécanique empruntée à Revlo, **jamais son vocabulaire** (voir
REFONTE.md, règle 4.3).

## Ce que le visuel d'une carte doit montrer

**La voiture réellement croisée passe avant le modèle du catalogue.**

Ordre de priorité, identique dans la fiche, la grille et l'image de partage :

1. la photo du joueur, mise en scène par `CardArtStylizer` ;
2. à défaut, le rendu studio du modèle, affiché par `ModelArt` : le rendu carré haute
   définition du serveur (`VehicleArtService`, action `vehicle_art`) en plein cadre, et en
   attendant qu'il arrive le bandeau embarqué `CarArt` (660 × 290, trop petit pour une
   carte, décision du 08/10/2026) ;
3. à défaut, la silhouette de la carrosserie (`CarSilhouette`). Le volume 3D SceneKit a été
   retiré le 07/10/2026.

C'est une décision du 07/10/2026, et elle renverse l'ordre d'origine. Un rendu studio montre
un exemplaire neuf et standard dans l'une des quatorze teintes de la palette : il ne sait
représenter ni un covering zébré, ni une livrée de taxi, ni un kit large, ni vingt ans de
soleil sur la peinture. Rendre ce rendu à quelqu'un qui a repéré une Porsche zébrée, c'est
lui prendre sa prise pour lui donner une illustration.

Les rendus studio servent donc au **Spogdex** — montrer ce qu'il reste à trouver — et aux
modèles pas encore attrapés. Là, il n'y a rien à trahir.

**Le « développement »** (décidé le 08/10/2026, pas encore dans l'app) concilie les deux :
un rendu studio généré **à partir de la photo du joueur**, qui garde sa teinte, ses jantes,
son covering. Action `develop` du backend, fermée aux joueurs tant que l'économie n'existe
pas (voir REFONTE.md).

## L'argent

Le seul coût variable est l'appel d'identification : **0,44 centime d'euro par scan**
(`gpt-4o`, image 1280 px en `detail: "high"`). Chaque appel inscrit son coût réel dans les
journaux de la fonction Neon.

Trois garde-fous dans `identify` (`backend/functions/identify/handler.ts`). Ils sont
**fail-closed** : si la base des quotas ne répond pas, les scans sont refusés plutôt que
laissés sans plafond.

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

Les **rendus des modèles** (`vehicle_art`, 1024 × 1024, `gpt-image-1-mini` en qualité
`high`) coûtent ≈3,3 centimes de dollar, **une fois par modèle** pour tous les joueurs :
≈30 $ pour les 867 modèles, puis plus rien. Seuls les modèles du catalogue embarqué sont
acceptés, et `ART_GLOBAL_DAY_LIMIT` (300 générations par jour, cache non compté) empêche
une boucle de tout payer d'un coup.

**Le serveur est l'autorité sur les scans offerts** (`free_scans`, par installation) et sur
l'abonnement (transaction StoreKit 2 vérifiée côté serveur, `entitlement.ts`). Le compteur de
l'app n'est qu'un miroir pour l'affichage.

⚠️ **L'économie va changer** (décision du 08/10/2026, voir REFONTE.md « Économie ») : 3 scans
par jour (10 le premier jour), 1 rendu par jour, de la pub récompensée pour en gagner plus,
Pro illimité et sans pub. Le code applique encore « 5 scans offerts puis abonnement ».

## Les secrets

Le backend est sur **Neon**, projet `spog` (`damp-fire-11684360`, branche
`br-plain-fog-b7f3ate2`), sur le compte Neon du développeur. Le déploiement passe par la
CI : `gh workflow run backend.yml -f deploy=true`.

- `OPENAI_API_KEY` et `NEON_API_KEY` → secrets GitHub du dépôt, **jamais dans le dépôt ni
  dans l'app**. La CI pousse la clé OpenAI dans l'environnement de la fonction à chaque
  déploiement.
- `Core/BackendConfig.swift` ne contient que l'URL publique de la fonction.
- `RENDER_SECRET` → reste sur l'ancien projet Supabase, avec la fonction `render` des
  illustrations studio, appelée à disparaître (voir REFONTE.md).

## Le classement

C'est le serveur qui compte, jamais l'app. Une prise **entre au classement** seulement si :

- son pays vient de la position (mode automatique), pas d'un choix à la main ;
- son modèle correspond à une identification faite par ce serveur pour cette installation
  (`scan_id`) — le modèle retenu, ou l'une des propositions montrées au joueur.

Le reste n'est jamais refusé : la carte, le garage, la collection. La sanction se limite au
classement, là où tricher fait du tort aux autres. Le premier à attraper un modèle dans un
pays double sa prise (`first_spots`). Les ligues : groupes de 30 du même palier, remis à zéro
chaque lundi UTC, 7 montent, 5 descendent. La logique qui doit tenir face aux requêtes
simultanées vit en SQL (`backend/migrations/004_players_leagues.sql`) et se teste sur un vrai
Postgres embarqué (PGlite).

Toute app qui crée des comptes doit permettre de **les supprimer depuis l'app** (App Store
5.1.1(v)) : action `delete_account`, bouton dans les réglages. Ne pas le retirer.

## Construire et tester

**Depuis le 07/10/2026, on développe sous Windows, sans Mac** — la méthode de RepLock
(voir [REFONTE.md](REFONTE.md)). Le projet Xcode n'est plus versionné : il est généré par
XcodeGen depuis `project.yml`. Ne jamais éditer de `project.pbxproj`, ne jamais proposer
d'ouvrir Xcode ni le simulateur en local.

La boucle : modifier → push → la CI (`.github/workflows/ios.yml`, runner macOS) compile et
lance les tests → build signé à la demande :

```bash
# IPA de développement, à installer par USB
gh workflow run ios.yml -f export_method=debugging
gh run download --name Spog-ipa
py -3.12 -m pymobiledevice3 apps install Spog.ipa   # Python 3.12, pas 3.14

# Envoi direct sur TestFlight
gh workflow run ios.yml -f export_method=app-store-connect

# Vérifier le catalogue après toute édition de vehicles.json (tourne sous Windows)
py tools/validate_catalog.py
```

Signature : équipe Mandalore LLC `GXS33F5JT9`, bundle `com.mandalore-group.spog`. Les
certificats et la clé API vivent dans les secrets GitHub du dépôt, jamais dans le dépôt.

⚠️ **Les minutes macOS des dépôts privés du compte sont épuisées.** Décision de l'utilisateur :
le dépôt passe en **public le temps de chaque CI**, puis repasse en **privé**. Le code ne se
pousse **que pendant que le dépôt est privé** (vérifier la visibilité dans la même commande
que le push), et on ne bascule en public qu'ensuite, dans une commande séparée. Repasser en
privé dès la fin des runs — y compris si un run échoue.

```bash
gh repo view 0xcssh/spog --json visibility -q .visibility   # avant tout push : PRIVATE
gh repo edit 0xcssh/spog --visibility public  --accept-visibility-change-consequences
gh repo edit 0xcssh/spog --visibility private --accept-visibility-change-consequences
```

Backend : `cd backend && npm test` tourne sous Windows (128 tests, dont les migrations SQL
sur PGlite). Une migration s'applique aussi sur la base Neon, à la main, avant le déploiement
du code qui en dépend.

Sur un Mac, l'ancienne voie marche toujours : `xcodegen generate`, puis `xcodebuild`.

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

Toute donnée nouvelle qui part au serveur doit être dite dans la politique de
confidentialité (`privacy.*` dans le catalogue), puis `py tools/export-legal.py` pour
régénérer `Legal/`. Les pages publiées sur le site doivent ensuite être remplacées.
