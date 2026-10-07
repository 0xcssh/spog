-- Photos d'entraînement du futur classifieur embarqué (REFONTE.md, phase 3).
--
-- Une ligne n'existe que si le joueur l'a accepté explicitement, et le retrait de
-- son accord efface toutes ses lignes et leurs images (action "forget"). La photo
-- elle-même vit dans le compartiment privé `training` du stockage Neon ; les plaques
-- y sont déjà floutées, l'app les masque avant tout envoi.
--
-- Deux étiquettes : celle de l'IA, toujours présente, et celle du joueur, quand il a
-- confirmé ou corrigé le modèle — c'est elle qui vaut vérité pour l'entraînement.

create table if not exists public.training_samples (
  id              uuid        primary key,
  install_hash    text        not null,       -- même empreinte que free_scans, jamais l'ID brut
  object_key      text        not null,
  ai_make         text        not null,
  ai_model        text        not null,
  ai_generation   text        not null default '',
  ai_body         text        not null,
  ai_color        text        not null default '',
  ai_confidence   real        not null,
  label_vehicle   text,                       -- identifiant du catalogue choisi par le joueur
  label_source    text,                       -- confirmed | corrected
  labeled_at      timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists training_samples_install_idx on public.training_samples (install_hash);
