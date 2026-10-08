// Fonction Neon "identify" — relais unique entre l'app iOS Spog et OpenAI.
// La clé OpenAI vit ici (variable d'environnement OPENAI_API_KEY), jamais dans l'app.
// Contrat et logique : voir handler.ts. Ce fichier ne fait que brancher
// l'environnement réel (variables, base Neon, fetch) sur le handler.

import { attachDatabasePool } from "@neon/functions";
import { Pool } from "pg";
import { verifyEntitlement } from "./entitlement";
import { createHandler } from "./handler";
import { createArtStore, createSampleStore } from "./storage";
import { testersFrom } from "./develop";
import { createAppleVerifier } from "./apple";

// Transactions Sandbox (TestFlight, revue Apple) acceptées par défaut. À couper
// avec ALLOW_SANDBOX=false une fois l'app publiée, si l'abus se présente.
const ALLOW_SANDBOX = process.env.ALLOW_SANDBOX !== "false";

// Base Neon de la branche (DATABASE_URL injectée par Neon Functions). Timeouts courts :
// une base injoignable doit répondre « indisponible » vite, pas faire attendre le joueur
// devant son viseur. attachDatabasePool absorbe les déconnexions de clients inactifs.
const pool = process.env.DATABASE_URL
  ? new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 5,
    connectionTimeoutMillis: 3000,
    query_timeout: 3000,
    idleTimeoutMillis: 30_000,
  })
  : null;
if (pool) attachDatabasePool(pool);

const handle = createHandler({
  openaiKey: process.env.OPENAI_API_KEY,
  db: pool,
  fetch: (input, init) => fetch(input, init),
  verifyEntitlement: (jws) => verifyEntitlement(jws, { allowSandbox: ALLOW_SANDBOX }),
  // Photos d'entraînement, avec l'accord du joueur. Coupable sans redéployer le code :
  // TRAINING_ENABLED=false au déploiement.
  samples: process.env.TRAINING_ENABLED === "false" ? null : createSampleStore(),
  developTesters: testersFrom(process.env.DEVELOP_TESTERS),
  verifyApple: createAppleVerifier((input, init) => fetch(input, init)),
  model: process.env.OPENAI_MODEL,
  // Rendus des cibles du pack, mis en cache dans le compartiment privé `art`. Coupable
  // sans redéployer le code : ART_ENABLED=false au déploiement.
  art: process.env.ART_ENABLED === "false" ? null : createArtStore(),
});

export default { fetch: handle };
