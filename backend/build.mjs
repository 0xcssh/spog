// Bundle + zip de la fonction `identify` au format attendu par Neon Functions
// (dist/index.mjs ESM, banner require/__dirname pour les dépendances CJS comme pg).
import { build } from "esbuild";
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { deflateRawSync, crc32 } from "node:zlib";

const banner = "import{createRequire as ___cr}from'module';import{fileURLToPath as ___f}from'url';import{dirname as ___d}from'path';const require=___cr(import.meta.url);const __filename=___f(import.meta.url);const __dirname=___d(__filename);";
mkdirSync("dist", { recursive: true });
await build({
  entryPoints: ["functions/identify/index.ts"],
  bundle: true, platform: "node", target: "node24", format: "esm",
  banner: { js: banner }, outfile: "dist/index.mjs", logLevel: "info",
  minify: true, legalComments: "none",
  // pg-native est optionnel (pg retombe sur son client JS) : ne pas l'embarquer.
  external: ["pg-native"],
});

// Zip minimal (une entrée, deflate) sans dépendance externe. Date DOS fixe
// 1980-01-01 (0x21) : un champ date à 0 (mois 0) est invalide pour certains outils.
const DOS_DATE = 0x21;
const data = readFileSync("dist/index.mjs");
const name = Buffer.from("index.mjs");
const comp = deflateRawSync(data);
const crc = crc32(data);
const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4);
local.writeUInt16LE(8, 8); local.writeUInt16LE(DOS_DATE, 12); local.writeUInt32LE(crc, 14); local.writeUInt32LE(comp.length, 18);
local.writeUInt32LE(data.length, 22); local.writeUInt16LE(name.length, 26);
const central = Buffer.alloc(46); central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4);
central.writeUInt16LE(20, 6); central.writeUInt16LE(8, 10); central.writeUInt16LE(DOS_DATE, 14); central.writeUInt32LE(crc, 16);
central.writeUInt32LE(comp.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(name.length, 28);
const offset = local.length + name.length + comp.length;
const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
end.writeUInt32LE(central.length + name.length, 12); end.writeUInt32LE(offset, 16);
writeFileSync("dist/function.zip", Buffer.concat([local, name, comp, central, name, end]));
console.log(`dist/function.zip (${data.length} → ${comp.length} bytes)`);
