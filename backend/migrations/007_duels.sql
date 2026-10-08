-- Duels entre amis (REFONTE.md, « Social ») : sept jours, celui qui marque le plus gagne.
-- Le score n'est pas stocké : c'est la somme des points comptés des prises de chacun
-- pendant le duel (`catches.counted_points`, primes comprises), recalculée à la lecture.
-- Rien à tenir à jour, rien qui puisse diverger du classement.
-- Idempotent : peut être rejoué sur une base existante.

create table if not exists public.duels (
  id            uuid        primary key default gen_random_uuid(),
  code          text        not null unique,     -- à partager : spog://duel/CODE
  challenger_id uuid        not null references public.players(id) on delete cascade,
  opponent_id   uuid        references public.players(id) on delete cascade,
  created_at    timestamptz not null default now(),
  starts_at     timestamptz,
  ends_at       timestamptz
);
create index if not exists duels_challenger_idx on public.duels (challenger_id);
create index if not exists duels_opponent_idx on public.duels (opponent_id);

-- Points comptés d'un joueur sur une période.
create or replace function public.points_between(p_player uuid, p_from timestamptz, p_to timestamptz)
returns integer
language sql stable as $$
  select coalesce(sum(counted_points), 0)::int from public.catches
   where player_id = p_player and deleted_at is null
     and created_at >= p_from and created_at < p_to;
$$;

-- Rejoindre un duel : une seule fois, jamais le sien, et le chrono part à ce moment-là.
create or replace function public.join_duel(p_code text, p_player uuid, p_days integer default 7)
returns jsonb
language plpgsql as $$
declare d public.duels;
begin
  select * into d from public.duels where code = upper(p_code) for update;
  if not found then return jsonb_build_object('error', 'unknown'); end if;
  if d.challenger_id = p_player then return jsonb_build_object('error', 'own'); end if;
  if d.opponent_id is not null then
    if d.opponent_id = p_player then return jsonb_build_object('ok', true, 'id', d.id); end if;
    return jsonb_build_object('error', 'taken');
  end if;
  update public.duels set opponent_id = p_player, starts_at = now(),
         ends_at = now() + make_interval(days => p_days)
   where id = d.id;
  return jsonb_build_object('ok', true, 'id', d.id);
end;
$$;
