-- Scans offerts, comptés par installation. Le serveur en est l'autorité : tant que
-- le décompte vivait dans l'app, une réinstallation rendait les cinq scans.
-- Idempotent : peut être rejoué sur une base existante.

create table if not exists public.free_scans (
  install_hash text        primary key,   -- SHA-256 de "spog:<identifiant d'installation>"
  used         integer     not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Incrément atomique : deux scans simultanés de la même installation ne peuvent pas
-- lire le même compteur et n'en consommer qu'un.
create or replace function public.consume_free_scan(p_install_hash text) returns integer
language sql
as $$
  insert into public.free_scans (install_hash, used) values (p_install_hash, 1)
  on conflict (install_hash) do update
    set used = public.free_scans.used + 1, updated_at = now()
  returning used;
$$;
