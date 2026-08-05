import assert from "node:assert/strict";
import test from "node:test";
import { createNormalMagicFixture } from "../examples/normal-magic-fixture.js";
import {
  loadLocalPrimeMagicSeed,
  loadLocalSeedBankManifest,
} from "../examples/load-node-seeds.js";
import {
  acquireSharedFront,
  composeTransformsInto,
  createSharedOrbitViews,
  identityTransformInto,
  invertTransformInto,
  PrimeMagicOrbitEngine,
  PrimeMagicSeedBankOrbitEngine,
  releaseSharedFront,
  reversalCentralizerSize,
  Xoshiro128StarStar,
} from "../src/index.js";
import { assertCompleteMagic, makeTransform } from "./helpers.js";

test("19-order reversal centralizer has 9! * 2^9 elements", () => {
  assert.equal(reversalCentralizerSize(19), 185_794_560n);
  assert.equal(
    reversalCentralizerSize(19) * 4n,
    743_178_240n,
    "including one independent axis reversal and transpose",
  );
});

test("identity, sampled transforms, and full magic invariants", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  assertCompleteMagic(seed.values, seed);
  const engine = new PrimeMagicOrbitEngine(seed, 0x1234_5678_9abc_def0n);
  const identity = makeTransform(seed.size);
  identityTransformInto(identity);
  assert.equal(engine.validateTransform(identity), true);

  const output = new Uint32Array(seed.values.length);
  engine.applyTransformInto(identity, output);
  assert.deepEqual(output, seed.values);

  const sampled = makeTransform(seed.size);
  for (let iteration = 0; iteration < 2_000; iteration += 1) {
    sampled.transpose = engine.sampleTransformInto(
      sampled.rowPermutation,
      sampled.columnPermutation,
    );
    assert.equal(engine.validateTransform(sampled), true);
    engine.applyTransformInto(sampled, output);
    if ((iteration & 31) === 0) {
      assertCompleteMagic(output, seed);
    }
  }
});

test("transform set is closed and inverse composes to identity", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 77n);
  const first = makeTransform(seed.size);
  const second = makeTransform(seed.size);
  const composed = makeTransform(seed.size);
  const inverse = makeTransform(seed.size);
  const identity = makeTransform(seed.size);

  for (let iteration = 0; iteration < 10_000; iteration += 1) {
    first.transpose = engine.sampleTransformInto(first.rowPermutation, first.columnPermutation);
    second.transpose = engine.sampleTransformInto(second.rowPermutation, second.columnPermutation);
    composeTransformsInto(first, second, composed);
    assert.equal(engine.validateTransform(composed), true, "closure");

    invertTransformInto(first, inverse);
    assert.equal(engine.validateTransform(inverse), true, "inverse is legal");
    composeTransformsInto(first, inverse, identity);
    assert.equal(engine.validateTransform(identity), true);
    assert.equal(identity.transpose, false);
    for (let index = 0; index < seed.size; index += 1) {
      assert.equal(identity.rowPermutation[index], index);
      assert.equal(identity.columnPermutation[index], index);
    }
  }
});

test("composition convention agrees with sequential matrix actions", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 123n);
  const first = makeTransform(seed.size);
  const second = makeTransform(seed.size);
  const composed = makeTransform(seed.size);
  first.transpose = engine.sampleTransformInto(first.rowPermutation, first.columnPermutation);
  second.transpose = engine.sampleTransformInto(second.rowPermutation, second.columnPermutation);
  composeTransformsInto(first, second, composed);

  const afterFirst = new Uint32Array(seed.values.length);
  const afterSequential = new Uint32Array(seed.values.length);
  const afterComposed = new Uint32Array(seed.values.length);
  engine.applyTransformInto(first, afterFirst);
  const intermediateSeed = { ...seed, values: afterFirst };
  const intermediateEngine = new PrimeMagicOrbitEngine(intermediateSeed, 0n);
  intermediateEngine.applyTransformInto(second, afterSequential);
  engine.applyTransformInto(composed, afterComposed);
  assert.deepEqual(afterComposed, afterSequential);
});

test("same random seed is reproducible and PRNG state can be restored", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const first = new PrimeMagicOrbitEngine(seed, 0xfeed_face_cafe_beefn);
  const second = new PrimeMagicOrbitEngine(seed, 0xfeed_face_cafe_beefn);
  const firstOutput = new Uint32Array(seed.values.length);
  const secondOutput = new Uint32Array(seed.values.length);

  for (let iteration = 0; iteration < 10_000; iteration += 1) {
    first.nextInto(firstOutput);
    second.nextInto(secondOutput);
    assert.deepEqual(firstOutput, secondOutput);
  }

  const saved = new Uint32Array(4);
  first.saveRandomStateInto(saved);
  first.nextInto(firstOutput);
  first.restoreRandomState(saved);
  first.nextInto(secondOutput);
  assert.deepEqual(firstOutput, secondOutput);
});

test("xoshiro bounded sampler is deterministic and exercises every small bucket", () => {
  const first = new Xoshiro128StarStar(42n);
  const second = new Xoshiro128StarStar(42n);
  const counts = new Uint32Array(7);
  for (let index = 0; index < 100_000; index += 1) {
    const a = first.nextBounded(7);
    const b = second.nextBounded(7);
    assert.equal(a, b);
    counts[a] = counts[a]! + 1;
  }
  for (const count of counts) {
    assert.ok(count > 13_000 && count < 15_600, `unexpected bucket count ${count}`);
  }
});

