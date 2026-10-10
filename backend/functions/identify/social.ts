// Le jeu à plusieurs : joueur, pseudo, compte Apple, prises, ligues.
//
// Le serveur compte les points (rareté du catalogue, voir catalog.ts) et décide de ce qui
// entre au classement. Une prise n'y entre que si :
//   - son pays a été relevé par la position (pas choisi à la main) ;
//   - son modèle correspond à une identification réellement faite par ce serveur pour
//     cette installation — le modèle retenu par l'IA, ou l'une des propositions qu'on a
//     montrées au joueur. Corriger un Clio en Ferrari garde la carte, pas les points.
// Le reste — carte, garage, collection — n'est jamais refusé : la sanction se limite au
// classement, là où tricher fait du tort aux autres.
//
// Actions (POST, en-tête x-install-id) :
//   me · set_pseudo · apple_link · catch · reassign · delete_catch · league · garage · delete_account
//   bounty · open_bounty   (pack de primes de la semaine, voir bounty.ts)
//   duel_create · duel_join · duels   (duels de sept jours entre amis)

import { resolve } from "./catalog";
import { weeklyBounties, currentWeek } from "./bounty";
import type { AppleResult } from "./apple";

export interface Queryable {
  query(text: string, values?: unknown[]): Promise<{ rows: any[] }>;
}

export interface SocialDeps {
  db: Queryable | null;
  verifyApple: (token: unknown) => Promise<AppleResult>;
  now?: () => Date;
}

