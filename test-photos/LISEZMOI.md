# Jeu de test — identification

Trente modèles parmi les plus courants sur les routes françaises. Le but n'est pas
de montrer que l'app marche : c'est de mesurer **où elle échoue**, avant que des
joueurs ne le découvrent à notre place.

## Quelles photos chercher

Des photos **de petites annonces**, pas des photos de presse. Leboncoin, La Centrale,
Facebook Marketplace. Ce qu'on veut ressemble à ça :

- prise au téléphone, par un particulier ;
- dans la rue ou sur un parking, pas en studio ;
- voiture pas forcément lavée, cadrage approximatif ;
- de trois-quarts, de côté, de face — varie les angles, c'est le but.

Ce qu'il faut **éviter** :

- les photos de presse du constructeur : l'IA les reconnaît trop facilement et le
  résultat serait flatteur et faux ;
- les **captures d'écran** : l'anti-triche détecte les photos d'écran (moiré, bords
  de fenêtre) et refusera la photo, à juste titre. Enregistre l'image, ne capture pas
  l'écran.

## Comment nommer

Le nom du fichier doit correspondre exactement à la colonne `fichier` de `verite.csv`.
Par exemple la photo de Clio s'appelle `renault-clio.jpg`.

## La colonne couleur

Facultative, mais c'est elle qui vérifie la promesse « on scanne une voiture bleue,
la carte est bleue ». Remplis-la avec **un seul** de ces mots, en anglais :

    white, black, silver, grey, red, blue, dark blue, green,
    yellow, orange, purple, teal, brown, beige

Laisse vide si la teinte est ambiguë — mieux vaut ne rien mesurer que mesurer faux.

## Lancer la mesure

    python3 tools/score-identification.py test-photos --dry-run          # annonce la facture
    python3 tools/score-identification.py test-photos --verite test-photos/verite.csv

Environ un demi-centime de dollar par photo. Le script demande confirmation avant
le premier appel et écrit le détail dans `resultats-identification.csv`.
