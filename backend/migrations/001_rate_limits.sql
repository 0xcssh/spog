-- Quotas anti-abus de la fonction Neon `identify`. Repris de Cyranox, où la même
-- table a remplacé celle de Supabase.
-- Idempotent : peut être rejoué sur une base existante.
-- Jours et mois comptés en UTC, quel que soit le fuseau de la session.

create table if not exists public.rate_limits (
  device_hash   text        primary key,          -- SHA-256 de "spog:<clé>" — jamais d'ID ni d'IP brute
  day           date        not null default (now() at time zone 'UTC')::date,
  day_count     integer     not null default 0,
  window_start  timestamptz not null default now(),
  window_count  integer     not null default 0,
  month         date        not null default date_trunc('month', now() at time zone 'UTC')::date,
  month_count   integer     not null default 0,
  updated_at    timestamptz not null default now()
);

-- Purge des compteurs inactifs (voir check_rate_limit) : sans elle, la table
-- grossit d'une ligne par appareil et par IP, pour toujours.
create index if not exists rate_limits_updated_at_idx on public.rate_limits (updated_at);

create or replace function public.check_rate_limit(
  p_device_hash    text,
  p_day_limit      integer,
  p_window_seconds integer,
  p_window_limit   integer,
  p_month_limit    integer default null
) returns jsonb
language plpgsql
as $$
declare
  r public.rate_limits;
  v_today date := (now() at time zone 'UTC')::date;
  v_month date := date_trunc('month', now() at time zone 'UTC')::date;
begin
  -- Ligne créée au besoin, puis verrouillée : deux appels simultanés pour la
  -- même clé se sérialisent sur le FOR UPDATE.
  insert into public.rate_limits (device_hash) values (p_device_hash)
  on conflict (device_hash) do nothing;

  select * into r from public.rate_limits where device_hash = p_device_hash for update;

  if r.day <> v_today then r.day := v_today; r.day_count := 0; end if;
  if r.month <> v_month then r.month := v_month; r.month_count := 0; end if;
  if r.window_start < now() - make_interval(secs => p_window_seconds) then
    r.window_start := now(); r.window_count := 0;
  end if;

  if r.day_count >= p_day_limit
     or r.window_count >= p_window_limit
     or (p_month_limit is not null and r.month_count >= p_month_limit) then
    update public.rate_limits set
      day = r.day, day_count = r.day_count, month = r.month, month_count = r.month_count,
      window_start = r.window_start, window_count = r.window_count, updated_at = now()
    where device_hash = p_device_hash;
    return jsonb_build_object('allowed', false);
  end if;

  update public.rate_limits set
    day = r.day, day_count = r.day_count + 1,
    month = r.month, month_count = r.month_count + 1,
    window_start = r.window_start, window_count = r.window_count + 1,
    updated_at = now()
  where device_hash = p_device_hash;

  -- Ménage occasionnel (~1 appel sur 1000) : une ligne inactive depuis plus de
  -- 40 jours ne porte plus aucun compteur utile.
  if random() < 0.001 then
    delete from public.rate_limits where updated_at < now() - interval '40 days';
  end if;

  return jsonb_build_object('allowed', true);
end;
$$;
