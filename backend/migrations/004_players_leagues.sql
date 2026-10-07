-- Joueurs, prises, premiers repéreurs et ligues hebdomadaires (REFONTE.md, social).
-- Idempotent : peut être rejoué sur une base existante.
--
-- Un joueur existe dès sa première requête, sans rien demander : il est identifié par
-- son installation (identifiant du trousseau, dont on ne garde que l'empreinte). Sign in
-- with Apple ne sert qu'à retrouver ce joueur sur un autre appareil ou après une
-- réinitialisation. Le pseudo est facultatif tant qu'on ne veut pas apparaître nommé.

create table if not exists public.players (
  id          uuid        primary key default gen_random_uuid(),
  pseudo      text,
  apple_sub   text        unique,      -- identifiant Apple propre à l'équipe, jamais l'e-mail
  created_at  timestamptz not null default now()
);
-- Unicité insensible à la casse : « Keno » et « keno » sont le même pseudo.
create unique index if not exists players_pseudo_idx on public.players (lower(pseudo));

create table if not exists public.installs (
  install_hash text        primary key,
  player_id    uuid        not null references public.players(id) on delete cascade,
  created_at   timestamptz not null default now()
);

-- Chaque identification réussie laisse une trace : c'est elle qui permet au serveur de
-- vérifier qu'une prise déclarée correspond à une photo réellement identifiée, et non à
-- une Ferrari inventée.
create table if not exists public.scans (
  id               uuid        primary key,
  install_hash     text        not null,
  expected_vehicle text        not null,
  candidate_ids    text[]      not null default '{}',
  confidence       real        not null,
  created_at       timestamptz not null default now(),
  used_at          timestamptz
);
create index if not exists scans_created_idx on public.scans (created_at);

create table if not exists public.catches (
  id                uuid        primary key,          -- identifiant choisi par l'app
  player_id         uuid        not null references public.players(id) on delete cascade,
  vehicle_id        text        not null,
  country           text        not null,
  caught_at         timestamptz not null,
  location_verified boolean     not null,             -- pays relevé par la position
  vehicle_verified  boolean     not null,             -- le modèle correspond à l'identification
  scan_id           uuid,
  tier              text        not null,
  points            integer     not null,             -- valeur de la carte, toujours affichée
  counted_points    integer     not null default 0,   -- ce qui est entré au classement
  league_week       date,
  first_spot        boolean     not null default false,
  created_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index if not exists catches_player_idx on public.catches (player_id);

-- Le premier joueur à attraper un modèle dans un pays : crédité à vie.
create table if not exists public.first_spots (
  vehicle_id  text        not null,
  country     text        not null,
  player_id   uuid        not null references public.players(id) on delete cascade,
  catch_id    uuid        not null,
  caught_at   timestamptz not null,
  primary key (vehicle_id, country)
);

-- Ligues : groupes de 30 joueurs du même palier, remis à zéro chaque lundi (UTC). Les
-- premiers montent, les derniers descendent — on joue pour ne pas redescendre.
create table if not exists public.league_members (
  week       date        not null,
  player_id  uuid        not null references public.players(id) on delete cascade,
  tier       smallint    not null,
  group_no   integer     not null,
  points     integer     not null default 0,
  joined_at  timestamptz not null default now(),
  primary key (week, player_id)
);
create index if not exists league_group_idx on public.league_members (week, tier, group_no);

-- Semaine courante : le lundi, en UTC.
create or replace function public.current_week() returns date
language sql stable as $$
  select date_trunc('week', now() at time zone 'UTC')::date;
$$;

-- Joueur d'une installation, créé au besoin.
create or replace function public.player_for_install(p_install_hash text) returns uuid
language plpgsql as $$
declare
  v_player  uuid;
  v_created uuid;
begin
  select player_id into v_player from public.installs where install_hash = p_install_hash;
  if v_player is not null then return v_player; end if;
  insert into public.players default values returning id into v_created;
  insert into public.installs (install_hash, player_id) values (p_install_hash, v_created)
  on conflict (install_hash) do nothing;
  -- Deux premières requêtes simultanées : celle qui a perdu la course rejoint l'autre,
  -- et le joueur qu'elle venait de créer pour rien disparaît.
  select player_id into v_player from public.installs where install_hash = p_install_hash;
  if v_player <> v_created then delete from public.players where id = v_created; end if;
  return v_player;
end;
$$;

-- Palier d'un joueur pour une semaine, d'après son classement de la semaine précédente.
-- Paramètres : taille de groupe, nombre de promus et de relégués, palier maximal.
create or replace function public.league_tier_for(p_player uuid, p_week date,
  p_promote integer default 7, p_demote integer default 5, p_max_tier integer default 5)
returns smallint
language plpgsql stable as $$
declare
  prev   public.league_members;
  v_rank integer;
  v_size integer;
begin
  select * into prev from public.league_members
   where player_id = p_player and week < p_week order by week desc limit 1;
  if not found then return 0; end if;
  -- Une absence d'une semaine ou plus ne promeut ni ne relègue : on reprend où on était.
  if prev.week < p_week - 7 then return prev.tier; end if;
  select count(*) into v_size from public.league_members
   where week = prev.week and tier = prev.tier and group_no = prev.group_no;
  select count(*) + 1 into v_rank from public.league_members
   where week = prev.week and tier = prev.tier and group_no = prev.group_no
     and (points > prev.points or (points = prev.points and joined_at < prev.joined_at));
  if v_rank <= p_promote and prev.points > 0 then return least(prev.tier + 1, p_max_tier); end if;
  -- Pas de relégation dans un groupe trop petit pour qu'elle ait un sens.
  if v_size >= p_promote + p_demote and v_rank > v_size - p_demote then return greatest(prev.tier - 1, 0); end if;
  return prev.tier;
end;
$$;

-- Inscrit le joueur dans un groupe de la semaine, s'il n'y est pas déjà.
create or replace function public.join_league(p_player uuid, p_week date, p_group_size integer default 30)
returns public.league_members
language plpgsql as $$
declare
  m       public.league_members;
  v_tier  smallint;
  v_group integer;
begin
  select * into m from public.league_members where week = p_week and player_id = p_player;
  if found then return m; end if;
  v_tier := public.league_tier_for(p_player, p_week);
  -- Un verrou par palier et par semaine : deux inscriptions simultanées ne doivent pas
  -- remplir le même groupe au-delà de sa taille.
  perform pg_advisory_xact_lock(hashtext('league:' || p_week::text || ':' || v_tier::text));
  select group_no into v_group from public.league_members
   where week = p_week and tier = v_tier
   group by group_no having count(*) < p_group_size
   order by group_no limit 1;
  if v_group is null then
    select coalesce(max(group_no), 0) + 1 into v_group from public.league_members
     where week = p_week and tier = v_tier;
  end if;
  insert into public.league_members (week, player_id, tier, group_no)
  values (p_week, p_player, v_tier, v_group)
  on conflict (week, player_id) do nothing;
  select * into m from public.league_members where week = p_week and player_id = p_player;
  return m;
end;
$$;

-- Enregistre une prise. Idempotent sur l'identifiant : l'app peut renvoyer une prise
-- dont elle n'a pas reçu la réponse sans la compter deux fois.
-- Ne compte au classement que si le pays ET le modèle sont vérifiés ; le premier
-- repéreur d'un modèle dans un pays reçoit `p_first_bonus` points de plus.
create or replace function public.record_catch(
  p_catch_id uuid, p_player uuid, p_vehicle text, p_country text, p_caught_at timestamptz,
  p_location_verified boolean, p_vehicle_verified boolean, p_scan_id uuid,
  p_tier text, p_points integer, p_first_bonus integer)
returns jsonb
language plpgsql as $$
declare
  c        public.catches;
  v_counts boolean := p_location_verified and p_vehicle_verified;
  v_first  boolean := false;
  v_total  integer := 0;
  v_week   date := public.current_week();
  m        public.league_members;
begin
  select * into c from public.catches where id = p_catch_id;
  if found then
    if c.player_id <> p_player then return jsonb_build_object('error', 'not_owner'); end if;
    return jsonb_build_object('duplicate', true, 'points', c.points, 'counted_points', c.counted_points,
                              'first_spot', c.first_spot, 'tier', c.tier);
  end if;

  if v_counts then
    insert into public.first_spots (vehicle_id, country, player_id, catch_id, caught_at)
    values (p_vehicle, p_country, p_player, p_catch_id, now())
    on conflict do nothing;
    v_first := found;
    v_total := p_points + case when v_first then p_first_bonus else 0 end;
  end if;

  insert into public.catches (id, player_id, vehicle_id, country, caught_at, location_verified,
    vehicle_verified, scan_id, tier, points, counted_points, league_week, first_spot)
  values (p_catch_id, p_player, p_vehicle, p_country, p_caught_at, p_location_verified,
    p_vehicle_verified, p_scan_id, p_tier, p_points, v_total,
    case when v_total > 0 then v_week end, v_first);

  if p_scan_id is not null then
    update public.scans set used_at = now() where id = p_scan_id and used_at is null;
  end if;

  if v_total > 0 then
    m := public.join_league(p_player, v_week);
    update public.league_members set points = points + v_total
     where week = v_week and player_id = p_player
     returning * into m;
  end if;

  return jsonb_build_object('duplicate', false, 'points', p_points, 'counted_points', v_total,
                            'first_spot', v_first, 'tier', p_tier,
                            'league_tier', m.tier, 'league_points', m.points);
end;
$$;

-- Retire du classement ce qu'une prise y avait apporté, si c'était cette semaine.
-- Sert à la suppression comme à la correction du modèle.
create or replace function public.uncount_catch(p_catch_id uuid) returns void
language plpgsql as $$
declare c public.catches;
begin
  select * into c from public.catches where id = p_catch_id for update;
  if not found or c.counted_points = 0 then return; end if;
  if c.league_week = public.current_week() then
    update public.league_members set points = greatest(0, points - c.counted_points)
     where week = c.league_week and player_id = c.player_id;
  end if;
  update public.catches set counted_points = 0 where id = p_catch_id;
end;
$$;

-- Rattache une installation au compte Apple. Si ce compte existe déjà (autre appareil,
-- réinstallation), l'installation le rejoint et y apporte ses prises.
create or replace function public.link_apple(p_install_hash text, p_sub text) returns uuid
language plpgsql as $$
declare
  v_current uuid := public.player_for_install(p_install_hash);
  v_owner   uuid;
begin
  select id into v_owner from public.players where apple_sub = p_sub;
  if v_owner is null then
    update public.players set apple_sub = p_sub where id = v_current;
    return v_current;
  end if;
  if v_owner = v_current then return v_current; end if;
  update public.installs set player_id = v_owner where install_hash = p_install_hash;
  -- Le joueur anonyme rejoint le compte : ses prises le suivent, pas son classement de
  -- la semaine (deux inscriptions la même semaine ne se fusionnent pas proprement).
  update public.catches set player_id = v_owner where player_id = v_current;
  update public.first_spots set player_id = v_owner where player_id = v_current;
  delete from public.league_members where player_id = v_current;
  delete from public.players p where p.id = v_current
    and not exists (select 1 from public.installs i where i.player_id = p.id);
  return v_owner;
end;
$$;
