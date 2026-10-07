// Accès au compartiment `training` du stockage Neon (compatible S3).
//
// Aucun secret à gérer : Neon injecte AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
// AWS_ENDPOINT_URL_S3 et AWS_REGION dans la fonction dès que le stockage est actif sur
// la branche. Le SDK AWS les lit tout seul ; seul le style d'adresse est imposé.

import { S3Client, PutObjectCommand, DeleteObjectsCommand } from "@aws-sdk/client-s3";

export const TRAINING_BUCKET = "training";

export interface SampleStore {
  put(key: string, bytes: Buffer): Promise<void>;
  remove(keys: string[]): Promise<void>;
}

export function createSampleStore(): SampleStore | null {
  if (!process.env.AWS_ENDPOINT_URL_S3) return null;
  const client = new S3Client({ forcePathStyle: true });
  return {
    async put(key, bytes) {
      await client.send(new PutObjectCommand({
        Bucket: TRAINING_BUCKET, Key: key, Body: bytes, ContentType: "image/jpeg",
      }));
    },
    async remove(keys) {
      // DeleteObjects accepte 1 000 clés par appel.
      for (let i = 0; i < keys.length; i += 1000) {
        await client.send(new DeleteObjectsCommand({
          Bucket: TRAINING_BUCKET,
          Delete: { Objects: keys.slice(i, i + 1000).map((Key) => ({ Key })), Quiet: true },
        }));
      }
    },
  };
}
