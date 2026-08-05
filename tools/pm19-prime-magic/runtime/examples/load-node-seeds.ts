import { readFileSync } from "node:fs";
import { decodePrimeMagicBinary } from "../src/binary-seed.js";
import type { PrimeMagicSeedBankManifest } from "../src/binary-seed.js";
import type { PrimeMagicSeed } from "../src/types.js";

const assetsDirectory = new URL("../../web/assets/", import.meta.url);

export function loadLocalSeedBankManifest(): PrimeMagicSeedBankManifest {
  const text = readFileSync(new URL("seed-bank.json", assetsDirectory), "utf8");
  return JSON.parse(text) as PrimeMagicSeedBankManifest;
}

export function loadLocalPrimeMagicSeed(index = 0): PrimeMagicSeed {
  const manifest = loadLocalSeedBankManifest();
  const entry = manifest.seeds.find((candidate) => candidate.index === index);
  if (entry === undefined) throw new RangeError(`seed index ${index} is unavailable`);
  const filename = entry.url.slice(entry.url.lastIndexOf("/") + 1);
  const bytes = readFileSync(new URL(filename, assetsDirectory));
  return decodePrimeMagicBinary(bytes, entry.canonicalChecksum);
}

export function localSeedBinary(index = 0): Uint8Array {
  const manifest = loadLocalSeedBankManifest();
  const entry = manifest.seeds.find((candidate) => candidate.index === index);
  if (entry === undefined) throw new RangeError(`seed index ${index} is unavailable`);
  const filename = entry.url.slice(entry.url.lastIndexOf("/") + 1);
  return readFileSync(new URL(filename, assetsDirectory));
}
