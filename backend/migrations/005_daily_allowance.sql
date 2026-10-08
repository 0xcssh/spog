-- Quotas quotidiens du joueur gratuit (REFONTE.md, « Économie », décidée le 08/10/2026).
-- Remplacent les cinq scans offerts à vie : 10 scans le premier jour, puis 3 par jour, et
-- 1 rendu « développé » par jour. Pro n'y est pas soumis (il garde le plafond anti-abus).
-- Idempotent : peut être rejoué sur une base existante.
--
-- Les jours sont comptés en UTC. Un découpage à l'heure locale du joueur serait plus juste,
-- mais l'heure locale vient de l'appareil : la changer offrirait un jour neuf à volonté.

create table if not exists public.install_days (
  install_hash text primary key,
  first_day    date not null default (now() at time zone 'UTC')::date
);

create table if not exists public.usage_days (
  install_hash text    not null,
  day          date    not null,
  kind         text    not null,          -- 'scan' | 'develop'
  used         integer not null default 0,
  primary key (install_hash, day, kind)
);

-- Ce qui reste aujourd'hui pour une installation, sans rien consommer. Le premier jour
-- est celui de la première requête de l'installation, enregistrée au passage.
create or replace function public.allowance_left(
  p_install_hash text, p_kind text, p_first_day_limit integer, p_daily_limit integer)
returns integer
language plpgsql as $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_first date;
  v_used  integer;
begin
  insert into public.install_days (install_hash) values (p_install_hash)
  on conflict (install_hash) do nothing;
  select first_day into v_first from public.install_days where install_hash = p_install_hash;
  select coalesce(used, 0) into v_used from public.usage_days
   where install_hash = p_install_hash and day = v_today and kind = p_kind;
  return greatest(0, (case when v_first = v_today then p_first_day_limit else p_daily_limit end)
                     - coalesce(v_used, 0));
end;
$$;

-- Consomme une unité du jour et renvoie le total consommé aujourd'hui. Incrément atomique :
-- deux scans simultanés ne lisent pas le même compteur.
create or replace function public.consume_allowance(p_install_hash text, p_kind text) returns integer
language sql as $$
  insert into public.usage_days (install_hash, day, kind, used)
  values (p_install_hash, (now() at time zone 'UTC')::date, p_kind, 1)
  on conflict (install_hash, day, kind) do update set used = public.usage_days.used + 1
  returning used;
$$;
