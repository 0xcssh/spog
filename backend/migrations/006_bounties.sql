-- Pack de primes de la semaine : qui a ouvert son pack, qui a trouvé quelle cible.
-- Les cibles elles-mêmes ne sont pas stockées : elles se recalculent à l'identique depuis
-- la semaine et le pays (backend/functions/identify/bounty.ts).
-- Idempotent : peut être rejoué sur une base existante.

create table if not exists public.bounty_opens (
  week      date        not null,
  player_id uuid        not null references public.players(id) on delete cascade,
  opened_at timestamptz not null default now(),
  primary key (week, player_id)
);

create table if not exists public.bounty_claims (
  week       date        not null,
  country    text        not null,
  vehicle_id text        not null,
  player_id  uuid        not null references public.players(id) on delete cascade,
  catch_id   uuid        not null,
  first      boolean     not null,
  bonus      integer     not null,
  claimed_at timestamptz not null default now(),
  primary key (week, country, vehicle_id, player_id)
);

-- Encaisse une cible trouvée : une seule fois par joueur et par cible, le premier du pays
-- prend en plus `p_first_bonus`. Le bonus entre au classement de la semaine et s'ajoute
-- aux points comptés de la prise (une suppression de la carte le retire avec elle).
create or replace function public.claim_bounty(
  p_week date, p_country text, p_vehicle text, p_player uuid, p_catch uuid,
  p_bonus integer, p_first_bonus integer)
returns jsonb
language plpgsql as $$
declare
  v_first boolean;
  v_total integer;
begin
  -- Un verrou par cible : deux joueurs qui la trouvent à la même seconde ne peuvent pas
  -- être premiers tous les deux.
  perform pg_advisory_xact_lock(hashtext('bounty:' || p_week::text || ':' || p_country || ':' || p_vehicle));
  if exists (select 1 from public.bounty_claims
              where week = p_week and country = p_country and vehicle_id = p_vehicle and player_id = p_player) then
    return jsonb_build_object('claimed', false);
  end if;
  v_first := not exists (select 1 from public.bounty_claims
                          where week = p_week and country = p_country and vehicle_id = p_vehicle);
  v_total := p_bonus + case when v_first then p_first_bonus else 0 end;
  insert into public.bounty_claims (week, country, vehicle_id, player_id, catch_id, first, bonus)
  values (p_week, p_country, p_vehicle, p_player, p_catch, v_first, v_total);
  update public.catches set counted_points = counted_points + v_total where id = p_catch;
  perform public.join_league(p_player, p_week);
  update public.league_members set points = points + v_total where week = p_week and player_id = p_player;
  return jsonb_build_object('claimed', true, 'first', v_first, 'bonus', v_total);
end;
$$;
