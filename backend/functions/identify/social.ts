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
//   me · set_pseudo · apple_link · catch · reassign · delete_catch · league · garage

import { resolve } from "./catalog";
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

export const SOCIAL_ACTIONS = ["me", "set_pseudo", "apple_link", "catch", "reassign", "delete_catch", "league", "garage"];

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
      return reply({ ...result, vehicle_verified: verified,
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

    async garage(installHash) {
      const player = await playerOf(installHash);
      const { rows } = await deps.db!.query(
        `select id, vehicle_id, country, caught_at, tier, points, first_spot, location_verified, vehicle_verified
           from public.catches where player_id = $1 and deleted_at is null order by caught_at`, [player]);
      return reply({ catches: rows });
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
