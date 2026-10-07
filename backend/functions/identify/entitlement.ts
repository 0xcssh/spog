// Vérification de l'abonnement côté serveur.
//
// L'app envoie la transaction StoreKit 2 active (`entitlement`, JWS signé par
// Apple). On vérifie, sans AUCUN appel réseau (la racine Apple est embarquée) :
//   1. la chaîne x5c : feuille ← intermédiaire ← Apple Root CA - G3, avec les
//      OID marqueurs qu'Apple pose sur les certificats StoreKit (sans eux,
//      n'importe quel certificat délivré sous la racine Apple G3 — un certificat
//      de développeur, par exemple — pourrait signer un faux abonnement) ;
//   2. la signature du JWS avec la clé de la feuille ;
//   3. le contenu : bundle, produit, environnement, expiration, révocation.
// Production et Sandbox (revue Apple, TestFlight) sont acceptés ; la Sandbox
// peut être coupée avec ALLOW_SANDBOX=false une fois l'app publiée.

import { X509Certificate, createHash, verify as cryptoVerify } from "node:crypto";

const BUNDLE_ID = "com.mandalore-group.spog";
const PRODUCT_IDS = new Set([
  "com.mandaloregroup.spog.premium.yearly",
  "com.mandaloregroup.spog.premium.monthly",
]);
// Tolérance sur l'expiration (horloges, renouvellement en cours de traitement).
const EXPIRY_GRACE_MS = 10 * 60 * 1000;
// Un JWS StoreKit fait ~5 Ko (3 certificats + transaction) : au-delà, c'est anormal.
const MAX_JWS_LENGTH = 20_000;

// Apple Root CA - G3 (DER, base64), publiée sur
// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer — valide jusqu'en 2039.
// Embarquée plutôt que téléchargée : une panne réseau vers apple.com ne doit
// pas transformer tous les abonnés en « abonnement requis ».
const APPLE_ROOT_CA_G3_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";
// Empreinte SHA-256 publiée par Apple : garde-fou contre une altération de la constante.
export const APPLE_ROOT_CA_G3_SHA256 = "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179";

// OID marqueurs Apple, encodés DER (tag 06, longueur 0A) :
//   1.2.840.113635.100.6.11.1 — feuille « signature de reçus App Store »
//   1.2.840.113635.100.6.2.1  — intermédiaire « Apple Worldwide Developer Relations »
const LEAF_MARKER_OID = Buffer.from("060a2a864886f76364060b01", "hex");
const INTERMEDIATE_MARKER_OID = Buffer.from("060a2a864886f76364060201", "hex");

let appleRoot: X509Certificate | null = null;

/** Racine Apple embarquée, vérifiée contre son empreinte publiée. */
export function appleRootCertificate(): X509Certificate {
  if (!appleRoot) {
    const der = Buffer.from(APPLE_ROOT_CA_G3_B64, "base64");
    const fingerprint = createHash("sha256").update(der).digest("hex").toUpperCase();
    if (fingerprint !== APPLE_ROOT_CA_G3_SHA256) {
      throw new Error("Apple root CA: empreinte inattendue");
    }
    appleRoot = new X509Certificate(der);
  }
  return appleRoot;
}

function decodeSegment(segment: string): Record<string, unknown> {
  const value = JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("segment");
  return value as Record<string, unknown>;
}

export type EntitlementResult =
  | { ok: true; productId: string; environment: string; originalTransactionId: string }
  | { ok: false; reason: string };

export interface VerifyOptions {
  /** Racine de confiance (tests uniquement ; défaut : Apple Root CA - G3). */
  trustedRoot?: X509Certificate;
  /** Horloge (tests uniquement). */
  now?: number;
  /** Accepter les transactions Sandbox (TestFlight, revue Apple). Défaut : true. */
  allowSandbox?: boolean;
}

export async function verifyEntitlement(jws: unknown, options: VerifyOptions = {}): Promise<EntitlementResult> {
  if (typeof jws !== "string" || jws.length > MAX_JWS_LENGTH) {
    return { ok: false, reason: "missing" };
  }
  const parts = jws.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
    return { ok: false, reason: "missing" };
  }
  const [h, p, sig] = parts;
  try {
    const header = decodeSegment(h);
    const x5c = header.x5c;
    if (header.alg !== "ES256" || !Array.isArray(x5c) || x5c.length !== 3 || !x5c.every((c) => typeof c === "string")) {
      return { ok: false, reason: "bad_header" };
    }
    const [leaf, intermediate, root] = (x5c as string[]).map((c) => new X509Certificate(Buffer.from(c, "base64")));
    const trustedRoot = options.trustedRoot ?? appleRootCertificate();

    // La racine fournie doit être exactement la racine Apple, et chaque maillon
    // doit être signé par le suivant et valide à cette date.
    if (!root.raw.equals(trustedRoot.raw)) {
      return { ok: false, reason: "untrusted_root" };
    }
    const now = options.now ?? Date.now();
    const valid = (c: X509Certificate) => Date.parse(c.validFrom) <= now && now <= Date.parse(c.validTo);
    const chainOK =
      valid(leaf) && valid(intermediate) &&
      intermediate.ca && !leaf.ca &&
      leaf.checkIssued(intermediate) && leaf.verify(intermediate.publicKey) &&
      intermediate.checkIssued(trustedRoot) && intermediate.verify(trustedRoot.publicKey);
    if (!chainOK) return { ok: false, reason: "bad_chain" };
    if (!leaf.raw.includes(LEAF_MARKER_OID) || !intermediate.raw.includes(INTERMEDIATE_MARKER_OID)) {
      return { ok: false, reason: "not_storekit" };
    }

    // Signature JWS ES256 : r||s brut (IEEE P1363) sur "header.payload".
    const signatureOK = cryptoVerify(
      "sha256", Buffer.from(`${h}.${p}`),
      { key: leaf.publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(sig, "base64url"),
    );
    if (!signatureOK) return { ok: false, reason: "bad_signature" };
    const tx = decodeSegment(p);

    if (tx.bundleId !== BUNDLE_ID) return { ok: false, reason: "bundle" };
    if (typeof tx.productId !== "string" || !PRODUCT_IDS.has(tx.productId)) return { ok: false, reason: "product" };
    const environment = String(tx.environment ?? "");
    const allowSandbox = options.allowSandbox ?? true;
    if (environment !== "Production" && !(environment === "Sandbox" && allowSandbox)) {
      return { ok: false, reason: "environment" };
    }
    if (tx.revocationDate != null) return { ok: false, reason: "revoked" };
    // expiresDate : millisecondes depuis l'epoch (format StoreKit 2).
    if (typeof tx.expiresDate !== "number" || tx.expiresDate + EXPIRY_GRACE_MS < now) {
      return { ok: false, reason: "expired" };
    }
    const originalTransactionId = String(tx.originalTransactionId ?? tx.transactionId ?? "");
    return { ok: true, productId: tx.productId, environment, originalTransactionId };
  } catch (error) {
    console.error("entitlement verification failed", error instanceof Error ? error.message : error);
    return { ok: false, reason: "invalid" };
  }
}
