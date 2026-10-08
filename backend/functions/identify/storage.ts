// Accès au stockage Neon (compatible S3) : compartiment `training` (photos d'entraînement)
// et compartiment `art` (rendus studio des cibles du pack, voir art.ts).
//
// Aucun secret à gérer : Neon injecte AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
// AWS_ENDPOINT_URL_S3 et AWS_REGION dans la fonction dès que le stockage est actif sur
// la branche. Le SDK AWS les lit tout seul ; seul le style d'adresse est imposé.

import { S3Client, PutObjectCommand, DeleteObjectsCommand, GetObjectCommand } from "@aws-sdk/client-s3";

export const TRAINING_BUCKET = "training";
export const ART_BUCKET = "art";

export interface SampleStore {
  put(key: string, bytes: Buffer): Promise<void>;
  remove(keys: string[]): Promise<void>;
}

/// Cache des rendus : `get` rend null quand l'objet n'existe pas encore.
export interface ArtStore {
  get(key: string): Promise<Buffer | null>;
  put(key: string, bytes: Buffer): Promise<void>;
}

// Un seul client pour les deux compartiments : il ne porte que la connexion.
let sharedClient: S3Client | null = null;
function client(): S3Client {
  sharedClient ??= new S3Client({ forcePathStyle: true });
  return sharedClient;
}

export function createSampleStore(): SampleStore | null {
  if (!process.env.AWS_ENDPOINT_URL_S3) return null;
  return {
    async put(key, bytes) {
      await client().send(new PutObjectCommand({
        Bucket: TRAINING_BUCKET, Key: key, Body: bytes, ContentType: "image/jpeg",
      }));
    },
    async remove(keys) {
      // DeleteObjects accepte 1 000 clés par appel.
      for (let i = 0; i < keys.length; i += 1000) {
        await client().send(new DeleteObjectsCommand({
          Bucket: TRAINING_BUCKET,
          Delete: { Objects: keys.slice(i, i + 1000).map((Key) => ({ Key })), Quiet: true },
        }));
      }
    },
  };
}

export function createArtStore(): ArtStore | null {
  if (!process.env.AWS_ENDPOINT_URL_S3) return null;
  return {
    async get(key) {
      try {
        const out = await client().send(new GetObjectCommand({ Bucket: ART_BUCKET, Key: key }));
        if (!out.Body) return null;
        return Buffer.from(await out.Body.transformToByteArray());
      } catch (error) {
        // Objet absent : le cas normal du premier joueur qui ouvre ce modèle. Toute autre
        // erreur remonte, pour ne pas relancer une génération payante sur une panne.
        const name = (error as { name?: string })?.name;
        const status = (error as { $metadata?: { httpStatusCode?: number } })?.$metadata?.httpStatusCode;
        if (name === "NoSuchKey" || name === "NotFound" || status === 404) return null;
        throw error;
      }
    },
    async put(key, bytes) {
      await client().send(new PutObjectCommand({
        Bucket: ART_BUCKET, Key: key, Body: bytes, ContentType: "image/jpeg",
      }));
    },
  };
}