test("n=5 sampler covers centralizer, independent axis reversal, and transpose uniformly", () => {
  const seed = createNormalMagicFixture(5);
  const engine = new PrimeMagicOrbitEngine(seed, 2026n);
  const transform = makeTransform(5);
  const counts = new Map<number, number>();
  const samples = 160_000;

  for (let iteration = 0; iteration < samples; iteration += 1) {
    transform.transpose = engine.sampleTransformInto(
      transform.rowPermutation,
      transform.columnPermutation,
    );
    let encoded = transform.transpose ? 5 ** 10 : 0;
    let multiplier = 1;
    for (let index = 0; index < 5; index += 1) {
      encoded += transform.rowPermutation[index]! * multiplier;
      multiplier *= 5;
    }
    for (let index = 0; index < 5; index += 1) {
      encoded += transform.columnPermutation[index]! * multiplier;
      multiplier *= 5;
    }
    counts.set(encoded, (counts.get(encoded) ?? 0) + 1);
  }

  const expected = samples / 32;
  let chiSquared = 0;
  for (const count of counts.values()) {
    const residual = count - expected;
    chiSquared += (residual * residual) / expected;
  }
  assert.equal(counts.size, 32);
  assert.ok(chiSquared < 80, `chi-squared ${chiSquared} is implausibly high for 31 dof`);
});

test("19-order duplicate rate agrees with sampling a 743,178,240-state orbit", (context) => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 0xabc0_1234n);
  const transform = makeTransform(19);
  const fingerprints = new Set<bigint>();
  const samples = 100_000;
  for (let iteration = 0; iteration < samples; iteration += 1) {
    transform.transpose = engine.sampleTransformInto(
      transform.rowPermutation,
      transform.columnPermutation,
    );
    let fingerprint = transform.transpose ? 1n : 0n;
    for (let index = 0; index < 19; index += 1) {
      fingerprint = (fingerprint << 5n) | BigInt(transform.rowPermutation[index]!);
    }
    for (let index = 0; index < 19; index += 1) {
      fingerprint = (fingerprint << 5n) | BigInt(transform.columnPermutation[index]!);
    }
    fingerprints.add(fingerprint);
  }
  const duplicates = samples - fingerprints.size;
  const expected = (samples * (samples - 1)) / (2 * 743_178_240);
  context.diagnostic(`duplicates=${duplicates}; birthday approximation=${expected.toFixed(2)}`);
  assert.ok(duplicates < 40, `duplicate count ${duplicates} is inconsistent with uniform sampling`);
});

test("double buffers alternate without creating new views", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 9n);
  const initial = engine.currentView();
  const secondBuffer = engine.nextView();
  const initialAgain = engine.nextView();
  const secondAgain = engine.nextView();
  assert.notEqual(initial, secondBuffer);
  assert.equal(initial, initialAgain);
  assert.equal(secondBuffer, secondAgain);
});

test("SharedArrayBuffer views pin and release the front buffer", () => {
  const shared = createSharedOrbitViews(361);
  assert.equal(shared.control.length, 3);
  Atomics.store(shared.control, 0, 0);
  assert.equal(acquireSharedFront(shared), shared.boards[0]);
  assert.equal(Atomics.load(shared.control, 2), 1);
  releaseSharedFront(shared);
  assert.equal(Atomics.load(shared.control, 2), 0);
  Atomics.store(shared.control, 0, 1);
  assert.equal(acquireSharedFront(shared), shared.boards[1]);
  assert.equal(Atomics.load(shared.control, 2), 2);
  releaseSharedFront(shared);
});

test("eight-seed bank selection is reproducible and nearly uniform", () => {
  const manifest = loadLocalSeedBankManifest();
  const seeds = manifest.seeds.map((entry) => loadLocalPrimeMagicSeed(entry.index));
  const first = new PrimeMagicSeedBankOrbitEngine(seeds, 0x8888n);
  const second = new PrimeMagicSeedBankOrbitEngine(seeds, 0x8888n);
  const firstOutput = new Uint32Array(361);
  const secondOutput = new Uint32Array(361);
  const counts = new Uint32Array(8);
  const samples = 80_000;
  for (let iteration = 0; iteration < samples; iteration += 1) {
    first.nextInto(firstOutput);
    second.nextInto(secondOutput);
    assert.deepEqual(firstOutput, secondOutput);
    assert.equal(first.lastSeedIndex(), second.lastSeedIndex());
    const selected = first.lastSeedIndex();
    counts[selected] = counts[selected]! + 1;
    assert.equal(firstOutput[9 * 19 + 9], manifest.seeds[selected]!.centerValue);
  }
  const expected = samples / 8;
  let chiSquared = 0;
  for (const count of counts) {
    const residual = count - expected;
    chiSquared += (residual * residual) / expected;
  }
  assert.ok(chiSquared < 30, `seed selector chi-squared ${chiSquared} is unexpectedly high`);
});

test("validator rejects nonsynchronous, duplicate, and noncommuting permutations", () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 1n);
  const transform = makeTransform(seed.size);
  identityTransformInto(transform);

  transform.columnPermutation[0] = 1;
  assert.equal(engine.validateTransform(transform), false, "row and column must match");
  identityTransformInto(transform);
  transform.rowPermutation[0] = 1;
  transform.columnPermutation[0] = 1;
  assert.equal(engine.validateTransform(transform), false, "duplicates are forbidden");
  identityTransformInto(transform);
  transform.rowPermutation[0] = 1;
  transform.rowPermutation[1] = 0;
  transform.columnPermutation.set(transform.rowPermutation);
  assert.equal(engine.validateTransform(transform), false, "permutation must commute with reversal");
});
