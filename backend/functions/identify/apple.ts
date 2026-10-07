// Vérification du jeton Sign in with Apple (JWT RS256 signé par Apple).
//
// On vérifie la signature avec les clés publiques d'Apple, l'émetteur, le destinataire
// (notre bundle) et l'expiration. On n'en garde que `sub`, l'identifiant propre à notre
// équipe : ni l'e-mail ni le nom, que Spog n'a aucune raison de connaître.

import { createPublicKey, verify, type JsonWebKey } from "node:crypto";

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
export const BUNDLE_ID = "com.mandalore-group.spog";
const MAX_TOKEN = 4_000;

export type AppleResult = { ok: true; sub: string } | { ok: false; reason: string };

interface AppleKey extends JsonWebKey { kid: string }

function segment(part: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

export function createAppleVerifier(fetchFn: typeof fetch, options: { now?: () => number } = {}) {
  let cache: { keys: AppleKey[]; at: number } | null = null;
  const now = options.now ?? Date.now;

  // Les clés d'Apple tournent rarement : une heure de cache, et un rechargement forcé si
  // le jeton annonce une clé inconnue (rotation survenue entre-temps).
  async function keys(force: boolean): Promise<AppleKey[]> {
    if (!force && cache && now() - cache.at < 3_600_000) return cache.keys;
    const response = await fetchFn(APPLE_KEYS_URL);
    if (!response.ok) throw new Error(`apple keys ${response.status}`);
    const body = await response.json() as { keys: AppleKey[] };
    cache = { keys: body.keys, at: now() };
    return body.keys;
  }

  return async function verifyAppleToken(token: unknown): Promise<AppleResult> {
    if (typeof token !== "string" || token.length > MAX_TOKEN) return { ok: false, reason: "missing" };
    const parts = token.split(".");
    if (parts.length !== 3) return { ok: false, reason: "malformed" };
    try {
      const header = segment(parts[0]);
      const claims = segment(parts[1]);
      if (header.alg !== "RS256" || typeof header.kid !== "string") return { ok: false, reason: "bad_header" };
      let key = (await keys(false)).find((k) => k.kid === header.kid);
      if (!key) key = (await keys(true)).find((k) => k.kid === header.kid);
      if (!key) return { ok: false, reason: "unknown_key" };
      const signed = verify("RSA-SHA256", Buffer.from(`${parts[0]}.${parts[1]}`),
        createPublicKey({ key, format: "jwk" }), Buffer.from(parts[2], "base64url"));
      if (!signed) return { ok: false, reason: "bad_signature" };
      if (claims.iss !== APPLE_ISSUER) return { ok: false, reason: "issuer" };
      if (claims.aud !== BUNDLE_ID) return { ok: false, reason: "audience" };
      if (typeof claims.exp !== "number" || claims.exp * 1000 < now()) return { ok: false, reason: "expired" };
      if (typeof claims.sub !== "string" || !claims.sub) return { ok: false, reason: "subject" };
      return { ok: true, sub: claims.sub };
    } catch (error) {
      console.error("apple token invalid", error instanceof Error ? error.message : error);
      return { ok: false, reason: "invalid" };
    }
  };
}
