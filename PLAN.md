# Spog — état du projet

*Dernière mise à jour : 08/10/2026.*

Ce fichier dit **où on en est, ce qui marche, ce qui bloque**. Pour les conventions de
travail, voir [CLAUDE.md](CLAUDE.md). La refonte lancée le 07/10/2026 — sans Mac, backend
Neon, scans offerts tenus par le serveur, collecte pour le classifieur — a son propre
suivi dans [REFONTE.md](REFONTE.md).

---

## L'app en une phrase

Tu photographies une voiture dans la rue, l'IA l'identifie, elle devient une carte de
collection dans ton garage — et sa rareté dépend du pays où tu l'as croisée. Une Clio ne
vaut rien à Paris et beaucoup à Los Angeles.

## Ce qui marche, vérifié

| | État |
|---|---|
| Identification réelle de bout en bout | **13 photos d'annonces sur 13** correctement identifiées (28/09/2026) |
| Couleur détectée | 9 sur 10 des photos dont la teinte était assez nette pour servir de référence |
| Catalogue | 867 véhicules, dont 274 modèles français écrits à la main |
| Rareté | Calibrée pour `EU_WEST`, `EU_NORTH`, `EU_EAST`, `NA`, `ASIA_SE` |
| Catalogue auto-apprenant | Un modèle inconnu entre au catalogue au premier scan |
| Correction d'identification | « Corriger le modèle » depuis la fiche d'une carte |
| Tests | App : tous au vert en CI (1 défaut connu : Vision en simulateur). Backend : 63 |
| Paywall | 5 scans offerts **décomptés par le serveur**, 7 €/mois ou 60 €/an, essai 3 jours |
| Build | Signé avec le compte Mandalore depuis la CI, IPA installable par USB |
| Parrainage | Code personnel, saisie, liens `spog://invite/XXXXXX` |
| Quêtes, série, Spogdex, partage | Faits |
| Documents légaux | FR et EN, conformes au comportement réel |
| Manifeste de confidentialité | Présent et vérifié embarqué |

## Ce qui bloque — et tout est côté Apple

Le build signé fonctionne depuis le 07/10/2026 (compte Mandalore LLC, équipe `GXS33F5JT9`).
Reste, dans App Store Connect :

1. **La fiche de l'app** (bundle `com.mandalore-group.spog`) : sans elle, pas d'envoi sur
   TestFlight. L'IPA de développement s'installe déjà par USB.
2. **Les deux produits** — `com.mandaloregroup.spog.premium.monthly` et `.yearly` — et le
   contrat « Paid Applications » de la LLC. Sans eux, le paywall ne peut rien vendre.
3. **Le solde OpenAI.** Si le crédit est à zéro, tous les scans échouent. `identify`
   distingue ce cas d'une panne passagère et l'écrit en clair dans les journaux.

## Décisions qui attendent une réponse

**Le lot d'illustrations.** 31 modèles sur 867 en ont une, et seulement 6 des 30 voitures les
plus courantes en France. Deux options chiffrées : 205 illustrations pour couvrir les
modèles courants, ou 450 pour la couverture complète.

⚠️ Mais **leur valeur a baissé le 07/10/2026** : depuis que la photo du joueur prime sur le
rendu studio, les illustrations ne servent plus qu'au Spogdex — montrer ce qu'il reste à
trouver — et non plus à habiller les cartes attrapées. À rechiffrer avant de lancer.

**Le marché thaïlandais.** Étudié le 28/09/2026 : iOS à 36 %, dépense en jeu la plus intense
d'Asie du Sud-Est, culture automobile vivante, rareté déjà calibrée pour la région. Deux
obstacles réels — l'app n'existe pas en thaï (254 textes), et le marché achète des **packs**
plutôt que des abonnements. Prix à viser : 99 bahts/mois, l'ancrage de Netflix Mobile.
Décision prise : **la France d'abord.**

**La cote d'occasion — revenue le 08/10/2026, à la demande du client, en devise locale.**
Retirée le 28/09/2026 (commit `d381c76`) parce qu'elle faisait une seconde échelle de valeur
à côté de la rareté, et surtout parce qu'elle était en euros pour tout le monde. Elle revient
sans cette faute : l'app envoie le pays de la prise, le serveur demande à l'IA la valeur de
revente typique **sur le marché de ce pays, dans sa devise** (`currencies` de `markets.json`,
une donnée : ajouter un pays, c'est aussi ajouter sa devise). Sans pays, pas de cote.
Toujours une fourchette, toujours « Cote approximative », figée à la capture, effacée si le
joueur corrige le modèle. Garde-fous serveur repris (`backend/functions/identify/price.ts`) ;
le plafond de 3 M passe en dollars, estimé par l'IA, puisque trois millions de yens sont une
citadine. Affichée sur la carte, sur sa fiche, et en tête de l'écran Collection (« Ton
garage ») : la **valeur estimée du garage**, somme des milieux de fourchette dans la devise
qui compte le plus de cartes, les autres devises nommées et jamais converties.
⚠️ Reste à vérifier sur de vraies prises que la rareté et la cote ne se contredisent pas
aux yeux des joueurs — c'était la raison du premier retrait. Déploiement du backend requis.

**Le signal « concession ».** Idée du 28/09/2026 : refuser une photo prise en concession.
Recommandation retenue — **un signal, pas un refus** : la carte est créée mais non
« vérifiée », donc elle ne compte pas au classement. Un refus sec volerait une prise sur
cinq à chaque faux positif, et ils seraient fréquents. Pas encore implémenté.

**La rotation « 4D ».** Une photo ne peut pas tourner : il n'y a qu'un point de vue. Le
parallaxe existant (`ParallaxArtwork`) est ce qui s'en approche le plus et marche sur
n'importe quelle photo. Piste retenue : l'accentuer plutôt que chercher une vraie 3D.

## Ce qui n'a jamais été fait, et qui compte

**Aucun scan depuis un vrai téléphone, dans une vraie rue.** Les 13/13 viennent de photos
d'annonces : de jour, par temps sec, voiture dégagée. La rue apportera la nuit, la pluie,
les voitures à moitié cachées. Le chiffre baissera — la question est de combien.

C'est le dernier risque sérieux avant publication, et aucun test de simulateur ne peut y
répondre.

## Sauvegarde — réglée

Depuis le 07/10/2026, le dépôt vit sur GitHub (`0xcssh/spog`, privé), historique complet.

## Repères de coût

| | |
|---|---|
| Un scan | 0,44 centime d'euro |
| 229 scans | 1 € |
| Un joueur à 30 scans/mois | 0,13 € — pour 4,96 € net encaissés |
| Les 5 scans offerts | 2,2 centimes par installation |
| Plafond global actuel | 5 000/jour, soit 25 $/jour maximum |