/// Le premier repéreur d'un modèle dans un pays double la valeur de sa prise.
export const FIRST_SPOT_BONUS_RATIO = 1;
export const LEAGUE_PROMOTE = 7;
export const LEAGUE_DEMOTE = 5;
export const LEAGUE_TIERS = ["bronze", "silver", "gold", "sapphire", "ruby", "diamond"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const PSEUDO = /^[A-Za-z0-9_.]{3,20}$/;

function reply(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}
const unavailable = () => reply({ code: "service_saturated", error: "Le service est momentanément indisponible." }, 503);
const bad = (error: string) => reply({ code: "bad_request", error }, 400);

export const SOCIAL_ACTIONS = ["me", "set_pseudo", "apple_link", "catch", "reassign", "delete_catch", "league", "garage",
  "delete_account", "bounty", "open_bounty", "duel_create", "duel_join", "duels"];

/// Un duel dure une semaine : assez pour que chacun sorte plusieurs fois.
export const DUEL_DAYS = 7;
/// Défis en cours par joueur (en attente compris) : au-delà, le classement des duels
/// devient une corvée, et la création en masse un moyen de spammer des codes.
export const MAX_OPEN_DUELS = 5;
/// Alphabet des codes : sans 0/O ni 1/I/L, qu'on confond en les dictant.
const DUEL_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/// Ce qui redessine une carte sur un autre appareil : numéro, teinte, cote. Le serveur ne
/// s'en sert pour rien d'autre, il ne fait donc que borner. Chaque champ invalide est
/// ignoré seul, sans refuser la prise : la carte compte plus que son décor, et un ancien
/// build qui n'envoie rien doit continuer de marcher.
export interface CardFields {
  serial: number | null;
  paint: number | null;
  price: { low: number; high: number; currency: string } | null;
}

/// Un joueur ne fera pas un million de prises ; au-delà, c'est une valeur fabriquée.
export const SERIAL_MAX = 1_000_000;

export function cardFields(body: Record<string, unknown>): CardFields {
  const int = (v: unknown, min: number, max: number) =>
    typeof v === "number" && Number.isInteger(v) && v >= min && v <= max ? v : null;
  const serial = int(body.serial, 1, SERIAL_MAX);
  const paint = int(body.paint, 0, 0xFFFFFF);
  let price: CardFields["price"] = null;
  const p = body.price;
  if (p && typeof p === "object" && !Array.isArray(p)) {
    const { low, high, currency } = p as Record<string, unknown>;
    // Même plafond que la cote envoyée par identify (price.ts) : une devise faible (dong,
    // roupie) dépasse vite les deux milliards d'un entier 32 bits, pas MAX_SAFE_INTEGER.
    const l = int(low, 1, Number.MAX_SAFE_INTEGER), h = int(high, 1, Number.MAX_SAFE_INTEGER);
    if (l !== null && h !== null && l <= h && typeof currency === "string" && /^[A-Z]{3}$/.test(currency)) {
      price = { low: l, high: h, currency };
    }
  }
  return { serial, paint, price };
}

export function duelCode(random: () => number = Math.random): string {
  let code = "";
  for (let i = 0; i < 6; i++) code += DUEL_ALPHABET[Math.floor(random() * DUEL_ALPHABET.length)];
  return code;
}

export function createSocial(deps: SocialDeps) {
  const now = deps.now ?? (() => new Date());

  async function playerOf(installHash: string): Promise<string> {
    const { rows } = await deps.db!.query("select public.player_for_install($1) as id", [installHash]);
    return rows[0].id;
  }

  async function profile(player: string) {
    const { rows } = await deps.db!.query(
      `select p.pseudo, p.apple_sub is not null as apple_linked,
              (select count(*)::int from public.catches c where c.player_id = p.id and c.deleted_at is null) as catches,
              (select coalesce(sum(points), 0)::int from public.catches c where c.player_id = p.id and c.deleted_at is null) as points,
              (select count(*)::int from public.first_spots f where f.player_id = p.id) as first_spots
         from public.players p where p.id = $1`, [player]);
    return rows[0];
  }

  /// Le modèle déclaré correspond-il à une identification faite ici, pour cette installation ?
  async function vehicleVerified(installHash: string, scanId: unknown, vehicleId: string, requireUnused: boolean) {
    if (typeof scanId !== "string" || !UUID.test(scanId)) return { verified: false, scan: null as string | null };
    const { rows } = await deps.db!.query(
      `select id, expected_vehicle, candidate_ids from public.scans
        where id = $1 and install_hash = $2 and created_at > now() - interval '2 days'
          ${requireUnused ? "and used_at is null" : ""}`, [scanId, installHash]);
    const scan = rows[0];
    if (!scan) return { verified: false, scan: null };
    const verified = scan.expected_vehicle === vehicleId || (scan.candidate_ids ?? []).includes(vehicleId);
    return { verified, scan: scan.id as string };
  }

  function nextMonday(): string {
    const d = now();
    const day = (d.getUTCDay() + 6) % 7; // lundi = 0
    const monday = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - day + 7);
    return new Date(monday).toISOString();
  }

  const handlers: Record<string, (installHash: string, body: Record<string, unknown>) => Promise<Response>> = {
    async me(installHash) {
      const player = await playerOf(installHash);
      return reply({ player_id: player, ...(await profile(player)) });
    },

    async set_pseudo(installHash, body) {
      const pseudo = typeof body.pseudo === "string" ? body.pseudo.trim() : "";
      if (!PSEUDO.test(pseudo)) return reply({ code: "pseudo_invalid", error: "Pseudo invalide" }, 400);
      const player = await playerOf(installHash);
      try {
        await deps.db!.query("update public.players set pseudo = $2 where id = $1", [player, pseudo]);
      } catch (error: any) {
        if (error?.code === "23505") return reply({ code: "pseudo_taken", error: "Ce pseudo est déjà pris" }, 409);
        throw error;
      }
      return reply({ ok: true, pseudo });
    },

    async apple_link(installHash, body) {
      const result = await deps.verifyApple(body.identity_token);
      if (!result.ok) return reply({ code: "apple_invalid", error: "Connexion Apple refusée" }, 401);
      const { rows } = await deps.db!.query("select public.link_apple($1, $2) as id", [installHash, result.sub]);
      const player = rows[0].id;
      return reply({ player_id: player, ...(await profile(player)) });
    },

    async catch(installHash, body) {
      const catchId = typeof body.catch_id === "string" ? body.catch_id : "";
      const vehicleId = typeof body.vehicle_id === "string" ? body.vehicle_id.trim() : "";
      const country = typeof body.country === "string" ? body.country.trim().toUpperCase() : "";
      if (!UUID.test(catchId) || !vehicleId || vehicleId.length > 120 || !/^[A-Z]{2}$/.test(country)) {
        return bad("Prise invalide");
      }
      // L'heure de la prise vient de l'app (une prise peut partir plus tard, hors réseau),
      // mais jamais dans le futur ni il y a plus d'un an.
      const declared = typeof body.caught_at === "string" ? Date.parse(body.caught_at) : NaN;
      const nowMs = now().getTime();
      const caughtAt = new Date(Number.isNaN(declared) ? nowMs : Math.min(nowMs, Math.max(declared, nowMs - 365 * 86_400_000)));

      const player = await playerOf(installHash);
      const { verified, scan } = await vehicleVerified(installHash, body.scan_id, vehicleId, true);
      const tier = resolve(vehicleId, country);
      const { rows } = await deps.db!.query(
        "select public.record_catch($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) as r",
        [catchId, player, vehicleId, country, caughtAt.toISOString(), body.location_verified === true,
         verified, scan, tier.id, tier.points, Math.round(tier.points * FIRST_SPOT_BONUS_RATIO)]);
      const result = rows[0].r;
      if (result.error === "not_owner") return reply({ code: "not_owner", error: "Prise inconnue" }, 403);

      // Hors de record_catch, qui ne concerne que le classement. Ne remplit que ce qui
      // manque : une prise renvoyée ne réécrit pas la carte déjà gardée.
      const card = cardFields(body);
      if (card.serial !== null || card.paint !== null || card.price !== null) {
        await deps.db!.query(
          `update public.catches set serial = coalesce(serial, $3::int), paint = coalesce(paint, $4::bigint),
                  price_low      = case when price_low is null then $5::bigint else price_low end,
                  price_high     = case when price_low is null then $6::bigint else price_high end,
                  price_currency = case when price_low is null then $7::text else price_currency end
            where id = $1 and player_id = $2`,
          [catchId, player, card.serial, card.paint, card.price?.low ?? null, card.price?.high ?? null,
           card.price?.currency ?? null]);
      }

      // Une cible du pack de la semaine, trouvée pour de vrai : seulement si la prise compte
      // au classement (même exigence de pays et de modèle vérifiés), et une fois par joueur.
      let bounty: unknown = null;
      if (!result.duplicate && result.counted_points > 0) {
        const week = currentWeek(now());
        const target = weeklyBounties(week, country).find((t) => t.vehicle.id === vehicleId);
        if (target) {
          const { rows: claim } = await deps.db!.query(
            "select public.claim_bounty($1,$2,$3,$4,$5,$6,$7) as r",
            [week, country, vehicleId, player, catchId, target.bonus, target.firstBonus]);
          if (claim[0].r.claimed) bounty = claim[0].r;
        }
      }
      return reply({ ...result, vehicle_verified: verified, bounty,
                     league_tier: result.league_tier == null ? null : LEAGUE_TIERS[result.league_tier] });
    },

    async reassign(installHash, body) {
      const catchId = typeof body.catch_id === "string" ? body.catch_id : "";
      const vehicleId = typeof body.vehicle_id === "string" ? body.vehicle_id.trim() : "";
      if (!UUID.test(catchId) || !vehicleId || vehicleId.length > 120) return bad("Correction invalide");
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query(
        "select * from public.catches where id = $1 and player_id = $2 and deleted_at is null", [catchId, player]);
      const c = rows[0];
      if (!c) return reply({ code: "not_owner", error: "Prise inconnue" }, 403);
      await deps.db!.query("select public.uncount_catch($1)", [catchId]);
      // La correction peut rendre la prise juste (le joueur choisit l'une des propositions)
      // ou la sortir du classement. Elle ne crée jamais de premier repéreur après coup.
      const { verified } = await vehicleVerified(installHash, c.scan_id, vehicleId, false);
      const tier = resolve(vehicleId, c.country);
      const { rows: weekRows } = await deps.db!.query("select public.current_week()::text as w");
      const counts = verified && c.location_verified && c.league_week !== null &&
        String(c.league_week).slice(0, 10) === weekRows[0].w.slice(0, 10);
      const counted = counts ? tier.points : 0;
      await deps.db!.query(
        `update public.catches set vehicle_id = $2, tier = $3, points = $4, vehicle_verified = $5,
                counted_points = $6 where id = $1`, [catchId, vehicleId, tier.id, tier.points, verified, counted]);
      if (counted > 0) {
        await deps.db!.query(
          "update public.league_members set points = points + $2 where week = public.current_week() and player_id = $1",
          [player, counted]);
      }
      return reply({ ok: true, points: tier.points, counted_points: counted, vehicle_verified: verified, tier: tier.id });
    },

    async delete_catch(installHash, body) {
      const catchId = typeof body.catch_id === "string" ? body.catch_id : "";
      if (!UUID.test(catchId)) return bad("Prise invalide");
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query(
        "select id from public.catches where id = $1 and player_id = $2 and deleted_at is null", [catchId, player]);
      if (!rows[0]) return reply({ ok: true });   // déjà partie : rien à faire
      await deps.db!.query("select public.uncount_catch($1)", [catchId]);
      await deps.db!.query("update public.catches set deleted_at = now() where id = $1", [catchId]);
      return reply({ ok: true });
    },

    async league(installHash) {
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query(
        "select * from public.league_members where week = public.current_week() and player_id = $1", [player]);
      const me = rows[0];
      if (!me) {
        // Pas encore inscrit cette semaine : on dit où il entrera à sa première prise.
        const { rows: t } = await deps.db!.query(
          "select public.league_tier_for($1, public.current_week()) as tier", [player]);
        return reply({ joined: false, tier: LEAGUE_TIERS[t[0].tier], ends_at: nextMonday(),
                       promote: LEAGUE_PROMOTE, demote: LEAGUE_DEMOTE, members: [] });
      }
      const { rows: members } = await deps.db!.query(
        `select m.player_id, m.points, p.pseudo from public.league_members m
           join public.players p on p.id = m.player_id
          where m.week = $1 and m.tier = $2 and m.group_no = $3
          order by m.points desc, m.joined_at asc`, [me.week, me.tier, me.group_no]);
      return reply({
        joined: true, tier: LEAGUE_TIERS[me.tier], ends_at: nextMonday(),
        promote: LEAGUE_PROMOTE, demote: LEAGUE_DEMOTE,
        members: members.map((m, i) => ({ rank: i + 1, pseudo: m.pseudo, points: m.points, me: m.player_id === player })),
      });
    },

    /// Suppression du compte, exigée par l'App Store (5.1.1(v)) pour toute app qui en crée :
    /// pseudo, prises, premiers repéreurs, ligues et rattachement Apple disparaissent. Les
    /// photos d'entraînement s'effacent par l'action "forget", que l'app appelle aussi. Le
    /// décompte des scans offerts, lui, reste : il protège du contournement, pas du joueur.
    async delete_account(installHash) {
      const player = await playerOf(installHash);
      await deps.db!.query("delete from public.players where id = $1", [player]);
      return reply({ ok: true });
    },

    /// Le pack de la semaine du pays demandé. Scellé tant que le joueur ne l'a pas ouvert :
    /// l'ouverture est un moment de l'app, les cibles n'en sont révélées qu'à ce moment-là.
    async bounty(installHash, body) {
      const country = typeof body.country === "string" ? body.country.trim().toUpperCase() : "";
      if (!/^[A-Z]{2}$/.test(country)) return bad("Pays invalide");
      const player = await playerOf(installHash);
      const week = currentWeek(now());
      const { rows: opened } = await deps.db!.query(
        "select 1 from public.bounty_opens where week = $1 and player_id = $2", [week, player]);
      const base = { week, ends_at: nextMonday(), country, opened: opened.length > 0 };
      if (!base.opened) return reply({ ...base, targets: [] });
      const { rows: claims } = await deps.db!.query(
        `select c.vehicle_id, c.player_id, c.first, p.pseudo from public.bounty_claims c
           join public.players p on p.id = c.player_id
          where c.week = $1 and c.country = $2`, [week, country]);
      return reply({
        ...base,
        targets: weeklyBounties(week, country).map((t) => {
          const mine = claims.filter((c) => c.vehicle_id === t.vehicle.id);
          const first = mine.find((c) => c.first);
          return {
            vehicle_id: t.vehicle.id, make: t.vehicle.make, model: t.vehicle.model, body: t.vehicle.body,
            tier: t.tier.id, bonus: t.bonus, first_bonus: t.firstBonus,
            found: mine.some((c) => c.player_id === player),
            hunters: mine.length,
            first_hunter: first ? (first.pseudo ?? null) : undefined,
          };
        }),
      });
    },

    async open_bounty(installHash, body) {
      const player = await playerOf(installHash);
      await deps.db!.query(
        "insert into public.bounty_opens (week, player_id) values ($1, $2) on conflict do nothing",
        [currentWeek(now()), player]);
      return handlers.bounty(installHash, body);
    },

    async duel_create(installHash) {
      const player = await playerOf(installHash);
      const { rows: open } = await deps.db!.query(
        `select count(*)::int as n from public.duels
          where (challenger_id = $1 or opponent_id = $1) and (ends_at is null or ends_at > now())`, [player]);
      if (open[0].n >= MAX_OPEN_DUELS) {
        return reply({ code: "too_many_duels", error: "Trop de duels en cours" }, 409);
      }
      // Un code déjà pris (rarissime : 31^6 combinaisons) se retente.
      for (let attempt = 0; attempt < 5; attempt++) {
        try {
          const code = duelCode();
          await deps.db!.query("insert into public.duels (code, challenger_id) values ($1, $2)", [code, player]);
          return reply({ code });
        } catch (error: any) {
          if (error?.code !== "23505") throw error;
        }
      }
      return unavailable();
    },

    async duel_join(installHash, body) {
      const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
      if (!/^[A-Z0-9]{6}$/.test(code)) return reply({ code: "duel_unknown", error: "Code inconnu" }, 404);
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query("select public.join_duel($1, $2, $3) as r", [code, player, DUEL_DAYS]);
      const r = rows[0].r;
      if (r.error === "unknown") return reply({ code: "duel_unknown", error: "Code inconnu" }, 404);
      if (r.error === "own") return reply({ code: "duel_own", error: "C'est ton propre défi" }, 409);
      if (r.error === "taken") return reply({ code: "duel_taken", error: "Ce duel a déjà un adversaire" }, 409);
      return handlers.duels(installHash, body);
    },

    /// Les duels du joueur, du plus récent au plus ancien, avec les scores du moment.
    async duels(installHash) {
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query(
        `select d.id, d.code, d.starts_at, d.ends_at, d.challenger_id = $1 as mine,
                case when d.challenger_id = $1 then po.pseudo else pc.pseudo end as opponent,
                d.opponent_id is not null as joined,
                case when d.starts_at is null then 0 else public.points_between($1, d.starts_at, d.ends_at) end as my_points,
                case when d.starts_at is null then 0 else public.points_between(
                  case when d.challenger_id = $1 then d.opponent_id else d.challenger_id end,
                  d.starts_at, d.ends_at) end as their_points
           from public.duels d
           join public.players pc on pc.id = d.challenger_id
           left join public.players po on po.id = d.opponent_id
          where d.challenger_id = $1 or d.opponent_id = $1
          order by d.created_at desc limit 20`, [player]);
      const nowMs = now().getTime();
      return reply({
        duels: rows.map((d) => ({
          id: d.id, code: d.joined ? null : d.code, joined: d.joined,
          opponent: d.opponent ?? null, my_points: d.my_points, their_points: d.their_points,
          starts_at: d.starts_at ? new Date(d.starts_at).toISOString() : null,
          ends_at: d.ends_at ? new Date(d.ends_at).toISOString() : null,
          finished: d.ends_at ? new Date(d.ends_at).getTime() <= nowMs : false,
        })),
      });
    },

    /// Les cartes du joueur, pour les redessiner sur un autre iPhone (restauration par le
    /// compte Apple). Sans les photos : elles ne quittent jamais l'appareil.
    async garage(installHash) {
      const player = await playerOf(installHash);
      // Casts : un bigint revient en chaîne de pg, en BigInt de PGlite. Les valeurs sont
      // bornées à l'écriture (0xFFFFFF, MAX_SAFE_INTEGER) et tiennent dans un nombre JSON.
      const { rows } = await deps.db!.query(
        `select id, vehicle_id, country, caught_at, tier, points, first_spot, location_verified, vehicle_verified,
                scan_id, serial, paint::int as paint, price_low::float8 as price_low,
                price_high::float8 as price_high, price_currency
           from public.catches where player_id = $1 and deleted_at is null order by caught_at`, [player]);
      return reply({
        catches: rows.map((c) => ({
          id: c.id, vehicle_id: c.vehicle_id, country: c.country,
          caught_at: new Date(c.caught_at).toISOString(),
          tier: c.tier, points: c.points, first_spot: c.first_spot,
          location_verified: c.location_verified, vehicle_verified: c.vehicle_verified,
          scan_id: c.scan_id ?? null, serial: c.serial ?? null, paint: c.paint ?? null,
          price: c.price_low == null || c.price_high == null || c.price_currency == null ? null
            : { low: c.price_low, high: c.price_high, currency: c.price_currency },
        })),
      });
    },
  };

  return async function handleSocial(action: string, installHash: string, body: Record<string, unknown>): Promise<Response> {
    if (!deps.db) return unavailable();
    try {
      return await handlers[action](installHash, body);
    } catch (error) {
      console.error(`social ${action} failed`, error instanceof Error ? error.message : error);
      return unavailable();
    }
  };
}
