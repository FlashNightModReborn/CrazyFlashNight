import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import {
  loadLocalPrimeMagicSeed,
  loadLocalSeedBankManifest,
  localSeedBinary,
} from "../examples/load-node-seeds.js";
import { decodePrimeMagicBinary, sha256Hex } from "../src/binary-seed.js";
import { assertCompleteMagic } from "./helpers.js";

function sha256(data: Uint8Array | string): string {
  return createHash("sha256").update(data).digest("hex");
}

function isPrimeByTrialDivision(value: number): boolean {
  if (!Number.isSafeInteger(value) || value < 2) return false;
  if ((value & 1) === 0) return value === 2;
  if (value % 3 === 0) return value === 3;
  for (let divisor = 5; divisor * divisor <= value; divisor += 6) {
    if (value % divisor === 0 || value % (divisor + 2) === 0) return false;
  }
  return true;
}

test("all eight packaged PM19 seeds independently pass runtime-bank audit", (context) => {
  const manifest = loadLocalSeedBankManifest();
  assert.equal(manifest.format, "prime-magic-runtime-bank/v1");
  assert.equal(manifest.size, 19);
  assert.equal(manifest.magicSum, 190_000_361);
  assert.equal(manifest.seeds.length, 8);

  const firstSortedValues: number[] = [];
  const centerValues = new Set<number>();
  const primalityCache = new Map<number, boolean>();

  for (const entry of manifest.seeds) {
    const binary = localSeedBinary(entry.index);
    assert.equal(binary.byteLength, entry.binaryBytes);
    assert.equal(sha256(binary), entry.binarySha256, `binary SHA seed ${entry.index}`);

    const seed = loadLocalPrimeMagicSeed(entry.index);
    assert.equal(seed.size, manifest.size);
    assert.equal(seed.magicSum, manifest.magicSum);
    assert.equal(seed.checksum, `sha256:${entry.canonicalChecksum}`);
    assert.equal(seed.values[9 * 19 + 9], entry.centerValue);
    assertCompleteMagic(seed.values, seed);

    const canonicalBytes = JSON.stringify({
      magicSum: seed.magicSum,
      size: seed.size,
      values: Array.from(seed.values),
    });
    assert.equal(sha256(canonicalBytes), entry.canonicalChecksum, `canonical SHA seed ${entry.index}`);

    const sortedValues = Array.from(seed.values).sort((left, right) => left - right);
    if (entry.index === 0) {
      firstSortedValues.push(...sortedValues);
    } else {
      assert.deepEqual(sortedValues, firstSortedValues, `element set seed ${entry.index}`);
    }
    for (const value of seed.values) {
      let prime = primalityCache.get(value);
      if (prime === undefined) {
        prime = isPrimeByTrialDivision(value);
        primalityCache.set(value, prime);
      }
      assert.equal(prime, true, `composite ${value} in seed ${entry.index}`);
    }
    centerValues.add(entry.centerValue);
  }

  assert.equal(primalityCache.size, 361, "seed bank should preserve one 361-prime set");
  assert.equal(centerValues.size, 8, "distinct centers prove eight disjoint runtime orbits");
  context.diagnostic("8 complete prime-magic seeds; 8 distinct centers; 5,945,425,920 total states");
});

test("PM19 decoder rejects corrupt headers/lengths and Web Crypto matches binary hash", async () => {
  const manifest = loadLocalSeedBankManifest();
  const entry = manifest.seeds[0]!;
  const binary = localSeedBinary(0);
  assert.equal(await sha256Hex(binary), entry.binarySha256);

  const badMagic = new Uint8Array(binary);
  badMagic[0] = badMagic[0]! ^ 0xff;
  assert.throws(() => decodePrimeMagicBinary(badMagic, entry.canonicalChecksum), /magic/);
  const badVersion = new Uint8Array(binary);
  badVersion[4] = 2;
  assert.throws(() => decodePrimeMagicBinary(badVersion, entry.canonicalChecksum), /version/);
  assert.throws(
    () => decodePrimeMagicBinary(binary.subarray(0, binary.length - 4), entry.canonicalChecksum),
    /length/,
  );
  assert.throws(() => decodePrimeMagicBinary(binary, "not-a-checksum"), /SHA-256/);
});
